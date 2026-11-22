#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
#include <hyprland/src/layout/supplementary/DragController.hpp>
#include <hyprland/src/desktop/state/GlobalWindowController.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/state/MonitorState.hpp>
#include <hyprland/src/state/workspace/State.hpp>
#include <hyprland/src/debug/log/Logger.hpp>

#include "cod29/top_edge_drag_logic.hpp"
#include "cod29/compositor_delegate.hpp"
#include "cod29/ipc_server.hpp"
#include "cod29/drag_hook_adapter.hpp"

#include <chrono>
#include <memory>
#include <cstring>

namespace Cod29 {

class HyprlandCompositorDelegate : public ICompositorDelegate {
public:
    using origDragEnd_t = bool (*)(void* thisptr);

    void setOrigDragEnd(origDragEnd_t fn) noexcept {
        m_origDragEnd = fn;
    }

    void capturePreReleaseWindow(void* thisptr, uint64_t /*windowToken*/) override {
        if (!thisptr) return;
        auto pController = static_cast<Layout::Supplementary::CDragStateController*>(thisptr);
        if (pController) {
            auto spTarget = pController->target();
            if (spTarget) {
                auto pWindow = spTarget->window();
                if (pWindow) {
                    m_capturedWindowRef = pWindow;
                }
            }
        }
    }

    bool invokeOriginalDragEnd(void* thisptr) override {
        if (m_origDragEnd && thisptr) {
            return m_origDragEnd(thisptr);
        }
        return false;
    }

    bool isWindowValid(uint64_t /*windowToken*/) const override {
        return !m_capturedWindowRef.expired();
    }

    bool moveWindowToWorkspace(uint64_t /*windowToken*/, int targetWorkspaceId, bool /*follow*/) override {
        auto pWindow = m_capturedWindowRef.lock();
        if (!pWindow || targetWorkspaceId <= 0) {
            return false;
        }

        PHLWORKSPACE pTargetWs = nullptr;
        for (const auto& wsRef : ::State::Workspace::state()->workspaceRefs()) {
            auto ws = wsRef.lock();
            if (ws && ws->numberedID().has_value() && ws->numberedID().value() == static_cast<uint32_t>(targetWorkspaceId)) {
                pTargetWs = ws;
                break;
            }
        }

        if (!pTargetWs) {
            auto pMonitor = pWindow->m_monitor.lock();
            if (pMonitor) {
                pTargetWs = ::State::Workspace::state()->createNumbered(
                    ::Workspace::SWorkspaceNumberedID{static_cast<uint32_t>(targetWorkspaceId)},
                    pMonitor);
            }
        }

        if (pTargetWs && pWindow->m_workspace != pTargetWs) {
            Desktop::globalWindowController()->moveWindowToWorkspace(pWindow, pTargetWs);
            return true;
        }
        return false;
    }

