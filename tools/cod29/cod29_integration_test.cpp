#include "cod29/top_edge_drag_logic.hpp"
#include "cod29/compositor_delegate.hpp"
#include "cod29/ipc_server.hpp"
#include "cod29/drag_hook_adapter.hpp"

#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <fcntl.h>

#include <iostream>
#include <string>
#include <vector>
#include <unordered_set>
#include <chrono>
#include <thread>
#include <cstring>
#include <cassert>

using namespace Cod29;

namespace {

struct MoveCall {
    uint64_t windowToken = 0;
    int targetWorkspaceId = -1;
    bool follow = false;
};

class MockCompositorDelegate : public ICompositorDelegate {
public:
    bool origDragEndResult = true;
    bool origDragEndThrows = false;
    size_t dragEndCount = 0;
    std::unordered_set<uint64_t> validWindows;
    std::vector<MoveCall> moveCalls;
    std::vector<std::string> logMessages;

    void capturePreReleaseWindow(void* /*thisptr*/, uint64_t /*windowToken*/) override {
        // Tracked via validWindows
    }

    bool invokeOriginalDragEnd(void* /*thisptr*/) override {
        dragEndCount++;
        if (origDragEndThrows) {
            throw std::runtime_error("Simulated crash in origDragEnd");
        }
        return origDragEndResult;
    }

    bool isWindowValid(uint64_t windowToken) const override {
        return validWindows.find(windowToken) != validWindows.end();
    }

    bool moveWindowToWorkspace(uint64_t windowToken, int targetWorkspaceId, bool follow) override {
        moveCalls.push_back({windowToken, targetWorkspaceId, follow});
        return true;
    }

    void log(const std::string& level, const std::string& message) override {
        logMessages.push_back(level + ": " + message);
    }
};

class TestIpcClient {
public:
    int fd = -1;

    bool connect(const std::string& socketPath, int maxRetries = 25) {
        for (int i = 0; i < maxRetries; ++i) {
            fd = socket(AF_UNIX, SOCK_STREAM, 0);
            if (fd < 0) return false;
            struct sockaddr_un addr{};
            addr.sun_family = AF_UNIX;
            std::strncpy(addr.sun_path, socketPath.c_str(), sizeof(addr.sun_path) - 1);
            if (::connect(fd, reinterpret_cast<struct sockaddr*>(&addr), sizeof(addr)) == 0) {
                return true;
            }
            close(fd);
            fd = -1;
            std::this_thread::sleep_for(std::chrono::milliseconds(20));
        }
        return false;
    }

    void disconnect() {
        if (fd >= 0) {
            close(fd);
            fd = -1;
        }
    }

    bool sendLine(const std::string& line) {
        if (fd < 0) return false;
        std::string msg = line.back() == '\n' ? line : line + "\n";
        ssize_t n = ::send(fd, msg.c_str(), msg.length(), MSG_NOSIGNAL);
        return n == static_cast<ssize_t>(msg.length());
    }

    std::vector<std::string> readLines(int timeoutMs = 250) {
        std::vector<std::string> lines;
        if (fd < 0) return lines;

        auto start = std::chrono::steady_clock::now();
        std::string buffer;

        while (std::chrono::duration_cast<std::chrono::milliseconds>(
                   std::chrono::steady_clock::now() - start).count() < timeoutMs) {
            char chunk[512];
            ssize_t n = ::recv(fd, chunk, sizeof(chunk) - 1, MSG_DONTWAIT);
            if (n > 0) {
                chunk[n] = '\0';
                buffer += chunk;
                size_t pos;
                while ((pos = buffer.find('\n')) != std::string::npos) {
                    std::string l = buffer.substr(0, pos);
                    buffer.erase(0, pos + 1);
                    if (!l.empty() && l.back() == '\r') l.pop_back();
                    lines.push_back(l);
                }
            } else if (n == 0) {
                break;
            }
            if (!lines.empty()) break;
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
        }
        return lines;
    }

