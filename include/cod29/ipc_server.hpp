#pragma once

#include "cod29/top_edge_drag_logic.hpp"
#include <string>
#include <vector>
#include <functional>
#include <atomic>
#include <thread>
#include <mutex>

namespace Cod29 {

/**
 * @brief UNIX domain socket server managing IPC communication with the
 *        Quickshell workspace strip overlay.
 *
 * Implements a non-blocking, line-delimited protocol:
 * - Downstream (Plugin -> Quickshell):
 *     SHOW_STRIP
 *     HIDE_STRIP
 *     TARGET_CHANGED <wsId>
 *     RESET
 * - Upstream (Quickshell -> Plugin):
 *     STRIP_READY
 *     REGISTER_BOUNDS <json>
 *     CARD_HOVER <wsId>
 *     CARD_LEAVE [wsId]
 */
class IpcServer {
public:
    using HoverCallback = std::function<void(int workspaceId)>;
    using LeaveCallback = std::function<void()>;
    using SetCardsCallback = std::function<void(const std::vector<WorkspaceCard>& cards)>;

    explicit IpcServer(std::string socketPath = "") noexcept;
    ~IpcServer() noexcept;

    // Server lifecycle
    bool start() noexcept;
    void stop() noexcept;
    bool isRunning() const noexcept;
    const std::string& getSocketPath() const noexcept;

    // Downstream broadcasts
    void broadcastShowStrip() noexcept;
    void broadcastHideStrip() noexcept;
    void broadcastTargetChanged(int targetWorkspaceId) noexcept;
    void broadcastReset() noexcept;

    // Upstream message callbacks
    void setHoverCallback(HoverCallback cb) noexcept { m_onHover = std::move(cb); }
    void setLeaveCallback(LeaveCallback cb) noexcept { m_onLeave = std::move(cb); }
    void setSetCardsCallback(SetCardsCallback cb) noexcept { m_onSetCards = std::move(cb); }

    // Test / Diagnostic queries
    size_t getConnectedClientCount() const noexcept;

    // Static helper to parse JSON array of card bounds
    static std::vector<WorkspaceCard> parseBoundsJson(const std::string& json) noexcept;

private:
    void serverLoop() noexcept;
    void handleClientMessage(int clientFd, const std::string& line) noexcept;
    void sendToAllClients(const std::string& line) noexcept;
    void cleanupClient(int clientFd) noexcept;

    std::string m_socketPath;
    std::atomic<bool> m_running{false};
    int m_serverFd = -1;
    std::thread m_serverThread;

    mutable std::mutex m_clientsMutex;
    std::vector<int> m_clientFds;

    HoverCallback m_onHover;
    LeaveCallback m_onLeave;
    SetCardsCallback m_onSetCards;
};

} // namespace Cod29