    void log(const std::string& level, const std::string& message) override {
        if (Log::logger) {
            Hyprutils::CLI::eLogLevel lvl = Hyprutils::CLI::LOG_DEBUG;
            if (level == "WARN") lvl = Hyprutils::CLI::LOG_WARN;
            else if (level == "ERROR") lvl = Hyprutils::CLI::LOG_ERR;
            Log::logger->log(lvl, std::string("[COD-29] ") + message);
        }
    }

private:
    origDragEnd_t m_origDragEnd = nullptr;
    PHLWINDOWREF m_capturedWindowRef;
};

// Global plugin state instances
static HANDLE g_pPluginHandle = nullptr;
static CFunctionHook* g_pDragEndHook = nullptr;
static std::unique_ptr<HyprlandCompositorDelegate> g_pDelegate;
static std::unique_ptr<StateMachine> g_pStateMachine;
static std::unique_ptr<IpcServer> g_pIpcServer;
static std::unique_ptr<DragHookAdapter> g_pAdapter;
static CHyprSignalListener g_mouseMoveListener;

static inline uint64_t currentTimestampMs() noexcept {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
}

static bool hkDragEnd(void* thisptr) noexcept {
    if (!g_pAdapter) return false;

    uint64_t token = 0;
    int sourceWs = -1;

    if (thisptr) {
        auto pController = static_cast<Layout::Supplementary::CDragStateController*>(thisptr);
        if (pController) {
            auto spTarget = pController->target();
            if (spTarget) {
                auto pWindow = spTarget->window();
                if (pWindow) {
                    token = reinterpret_cast<uint64_t>(pWindow.get());
                    if (pWindow->m_workspace && pWindow->m_workspace->numberedID().has_value()) {
                        sourceWs = pWindow->m_workspace->numberedID().value();
                    }
                }
            }
        }
    }

    const uint64_t now = currentTimestampMs();
    return g_pAdapter->onDragEnd(thisptr, token, sourceWs, now);
}

static void onMouseMove(const Hyprutils::Math::Vector2D& coords, Event::SCallbackInfo& info) noexcept {
    // Pointer grab inviolability: never consume or cancel event
    info.cancelled = false;

    if (!g_pAdapter || !g_pStateMachine) return;

    const uint64_t now = currentTimestampMs();

    // Check if dragging initiated
    if (g_pStateMachine->getState() == State::Idle) {
        if (g_layoutManager) {
            const auto& dragController = g_layoutManager->dragController();
            if (dragController && dragController->mode() == MBIND_MOVE && dragController->dragThresholdReached()) {
                auto spTarget = dragController->target();
                if (spTarget) {
                    auto pWindow = spTarget->window();
                    if (pWindow) {
                        uint64_t token = reinterpret_cast<uint64_t>(pWindow.get());
                        int sourceWs = (pWindow->m_workspace && pWindow->m_workspace->numberedID().has_value())
                                           ? pWindow->m_workspace->numberedID().value()
                                           : -1;
                        g_pAdapter->onDragBegin(token, DragMode::Move, true, sourceWs, now);
                    }
                }
            }
        }
    }

    if (g_pStateMachine->getState() == State::Idle) return;

    // Resolve active monitor logical box
    PHLMONITOR pActiveMon = nullptr;
    for (const auto& mon : ::State::monitorState()->monitors()) {
        if (mon && mon->logicalBox().containsPoint(coords)) {
            pActiveMon = mon;
            break;
        }
    }
    if (!pActiveMon) return;

    const auto box = pActiveMon->logicalBox();
    const OutputRect output{box.x, box.y, box.w, box.h};

    g_pAdapter->onPointerMotion(Vector2D{coords.x, coords.y}, output, now);
}

} // namespace Cod29

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    Cod29::g_pPluginHandle = handle;

    // Initialize State Machine with Config (default disabled per constraint)
    Cod29::Config cfg{};
    cfg.enabled = true; // Enabled when plugin is explicitly loaded
    Cod29::g_pStateMachine = std::make_unique<Cod29::StateMachine>(cfg);

    // Initialize Compositor Delegate
    Cod29::g_pDelegate = std::make_unique<Cod29::HyprlandCompositorDelegate>();

    // Initialize IPC Server
    Cod29::g_pIpcServer = std::make_unique<Cod29::IpcServer>();
    Cod29::g_pIpcServer->start();

    // Initialize Drag Hook Adapter
    Cod29::g_pAdapter = std::make_unique<Cod29::DragHookAdapter>(
        *Cod29::g_pStateMachine,
        *Cod29::g_pIpcServer,
        Cod29::g_pDelegate.get()
    );

    // Resolve CDragStateController::dragEnd symbol
    void* targetFunc = nullptr;
    auto matches = HyprlandAPI::findFunctionsByName(handle, "dragEnd");
    for (const auto& m : matches) {
        if (m.demangled.find("CDragStateController::dragEnd") != std::string::npos) {
            targetFunc = m.address;
            break;
        }
    }
    if (!targetFunc) {
        auto pMethod = &Layout::Supplementary::CDragStateController::dragEnd;
        std::memcpy(&targetFunc, &pMethod, sizeof(void*));
    }

    // Register function hook
    Cod29::g_pDragEndHook = HyprlandAPI::createFunctionHook(handle, targetFunc, reinterpret_cast<void*>(&Cod29::hkDragEnd));
    if (Cod29::g_pDragEndHook) {
        Cod29::g_pDragEndHook->hook();
        Cod29::g_pDelegate->setOrigDragEnd(
            reinterpret_cast<Cod29::HyprlandCompositorDelegate::origDragEnd_t>(Cod29::g_pDragEndHook->m_original)
        );
    }

    // Register mouse move signal listener
    Cod29::g_mouseMoveListener = Event::bus()->m_events.input.mouse.move.listen(Cod29::onMouseMove);

    return PLUGIN_DESCRIPTION_INFO{
        .name = "cod29_top_edge_drag",
        .description = "COD-29 Top-edge Workspace Drag for Rice Shell",
        .author = "Teamwork Engineering",
        .version = "0.1.0"
    };
}

APICALL EXPORT void PLUGIN_EXIT() {
    if (Cod29::g_pDragEndHook) {
        HyprlandAPI::removeFunctionHook(Cod29::g_pPluginHandle, Cod29::g_pDragEndHook);
        Cod29::g_pDragEndHook = nullptr;
    }

    if (Cod29::g_pIpcServer) {
        Cod29::g_pIpcServer->stop();
    }

    Cod29::g_pAdapter.reset();
    Cod29::g_pIpcServer.reset();
    Cod29::g_pDelegate.reset();
    Cod29::g_pStateMachine.reset();
    Cod29::g_pPluginHandle = nullptr;
}

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}