    ~TestIpcClient() {
        disconnect();
    }
};

std::string makeTestSocketPath(const std::string& testName) {
    return "/tmp/cod29-test-" + testName + "-" + std::to_string(getpid()) + ".sock";
}

} // anonymous namespace

// ----------------------------------------------------------------------------
// Test Cases IT01 through IT10
// ----------------------------------------------------------------------------

bool test_IT01_ipc_lifecycle() {
    std::string sock = makeTestSocketPath("it01");
    IpcServer server(sock);

    if (!server.start()) return false;
    if (!server.isRunning()) return false;

    TestIpcClient client;
    if (!client.connect(sock)) return false;

    if (!client.sendLine("STRIP_READY")) return false;
    std::this_thread::sleep_for(std::chrono::milliseconds(30));

    if (server.getConnectedClientCount() != 1) return false;

    client.disconnect();
    server.stop();

    if (server.isRunning()) return false;
    if (access(sock.c_str(), F_OK) == 0) return false; // unlinked

    return true;
}

bool test_IT02_e2e_drag_and_drop() {
    std::string sock = makeTestSocketPath("it02");
    Config cfg{};
    cfg.enabled = true;
    StateMachine sm(cfg);
    IpcServer server(sock);
    if (!server.start()) return false;

    MockCompositorDelegate delegate;
    delegate.validWindows.insert(0x1001);

    DragHookAdapter adapter(sm, server, &delegate);

    TestIpcClient client;
    if (!client.connect(sock)) return false;
    std::this_thread::sleep_for(std::chrono::milliseconds(25));
    client.sendLine("STRIP_READY");

    // Step 1: Drag Begin
    adapter.onDragBegin(0x1001, DragMode::Move, true, 1, 1000);
    if (adapter.getState() != State::Dragging) return false;

    // Step 2: Pointer touches physical top edge (y <= 4.0)
    OutputRect mon{0, 0, 1920, 1080};
    adapter.onPointerMotion(Vector2D{500, 2}, mon, 1000);
    if (adapter.getState() != State::EdgeArmed) return false;

    // Step 3: Dwell satisfied (> 80ms)
    adapter.onPointerMotion(Vector2D{500, 2}, mon, 1085);
    if (adapter.getState() != State::StripOpen) return false;

    auto lines = client.readLines(200);
    bool sawShow = false;
    for (const auto& l : lines) {
        if (l == "SHOW_STRIP") sawShow = true;
    }
    if (!sawShow) return false;

    // Step 4: Hover over target workspace card 2
    client.sendLine("CARD_HOVER 2");
    std::this_thread::sleep_for(std::chrono::milliseconds(30));
    if (adapter.getState() != State::HoverTarget) return false;
    if (adapter.getTargetWorkspaceId() != 2) return false;

    // Step 5: Drag End on target workspace 2
    bool ok = adapter.onDragEnd(nullptr, 0x1001, 1, 1150);
    if (!ok) return false;

    // Verify atomic moveWindowToWorkspace dispatch
    if (delegate.moveCalls.size() != 1) return false;
    if (delegate.moveCalls[0].windowToken != 0x1001) return false;
    if (delegate.moveCalls[0].targetWorkspaceId != 2) return false;
    if (delegate.moveCalls[0].follow != false) return false;

    // Verify state machine reset to Idle
    if (adapter.getState() != State::Idle) return false;

    client.disconnect();
    server.stop();
    return true;
}

