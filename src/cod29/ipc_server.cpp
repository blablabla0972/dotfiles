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
#include <regex>
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

    // Unlink any preexisting socket file
    unlink(m_socketPath.c_str());

    m_serverFd = socket(AF_UNIX, SOCK_STREAM, 0);
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

    if (listen(m_serverFd, 5) < 0) {
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

void IpcServer::broadcastShowStrip() noexcept {
    sendToAllClients("SHOW_STRIP\n");
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
    std::vector<int> deadFds;

    for (int fd : m_clientFds) {
        if (fd < 0) continue;
        ssize_t sent = ::send(fd, line.c_str(), line.length(), MSG_NOSIGNAL);
        if (sent < 0) {
            if (errno == EPIPE || errno == ECONNRESET || errno == EBADF) {
                deadFds.push_back(fd);
            }
        }
    }

    for (int deadFd : deadFds) {
        auto it = std::find(m_clientFds.begin(), m_clientFds.end(), deadFd);
        if (it != m_clientFds.end()) {
            m_clientFds.erase(it);
            ::close(deadFd);
        }
    }
}

void IpcServer::cleanupClient(int clientFd) noexcept {
    if (clientFd < 0) return;

    std::lock_guard<std::mutex> lock(m_clientsMutex);
    auto it = std::find(m_clientFds.begin(), m_clientFds.end(), clientFd);
    if (it != m_clientFds.end()) {
        m_clientFds.erase(it);
        ::close(clientFd);
    }
}

std::vector<WorkspaceCard> IpcServer::parseBoundsJson(const std::string& json) noexcept {
    std::vector<WorkspaceCard> cards;
    try {
        // Find each { ... } block
        size_t start = 0;
        while ((start = json.find('{', start)) != std::string::npos) {
            size_t end = json.find('}', start);
            if (end == std::string::npos) break;

            std::string obj = json.substr(start, end - start + 1);
            start = end + 1;

            WorkspaceCard card{};
            bool hasId = false;

            // Extract id
            std::regex idRegex(R"("id"\s*:\s*(-?\d+))");
            std::smatch match;
            if (std::regex_search(obj, match, idRegex)) {
                card.id = std::stoi(match[1]);
                hasId = true;
            }

            // Extract x
            std::regex xRegex(R"("x"\s*:\s*(-?[\d.]+))");
            if (std::regex_search(obj, match, xRegex)) {
                card.x = std::stod(match[1]);
            }

            // Extract y
            std::regex yRegex(R"("y"\s*:\s*(-?[\d.]+))");
            if (std::regex_search(obj, match, yRegex)) {
                card.y = std::stod(match[1]);
            }

            // Extract w
            std::regex wRegex(R"("w"\s*:\s*(-?[\d.]+))");
            if (std::regex_search(obj, match, wRegex)) {
                card.w = std::stod(match[1]);
            }

            // Extract h
            std::regex hRegex(R"("h"\s*:\s*(-?[\d.]+))");
            if (std::regex_search(obj, match, hRegex)) {
                card.h = std::stod(match[1]);
            }

            if (hasId) {
                cards.push_back(card);
            }
        }
    } catch (...) {
        // Return whatever was successfully parsed
    }
    return cards;
}

void IpcServer::handleClientMessage(int /*clientFd*/, const std::string& line) noexcept {
    if (line.empty()) return;

    if (line == "STRIP_READY") {
        // Client handshake
        return;
    }

    if (line.rfind("REGISTER_BOUNDS ", 0) == 0) {
        std::string json = line.substr(16);
        std::vector<WorkspaceCard> cards = parseBoundsJson(json);
        if (m_onSetCards && !cards.empty()) {
            m_onSetCards(cards);
        }
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
            int clientFd = accept(m_serverFd, reinterpret_cast<struct sockaddr*>(&clientAddr), &clientLen);
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
