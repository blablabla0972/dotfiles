#include "cod29/ipc_server.hpp"

#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>
#include <poll.h>

#include <cstdlib>
#include <cstring>
#include <algorithm>
#include <sstream>
#include <json-c/json.h>
#include <cmath>
#include <limits>
#include <memory>
#include <format>
#include <iostream>
#include <unordered_map>

namespace Cod29 {

static std::string resolveDefaultSocketPath() {
    const char* xdg = std::getenv("XDG_RUNTIME_DIR");
    const char* his = std::getenv("HYPRLAND_INSTANCE_SIGNATURE");

    if (xdg && his) {
        return std::string(xdg) + "/hypr/" + his + "/cod29.sock";
    }
    if (xdg) {
        return std::string(xdg) + "/hypr-cod29.sock";
    }
    return "/tmp/hypr-cod29.sock";
}

IpcServer::IpcServer(std::string socketPath) noexcept
    : m_socketPath(socketPath.empty() ? resolveDefaultSocketPath() : std::move(socketPath)) {}

IpcServer::~IpcServer() noexcept {
    stop();
}

bool IpcServer::start() noexcept {
    if (m_running.load()) return true;

    struct stat existing{};
    if (lstat(m_socketPath.c_str(), &existing) == 0) {
        if (!S_ISSOCK(existing.st_mode) || existing.st_uid != geteuid())
            return false;
        sockaddr_un probeAddress{};
        probeAddress.sun_family = AF_UNIX;
        if (m_socketPath.size() >= sizeof(probeAddress.sun_path))
            return false;
        std::strcpy(probeAddress.sun_path, m_socketPath.c_str());
        const int probe = socket(AF_UNIX, SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
        if (probe < 0)
            return false;
        const int connected = connect(probe, reinterpret_cast<sockaddr*>(&probeAddress), sizeof(probeAddress));
        const int error = errno;
        close(probe);
        if (connected == 0 || (error != ECONNREFUSED && error != ENOENT))
            return false;
        if (unlink(m_socketPath.c_str()) < 0 && errno != ENOENT)
            return false;
    }

    m_serverFd = socket(AF_UNIX, SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
    if (m_serverFd < 0) {
        return false;
    }

    // Set non-blocking
    int flags = fcntl(m_serverFd, F_GETFL, 0);
    if (flags >= 0) {
        fcntl(m_serverFd, F_SETFL, flags | O_NONBLOCK);
    }

    struct sockaddr_un addr{};
    addr.sun_family = AF_UNIX;
    if (m_socketPath.length() >= sizeof(addr.sun_path)) {
        close(m_serverFd);
        m_serverFd = -1;
        return false;
    }
    std::strncpy(addr.sun_path, m_socketPath.c_str(), sizeof(addr.sun_path) - 1);

    if (bind(m_serverFd, reinterpret_cast<struct sockaddr*>(&addr), sizeof(addr)) < 0) {
        close(m_serverFd);
        m_serverFd = -1;
        return false;
    }

    if (chmod(m_socketPath.c_str(), 0600) < 0 || listen(m_serverFd, 5) < 0) {
        close(m_serverFd);
        m_serverFd = -1;
        unlink(m_socketPath.c_str());
        return false;
    }

    m_running.store(true);
    m_serverThread = std::thread(&IpcServer::serverLoop, this);
    return true;
}

void IpcServer::stop() noexcept {
    if (!m_running.exchange(false)) {
        return;
    }

    if (m_serverThread.joinable()) {
        m_serverThread.join();
    }

    std::lock_guard<std::mutex> lock(m_clientsMutex);
    for (int fd : m_clientFds) {
        if (fd >= 0) {
            ::close(fd);
        }
    }
    m_clientFds.clear();
    m_clientCards.clear();

    if (m_serverFd >= 0) {
        ::close(m_serverFd);
        m_serverFd = -1;
    }

    unlink(m_socketPath.c_str());
}

bool IpcServer::isRunning() const noexcept {
    return m_running.load();
}

const std::string& IpcServer::getSocketPath() const noexcept {
    return m_socketPath;
}

size_t IpcServer::getConnectedClientCount() const noexcept {
    std::lock_guard<std::mutex> lock(m_clientsMutex);
    return m_clientFds.size();
}

void IpcServer::broadcastShowStrip(uint64_t windowToken) noexcept {
    sendToAllClients(std::format("SHOW_STRIP {:x}\n", windowToken));
}

void IpcServer::broadcastHideStrip() noexcept {
    sendToAllClients("HIDE_STRIP\n");
}

void IpcServer::broadcastTargetChanged(int targetWorkspaceId) noexcept {
    sendToAllClients("TARGET_CHANGED " + std::to_string(targetWorkspaceId) + "\n");
}

void IpcServer::broadcastReset() noexcept {
    sendToAllClients("RESET\n");
}

void IpcServer::sendToAllClients(const std::string& line) noexcept {
    std::lock_guard<std::mutex> lock(m_clientsMutex);
    if (line.starts_with("SHOW_STRIP ") || line == "HIDE_STRIP\n" || line == "RESET\n")
        m_stripMessage = line;

    for (int fd : m_clientFds) {
        if (fd < 0) continue;
        ssize_t sent = ::send(fd, line.c_str(), line.length(), MSG_NOSIGNAL);
        // A truncated command cannot be recovered; let the socket thread retire this client.
        if (sent != static_cast<ssize_t>(line.size()))
            ::shutdown(fd, SHUT_RDWR);
    }
}

void IpcServer::cleanupClient(int clientFd) noexcept {
    if (clientFd < 0) return;

    {
        std::lock_guard<std::mutex> lock(m_clientsMutex);
        auto it = std::find(m_clientFds.begin(), m_clientFds.end(), clientFd);
        if (it != m_clientFds.end()) {
            m_clientFds.erase(it);
            ::close(clientFd);
        }
    }
    if (m_clientCards.erase(clientFd))
        publishCards();
}

void IpcServer::publishCards() noexcept {
    std::vector<WorkspaceCard> cards;
    for (const auto& [fd, bounds] : m_clientCards)
        cards.insert(cards.end(), bounds.begin(), bounds.end());
    if (m_onSetCards)
        m_onSetCards(cards);
}

std::vector<WorkspaceCard> IpcServer::parseBoundsJson(const std::string& json) noexcept {
    if (json.size() > 65536)
        return {};
    std::unique_ptr<json_tokener, decltype(&json_tokener_free)> parser(json_tokener_new(), json_tokener_free);
    if (!parser)
        return {};
    json_tokener_set_flags(parser.get(), JSON_TOKENER_STRICT);
    std::unique_ptr<json_object, decltype(&json_object_put)> root(
        json_tokener_parse_ex(parser.get(), json.data(), json.size()), json_object_put);
    if (json_tokener_get_error(parser.get()) != json_tokener_success ||
        json_tokener_get_parse_end(parser.get()) != json.size() || !json_object_is_type(root.get(), json_type_array) ||
        json_object_array_length(root.get()) > 256)
        return {};

    const auto number = [](json_object* value, double& result) {
        if (!value || (!json_object_is_type(value, json_type_int) && !json_object_is_type(value, json_type_double)))
            return false;
        result = json_object_get_double(value);
        return std::isfinite(result) && std::abs(result) <= 1000000;
    };
    std::vector<WorkspaceCard> cards;
    for (size_t i = 0; i < json_object_array_length(root.get()); ++i) {
        auto* item = json_object_array_get_idx(root.get(), i);
        if (!json_object_is_type(item, json_type_object))
            return {};
        auto* id = json_object_object_get(item, "id");
        if (!json_object_is_type(id, json_type_int) || json_object_get_int64(id) <= 0 ||
            json_object_get_int64(id) > std::numeric_limits<int>::max())
            return {};
        WorkspaceCard card{.id = json_object_get_int(id)};
        if (!number(json_object_object_get(item, "x"), card.x) || !number(json_object_object_get(item, "y"), card.y) ||
            !number(json_object_object_get(item, "w"), card.w) || !number(json_object_object_get(item, "h"), card.h) ||
            card.w <= 0 || card.h <= 0)
            return {};
        if (auto* preview = json_object_object_get(item, "preview")) {
            if (!json_object_is_type(preview, json_type_array) || json_object_array_length(preview) != 4 ||
                !number(json_object_array_get_idx(preview, 0), card.preview.x) ||
                !number(json_object_array_get_idx(preview, 1), card.preview.y) ||
                !number(json_object_array_get_idx(preview, 2), card.preview.w) ||
                !number(json_object_array_get_idx(preview, 3), card.preview.h) || card.preview.w <= 0 || card.preview.h <= 0)
                return {};
        }
        cards.push_back(card);
    }
    return cards;
}

void IpcServer::handleClientMessage(int clientFd, const std::string& line) noexcept {
    if (line.empty()) return;

    if (line == "STRIP_READY") {
        std::lock_guard<std::mutex> lock(m_clientsMutex);
        if (::send(clientFd, m_stripMessage.data(), m_stripMessage.size(), MSG_NOSIGNAL) != static_cast<ssize_t>(m_stripMessage.size()))
            ::shutdown(clientFd, SHUT_RDWR);
        return;
    }

    if (line.rfind("REGISTER_BOUNDS ", 0) == 0) {
        m_clientCards[clientFd] = parseBoundsJson(line.substr(16));
        publishCards();
        return;
    }

    if (line.rfind("CARD_HOVER ", 0) == 0) {
        try {
            int wsId = std::stoi(line.substr(11));
            if (m_onHover) {
                m_onHover(wsId);
            }
        } catch (...) {}
        return;
    }

    if (line.rfind("CARD_LEAVE", 0) == 0) {
        if (m_onLeave) {
            m_onLeave();
        }
        return;
    }
}

void IpcServer::serverLoop() noexcept {
    std::unordered_map<int, std::string> clientBuffers;

    while (m_running.load()) {
        std::vector<struct pollfd> pfds;

        // Server listen socket
        struct pollfd serverPfd{};
        serverPfd.fd = m_serverFd;
        serverPfd.events = POLLIN;
        pfds.push_back(serverPfd);

        // Connected clients
        {
            std::lock_guard<std::mutex> lock(m_clientsMutex);
            for (int fd : m_clientFds) {
                if (fd >= 0) {
                    struct pollfd pfd{};
                    pfd.fd = fd;
                    pfd.events = POLLIN | POLLHUP | POLLERR;
                    pfds.push_back(pfd);
                }
            }
        }

        int ret = poll(pfds.data(), pfds.size(), 50); // 50ms poll timeout
        if (ret < 0) {
            if (errno == EINTR) continue;
            break;
        }
        if (ret == 0) continue; // Timeout, loop back to check m_running

        // 1. Check existing client FDs
        std::vector<int> disconnectedClients;
        for (size_t i = 1; i < pfds.size(); ++i) {
            int fd = pfds[i].fd;
            short revents = pfds[i].revents;

            // If client was already pruned and closed by sendToAllClients(), clean buffer and skip
            {
                std::lock_guard<std::mutex> lock(m_clientsMutex);
                if (std::find(m_clientFds.begin(), m_clientFds.end(), fd) == m_clientFds.end()) {
                    clientBuffers.erase(fd);
                    continue;
                }
            }

            bool clientDisconnected = false;

            // Defect C2: Process POLLIN BEFORE checking POLLHUP/POLLERR to drain pending data
            if (revents & POLLIN) {
                char buf[512];
                while (true) {
                    ssize_t n = -1;
                    int err = 0;
                    {
                        std::lock_guard<std::mutex> lock(m_clientsMutex);
                        if (std::find(m_clientFds.begin(), m_clientFds.end(), fd) == m_clientFds.end()) {
                            clientDisconnected = true;
                            break;
                        }
                        n = recv(fd, buf, sizeof(buf), 0);
                        if (n < 0) {
                            err = errno;
                        }
                    }
                    if (n > 0) {
                        // Defect C3: Binary safe append
                        clientBuffers[fd].append(buf, static_cast<size_t>(n));

                        // Defect C4: 64KB buffer cap to prevent DoS/memory exhaustion
                        if (clientBuffers[fd].size() > 65536) {
                            clientBuffers[fd].clear();
                            clientDisconnected = true;
                            break;
                        }

                        // Parse complete newline-delimited lines
                        size_t newlinePos;
                        while ((newlinePos = clientBuffers[fd].find('\n')) != std::string::npos) {
                            std::string line = clientBuffers[fd].substr(0, newlinePos);
                            clientBuffers[fd].erase(0, newlinePos + 1);

                            // Trim trailing \r if present
                            if (!line.empty() && line.back() == '\r') {
                                line.pop_back();
                            }

                            handleClientMessage(fd, line);
                        }
                    } else if (n == 0) {
                        // EOF reached (client closed connection)
                        clientDisconnected = true;
                        break;
                    } else {
                        if (err == EAGAIN || err == EWOULDBLOCK) {
                            // Drained all currently available data
                            break;
                        } else {
                            clientDisconnected = true;
                            break;
                        }
                    }
                }
            }

            // Defect C2: Mark disconnected after draining, or on POLLHUP/POLLERR/POLLNVAL
            if (clientDisconnected || (revents & (POLLHUP | POLLERR | POLLNVAL))) {
                disconnectedClients.push_back(fd);
            }
        }

        for (int discFd : disconnectedClients) {
            clientBuffers.erase(discFd);
            cleanupClient(discFd);
        }

        // 2. Check for incoming client connection on serverFd
        if (pfds[0].revents & POLLIN) {
            struct sockaddr_un clientAddr{};
            socklen_t clientLen = sizeof(clientAddr);
            int clientFd = accept4(m_serverFd, reinterpret_cast<struct sockaddr*>(&clientAddr), &clientLen, SOCK_NONBLOCK | SOCK_CLOEXEC);
            if (clientFd >= 0) {
                int flags = fcntl(clientFd, F_GETFL, 0);
                if (flags >= 0) {
                    fcntl(clientFd, F_SETFL, flags | O_NONBLOCK);
                }
                std::lock_guard<std::mutex> lock(m_clientsMutex);
                m_clientFds.push_back(clientFd);
                clientBuffers[clientFd] = "";
            }
        }
    }
}

} // namespace Cod29