bool test_IT03_same_workspace_noop() {
    std::string sock = makeTestSocketPath("it03");
    Config cfg{};
    cfg.enabled = true;
    StateMachine sm(cfg);
    IpcServer server(sock);
    if (!server.start()) return false;

    MockCompositorDelegate delegate;
    delegate.validWindows.insert(0x1001);
    DragHookAdapter adapter(sm, server, &delegate);

    TestIpcClient client;
    if (!client.connect(sock)) return false;
    std::this_thread::sleep_for(std::chrono::milliseconds(25));

    // Drag begin on WS 1
    adapter.onDragBegin(0x1001, DragMode::Move, true, 1, 1000);
    OutputRect mon{0, 0, 1920, 1080};
    adapter.onPointerMotion(Vector2D{500, 2}, mon, 1000);
    adapter.onPointerMotion(Vector2D{500, 2}, mon, 1090); // StripOpen

    // Hover over WS 1 (same as source)
    client.sendLine("CARD_HOVER 1");
    std::this_thread::sleep_for(std::chrono::milliseconds(30));

    // Release
    bool ok = adapter.onDragEnd(nullptr, 0x1001, 1, 1150);
    if (!ok) return false;

    // Strict NO-OP: moveWindowToWorkspace must NOT be called (0 calls)
    if (!delegate.moveCalls.empty()) return false;
    // Original dragEnd must still have been called
    if (delegate.dragEndCount != 1) return false;
    if (adapter.getState() != State::Idle) return false;

    client.disconnect();
    server.stop();
    return true;
}

bool test_IT04_fast_flick_disarm() {
    std::string sock = makeTestSocketPath("it04");
    Config cfg{};
    cfg.enabled = true;
    StateMachine sm(cfg);
    IpcServer server(sock);
    if (!server.start()) return false;

    MockCompositorDelegate delegate;
    DragHookAdapter adapter(sm, server, &delegate);

    TestIpcClient client;
    if (!client.connect(sock)) return false;
    std::this_thread::sleep_for(std::chrono::milliseconds(25));

    adapter.onDragBegin(0x1001, DragMode::Move, true, 1, 1000);
    OutputRect mon{0, 0, 1920, 1080};

    // Pointer reaches edge at t = 1000
    adapter.onPointerMotion(Vector2D{500, 2}, mon, 1000);
    if (adapter.getState() != State::EdgeArmed) return false;

    // Fast flick: retreats before 80ms dwell (at t = 1030)
    adapter.onPointerMotion(Vector2D{500, 50}, mon, 1030);
    if (adapter.getState() != State::Dragging) return false;

    // Verify 0 SHOW_STRIP messages were emitted
    auto lines = client.readLines(50);
    for (const auto& l : lines) {
        if (l == "SHOW_STRIP") return false;
    }

    client.disconnect();
    server.stop();
    return true;
}

bool test_IT05_exit_hysteresis_dismissal() {
    std::string sock = makeTestSocketPath("it05");
    Config cfg{};
    cfg.enabled = true;
    StateMachine sm(cfg);
    IpcServer server(sock);
    if (!server.start()) return false;

    MockCompositorDelegate delegate;
    DragHookAdapter adapter(sm, server, &delegate);

    TestIpcClient client;
    if (!client.connect(sock)) return false;
    std::this_thread::sleep_for(std::chrono::milliseconds(25));

    adapter.onDragBegin(0x1001, DragMode::Move, true, 1, 1000);
    OutputRect mon{0, 0, 1920, 1080};
    adapter.onPointerMotion(Vector2D{500, 2}, mon, 1000);
    adapter.onPointerMotion(Vector2D{500, 2}, mon, 1090);
    if (adapter.getState() != State::StripOpen) return false;

    // Move within strip bounds (e.g. y = 100) -> remains StripOpen
    adapter.onPointerMotion(Vector2D{500, 100}, mon, 1100);
    if (adapter.getState() != State::StripOpen) return false;

    // Move past stripHeight(140) + exitHysteresis(28) = 168 -> e.g. y = 170
    adapter.onPointerMotion(Vector2D{500, 170}, mon, 1120);
    if (adapter.getState() != State::Dragging) return false;

    auto lines = client.readLines(200);
    bool sawHide = false;
    for (const auto& l : lines) {
        if (l == "HIDE_STRIP") sawHide = true;
    }
    if (!sawHide) return false;

    client.disconnect();
    server.stop();
    return true;
}

bool test_IT06_hardening_h1_exception_quarantine() {
    std::string sock = makeTestSocketPath("it06");
    Config cfg{};
    cfg.enabled = true;
    StateMachine sm(cfg);
    IpcServer server(sock);
    if (!server.start()) return false;

    MockCompositorDelegate delegate;
    DragHookAdapter adapter(sm, server, &delegate);

    adapter.onDragBegin(0x1001, DragMode::Move, true, 1, 1000);
    OutputRect mon{0, 0, 1920, 1080};

    // Inject motion exception
    adapter.injectMotionExceptionForTest(true);

    // Call onPointerMotion - MUST NOT CRASH, MUST NOT ESCAPE NOEXCEPT
    adapter.onPointerMotion(Vector2D{500, 2}, mon, 1000);

    // Verify exception was quarantined
    if (adapter.getQuarantinedExceptionCount() != 1) return false;
    // Verify state machine safely reset to Idle
    if (adapter.getState() != State::Idle) return false;

    server.stop();
    return true;
}

bool test_IT07_hardening_h2_prerelease_capture() {
    std::string sock = makeTestSocketPath("it07");
    Config cfg{};
    cfg.enabled = true;
    StateMachine sm(cfg);
    IpcServer server(sock);
    if (!server.start()) return false;

    MockCompositorDelegate delegate;
    // Simulate window initially valid
    delegate.validWindows.insert(0x2002);

    DragHookAdapter adapter(sm, server, &delegate);

    TestIpcClient client;
    if (!client.connect(sock)) return false;
    std::this_thread::sleep_for(std::chrono::milliseconds(25));

    adapter.onDragBegin(0x2002, DragMode::Move, true, 1, 1000);
    OutputRect mon{0, 0, 1920, 1080};
    adapter.onPointerMotion(Vector2D{500, 2}, mon, 1000);
    adapter.onPointerMotion(Vector2D{500, 2}, mon, 1090);

    client.sendLine("CARD_HOVER 3");
    std::this_thread::sleep_for(std::chrono::milliseconds(30));
    if (adapter.getState() != State::HoverTarget) return false;

    // Simulate window destruction during release: remove from validWindows
    delegate.validWindows.clear();

    bool ok = adapter.onDragEnd(nullptr, 0x2002, 1, 1150);
    if (!ok) return false;

    // Because window was destroyed during release, move must be cleanly aborted (0 calls)
    if (!delegate.moveCalls.empty()) return false;
    if (adapter.getState() != State::Idle) return false;

    client.disconnect();
    server.stop();
    return true;
}

bool test_IT08_hardening_h3_aborted_release_reset() {
    std::string sock = makeTestSocketPath("it08");
    Config cfg{};
    cfg.enabled = true;
    StateMachine sm(cfg);
    IpcServer server(sock);
    if (!server.start()) return false;

    MockCompositorDelegate delegate;
    delegate.validWindows.insert(0x1001);
    // Simulate compositor aborting the drag
    delegate.origDragEndResult = false;

    DragHookAdapter adapter(sm, server, &delegate);

    TestIpcClient client;
    if (!client.connect(sock)) return false;
    std::this_thread::sleep_for(std::chrono::milliseconds(25));

    adapter.onDragBegin(0x1001, DragMode::Move, true, 1, 1000);
    OutputRect mon{0, 0, 1920, 1080};
    adapter.onPointerMotion(Vector2D{500, 2}, mon, 1000);
    adapter.onPointerMotion(Vector2D{500, 2}, mon, 1090);

    client.sendLine("CARD_HOVER 2");
    std::this_thread::sleep_for(std::chrono::milliseconds(30));

    // Release when compositor returns false
    bool res = adapter.onDragEnd(nullptr, 0x1001, 1, 1150);
    // Must forward false
    if (res != false) return false;

    // Move must NOT be called
    if (!delegate.moveCalls.empty()) return false;

    // State machine must be reset to Idle (via DragSuperseded)
    if (adapter.getState() != State::Idle) return false;

    // Quickshell strip must be dismissed
    auto lines = client.readLines(200);
    bool sawHide = false;
    for (const auto& l : lines) {
        if (l == "HIDE_STRIP") sawHide = true;
    }
    if (!sawHide) return false;

    client.disconnect();
    server.stop();
    return true;
}

bool test_IT09_mode_discrimination_filtering() {
    std::string sock = makeTestSocketPath("it09");
    Config cfg{};
    cfg.enabled = true;
    StateMachine sm(cfg);
    IpcServer server(sock);
    if (!server.start()) return false;

    MockCompositorDelegate delegate;
    DragHookAdapter adapter(sm, server, &delegate);

    OutputRect mon{0, 0, 1920, 1080};

    // 1. Resize mode must be ignored
    adapter.onDragBegin(0x1001, DragMode::Resize, true, 1, 1000);
    if (adapter.getState() != State::Idle) return false;
    adapter.onPointerMotion(Vector2D{500, 2}, mon, 1000);
    if (adapter.getState() != State::Idle) return false;

    // 2. Threshold unreached must be ignored
    adapter.onDragBegin(0x1001, DragMode::Move, false, 1, 1050);
    if (adapter.getState() != State::Idle) return false;

    // 3. Feature flag disabled must be ignored
    Config offCfg{};
    offCfg.enabled = false;
    sm.setConfig(offCfg);
    adapter.onDragBegin(0x1001, DragMode::Move, true, 1, 1100);
    if (adapter.getState() != State::Idle) return false;

    server.stop();
    return true;
}

bool test_IT10_client_reconnect_resilience() {
    std::string sock = makeTestSocketPath("it10");
    IpcServer server(sock);
    if (!server.start()) return false;

    // Client 1 connects
    {
        TestIpcClient client1;
        if (!client1.connect(sock)) return false;
        client1.sendLine("STRIP_READY");
        for (int i = 0; i < 20 && server.getConnectedClientCount() != 1; ++i) {
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
        }
        if (server.getConnectedClientCount() != 1) return false;

        // Abrupt disconnect
        client1.disconnect();
    }

    // Broadcast messages while client is disconnected - must not throw or crash
    server.broadcastShowStrip();
    server.broadcastTargetChanged(2);
    server.broadcastHideStrip();

    // Client 2 connects
    TestIpcClient client2;
    if (!client2.connect(sock)) return false;
    client2.sendLine("STRIP_READY");
    for (int i = 0; i < 20 && server.getConnectedClientCount() != 1; ++i) {
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }

    server.broadcastShowStrip();
    auto lines = client2.readLines(200);
    bool sawShow = false;
    for (const auto& l : lines) {
        if (l == "SHOW_STRIP") sawShow = true;
    }
    if (!sawShow) return false;

    client2.disconnect();
    server.stop();
    return true;
}

bool test_IT11_immediate_disconnect_message_retention() {
    std::string sock = makeTestSocketPath("it11");
    IpcServer server(sock);
    if (!server.start()) return false;

    std::atomic<int> receivedCount{0};
    std::vector<int> receivedIds;
    std::mutex mtx;

    server.setHoverCallback([&](int wsId) {
        std::lock_guard<std::mutex> lock(mtx);
        receivedIds.push_back(wsId);
        receivedCount++;
    });

    constexpr int kIterations = 20;

    for (int i = 0; i < kIterations; ++i) {
        int targetWs = 100 + i;
        int clientFd = socket(AF_UNIX, SOCK_STREAM, 0);
        if (clientFd < 0) {
            server.stop();
            return false;
        }

        struct sockaddr_un addr{};
        addr.sun_family = AF_UNIX;
        std::strncpy(addr.sun_path, sock.c_str(), sizeof(addr.sun_path) - 1);

        if (::connect(clientFd, reinterpret_cast<struct sockaddr*>(&addr), sizeof(addr)) < 0) {
            ::close(clientFd);
            server.stop();
            return false;
        }

        std::string msg = "CARD_HOVER " + std::to_string(targetWs) + "\n";
        ssize_t sent = ::send(clientFd, msg.c_str(), msg.length(), MSG_NOSIGNAL);
        if (sent != static_cast<ssize_t>(msg.length())) {
            ::close(clientFd);
            server.stop();
            return false;
        }

        // Immediate disconnect with 0 delay - directly triggers POLLIN | POLLHUP in poll()
        ::close(clientFd);
    }

    // Wait up to 1 second for all messages to be drained and processed
    auto start = std::chrono::steady_clock::now();
    while (receivedCount.load() < kIterations &&
           std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - start).count() < 1000) {
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }

    server.stop();

    if (receivedCount.load() != kIterations) {
        return false;
    }

    std::lock_guard<std::mutex> lock(mtx);
    for (int i = 0; i < kIterations; ++i) {
        if (receivedIds[i] != 100 + i) {
            return false;
        }
    }

    return true;
}

bool test_IT12_concurrent_broadcast_disconnect_safety() {
    std::string sock = makeTestSocketPath("it12");
    IpcServer server(sock);
    if (!server.start()) return false;

    std::atomic<bool> stopFlag{false};
    std::atomic<size_t> broadcastsCompleted{0};

    // Broadcaster thread: Rapidly broadcast events across all clients
    std::thread broadcaster([&]() {
        while (!stopFlag.load()) {
            server.broadcastShowStrip();
            server.broadcastTargetChanged(2);
            server.broadcastHideStrip();
            broadcastsCompleted += 3;
            std::this_thread::sleep_for(std::chrono::microseconds(100));
        }
    });

    // Client worker threads: Rapidly connect, send, and abruptly disconnect
    constexpr int kClientThreads = 4;
    constexpr int kCyclesPerThread = 25;
    std::vector<std::thread> clientThreads;
    clientThreads.reserve(kClientThreads);

    for (int t = 0; t < kClientThreads; ++t) {
        clientThreads.emplace_back([&, t]() {
            for (int i = 0; i < kCyclesPerThread; ++i) {
                int clientFd = socket(AF_UNIX, SOCK_STREAM, 0);
                if (clientFd < 0) continue;

                struct sockaddr_un addr{};
                addr.sun_family = AF_UNIX;
                std::strncpy(addr.sun_path, sock.c_str(), sizeof(addr.sun_path) - 1);

                if (::connect(clientFd, reinterpret_cast<struct sockaddr*>(&addr), sizeof(addr)) == 0) {
                    std::string msg = "CARD_HOVER " + std::to_string(t * 100 + i) + "\n";
                    ::send(clientFd, msg.c_str(), msg.length(), MSG_NOSIGNAL);
                    // Disconnect abruptly during concurrent broadcasts
                    ::close(clientFd);
                } else {
                    ::close(clientFd);
                }
                std::this_thread::yield();
            }
        });
    }

    for (auto& ct : clientThreads) {
        if (ct.joinable()) ct.join();
    }

    stopFlag.store(true);
    if (broadcaster.joinable()) broadcaster.join();

    // Verify server remains responsive and can accept a new clean client
    TestIpcClient finalClient;
    if (!finalClient.connect(sock)) {
        server.stop();
        return false;
    }
    finalClient.sendLine("STRIP_READY");
    std::this_thread::sleep_for(std::chrono::milliseconds(50));

    server.broadcastShowStrip();
    auto lines = finalClient.readLines(200);
    bool sawShow = false;
    for (const auto& l : lines) {
        if (l == "SHOW_STRIP") sawShow = true;
    }

    finalClient.disconnect();
    server.stop();

    return sawShow && (broadcastsCompleted.load() > 0);
}

bool test_IT13_concurrent_card_updates_and_motion() {
    std::string sock = makeTestSocketPath("it13");
    Config cfg{};
    cfg.enabled = true;
    StateMachine sm(cfg);
    IpcServer server(sock);
    if (!server.start()) return false;

    MockCompositorDelegate delegate;
    delegate.validWindows.insert(0x3001);
    DragHookAdapter adapter(sm, server, &delegate);

    TestIpcClient client;
    if (!client.connect(sock)) {
        server.stop();
        return false;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(25));
    client.sendLine("STRIP_READY");

    OutputRect mon{0, 0, 1920, 1080};
    adapter.onDragBegin(0x3001, DragMode::Move, true, 1, 1000);
    adapter.onPointerMotion(Vector2D{500, 2}, mon, 1000);
    adapter.onPointerMotion(Vector2D{500, 2}, mon, 1090);
    if (adapter.getState() != State::StripOpen) {
        client.disconnect();
        server.stop();
        return false;
    }

    std::atomic<bool> stopFlag{false};
    std::atomic<size_t> ipcOpsCompleted{0};
    std::atomic<size_t> motionOpsCompleted{0};

    // Thread 1: Rapid IPC card bounds registration & card hover/leave
    std::thread ipcThread([&]() {
        int iter = 0;
        while (!stopFlag.load()) {
            iter++;
            if (iter % 3 == 0) {
                // Bounds with 2 cards
                client.sendLine("REGISTER_BOUNDS [{\"id\":1,\"x\":100,\"y\":10,\"w\":150,\"h\":100},{\"id\":2,\"x\":260,\"y\":10,\"w\":150,\"h\":100}]");
            } else if (iter % 3 == 1) {
                // Bounds with 5 cards (forces vector reallocation)
                client.sendLine("REGISTER_BOUNDS [{\"id\":1,\"x\":50,\"y\":10,\"w\":80,\"h\":100},{\"id\":2,\"x\":140,\"y\":10,\"w\":80,\"h\":100},{\"id\":3,\"x\":230,\"y\":10,\"w\":80,\"h\":100},{\"id\":4,\"x\":320,\"y\":10,\"w\":80,\"h\":100},{\"id\":5,\"x\":410,\"y\":10,\"w\":80,\"h\":100}]");
            } else {
                // Bounds with 1 card (vector shrink/reallocation)
                client.sendLine("REGISTER_BOUNDS [{\"id\":1,\"x\":100,\"y\":10,\"w\":200,\"h\":100}]");
            }

            if (iter % 4 == 0) {
                client.sendLine("CARD_HOVER 2");
            } else if (iter % 4 == 1) {
                client.sendLine("CARD_HOVER 1");
            } else if (iter % 4 == 2) {
                client.sendLine("CARD_LEAVE");
            } else {
                client.sendLine("CARD_HOVER 3");
            }

            ipcOpsCompleted++;
            std::this_thread::yield();
        }
    });

    // Thread 2: Simulating Hyprland compositor main thread doing rapid pointer tracking & hit tests
    std::thread compositorThread([&]() {
        for (int i = 0; i < 2000; ++i) {
            double posX = 50.0 + (i % 500);
            double posY = 20.0 + (i % 80);
            adapter.onPointerMotion(Vector2D{posX, posY}, mon, 1100 + i);

            // Concurrent queries
            volatile State st = adapter.getState();
            (void)st;
            volatile int tgt = adapter.getTargetWorkspaceId();
            (void)tgt;
            auto cards = adapter.getWorkspaceCards();
            (void)cards.size();

            motionOpsCompleted++;
            if (i % 50 == 0) {
                std::this_thread::yield();
            }
        }
    });

    compositorThread.join();
    stopFlag.store(true);
    ipcThread.join();

    // Verify adapter remained intact and healthy
    State finalState = adapter.getState();
    if (finalState != State::StripOpen && finalState != State::HoverTarget) {
        client.disconnect();
        server.stop();
        return false;
    }

    // Terminate drag cleanly
    bool ok = adapter.onDragEnd(nullptr, 0x3001, 1, 4000);
    if (!ok) {
        client.disconnect();
        server.stop();
        return false;
    }
    if (adapter.getState() != State::Idle) {
        client.disconnect();
        server.stop();
        return false;
    }

    client.disconnect();
    server.stop();

    return (ipcOpsCompleted.load() > 50) && (motionOpsCompleted.load() == 2000);
}

// ----------------------------------------------------------------------------
// Test Runner
// ----------------------------------------------------------------------------

int main() {
    std::cout << "====================================================================\n";
    std::cout << " COD-29 Phase D: Integration & Verification Test Suite (IT01-IT13)  \n";
    std::cout << "====================================================================\n\n";

    struct TestCase {
        std::string id;
        std::string name;
        bool (*func)();
    };

    std::vector<TestCase> cases = {
        {"IT01", "IPC Server Handshake & Lifecycle", test_IT01_ipc_lifecycle},
        {"IT02", "Full End-to-End Drag & Atomic Drop", test_IT02_e2e_drag_and_drop},
        {"IT03", "Same-Workspace Drop (NO-OP Policy)", test_IT03_same_workspace_noop},
        {"IT04", "Fast Flick Edge Disarm", test_IT04_fast_flick_disarm},
        {"IT05", "Strip Dismissal via Exit Hysteresis", test_IT05_exit_hysteresis_dismissal},
        {"IT06", "Hardening Rule H1 (Exception Quarantine)", test_IT06_hardening_h1_exception_quarantine},
        {"IT07", "Hardening Rule H2 (Pre-Release Window Capture)", test_IT07_hardening_h2_prerelease_capture},
        {"IT08", "Hardening Rule H3 (Aborted Release Reset)", test_IT08_hardening_h3_aborted_release_reset},
        {"IT09", "Mode Discrimination Filtering", test_IT09_mode_discrimination_filtering},
        {"IT10", "IPC Client Disconnect / Reconnect Resilience", test_IT10_client_reconnect_resilience},
        {"IT11", "Immediate Disconnect Message Retention", test_IT11_immediate_disconnect_message_retention},
        {"IT12", "Concurrent Broadcast & Disconnect Safety", test_IT12_concurrent_broadcast_disconnect_safety},
        {"IT13", "Concurrent IPC Card Updates & Pointer Motion Thread-Safety", test_IT13_concurrent_card_updates_and_motion}
    };

    int passed = 0;
    int failed = 0;

    for (const auto& tc : cases) {
        bool ok = false;
        try {
            ok = tc.func();
        } catch (const std::exception& e) {
            std::cout << "  [FAIL] " << tc.id << ": " << tc.name << " (Exception: " << e.what() << ")\n";
            failed++;
            continue;
        } catch (...) {
            std::cout << "  [FAIL] " << tc.id << ": " << tc.name << " (Unknown exception)\n";
            failed++;
            continue;
        }

        if (ok) {
            std::cout << "  [PASS] " << tc.id << ": " << tc.name << "\n";
            passed++;
        } else {
            std::cout << "  [FAIL] " << tc.id << ": " << tc.name << "\n";
            failed++;
        }
    }

    std::cout << "\n--------------------------------------------------------------------\n";
    std::cout << " Test Summary: " << passed << " / " << (passed + failed) << " passed (" << failed << " failed)\n";
    std::cout << "--------------------------------------------------------------------\n";

    if (failed == 0) {
        std::cout << " [SUCCESS] ALL 13 INTEGRATION TESTS (IT01-IT13) PASSED DETERMINISTICALLY.\n";
        std::cout << "====================================================================\n";
        return 0;
    } else {
        std::cout << " [FAILURE] " << failed << " INTEGRATION TEST(S) FAILED.\n";
        std::cout << "====================================================================\n";
        return 1;
    }
}
