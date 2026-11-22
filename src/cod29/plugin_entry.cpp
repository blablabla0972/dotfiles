#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/config/ConfigValue.hpp>
#include <hyprland/src/config/shared/workspace/WorkspaceRuleManager.hpp>
#include <hyprland/src/layout/algorithm/Algorithm.hpp>
#include <hyprland/src/layout/algorithm/tiled/dwindle/DwindleAlgorithm.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/desktop/view/window/WindowGroupMembership.hpp>
#include <hyprland/src/managers/fullscreen/FullscreenController.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
#include <hyprland/src/layout/supplementary/DragController.hpp>
#include <hyprland/src/desktop/state/GlobalWindowController.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopManager.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/state/MonitorState.hpp>
#include <hyprland/src/state/workspace/State.hpp>
#include <hyprland/src/debug/log/Logger.hpp>

#include "cod29/top_edge_drag_logic.hpp"
#include "cod29/compositor_delegate.hpp"
#include "cod29/ipc_server.hpp"
#include "cod29/drag_hook_adapter.hpp"

#include <algorithm>
#include <chrono>
#include <linux/input-event-codes.h>
#include <memory>
#include <cstring>
#include <format>
#include <limits>

namespace Cod29 {

static PHLWORKSPACE workspaceById(int id) {
    for (const auto& reference : ::State::Workspace::state()->workspaceRefs()) {
        auto workspace = reference.lock();
        if (workspace && workspace->numberedID().value_or(0) == static_cast<uint32_t>(id))
            return workspace;
    }
    return nullptr;
}

struct DropPlacement {
    int workspaceId;
    Hyprutils::Math::Vector2D point;
    CBox box;
    bool floating;
};

static std::optional<DropPlacement> dropPlacement(const PHLWINDOW& window, bool tiled, const WorkspaceCard& card,
                                                  const PHLMONITOR& source, const Hyprutils::Math::Vector2D& cursor,
                                                  const Vector2D& anchor) {
    const auto workspace = workspaceById(card.id);
    const auto monitor = workspace ? workspace->m_monitor.lock() : source;
    if (!monitor || card.preview.w <= 0 || card.preview.h <= 0 || window->grouping().group() ||
        Fullscreen::controller()->isFullscreen(window) || (workspace && Fullscreen::controller()->hasFullscreen(workspace)))
        return std::nullopt;

    const auto output = monitor->logicalBox();
    const Hyprutils::Math::Vector2D point{
        output.x + output.w * std::clamp((cursor.x - card.preview.x) / card.preview.w, 0., 1.),
        output.y + output.h * std::clamp((cursor.y - card.preview.y) / card.preview.h, 0., 1.)};
    auto box = window->layoutTarget()->position();
    auto area = monitor->logicalBoxMinusReserved();
    if (!tiled) {
        box.x = std::clamp(point.x - box.w * anchor.x, area.x, area.x + std::max(0., area.w - box.w));
        box.y = std::clamp(point.y - box.h * anchor.y, area.y, area.y + std::max(0., area.h - box.h));
        return DropPlacement{card.id, point, box.round(), true};
    }

    static auto layout = CConfigValue<::Config::STRING>("general:layout");
    static auto smartSplit = CConfigValue<::Config::INTEGER>("dwindle:smart_split");
    static auto precise = CConfigValue<::Config::INTEGER>("dwindle:precise_mouse_move");
    static auto multiplier = CConfigValue<::Config::FLOAT>("dwindle:split_width_multiplier");
    static auto ratio = CConfigValue<::Config::FLOAT>("dwindle:default_split_ratio");
    static auto bias = CConfigValue<::Config::INTEGER>("dwindle:split_bias");
    static auto gapsOut = CConfigValue<::Config::IComplexConfigValue>("general:gaps_out");
    static auto gapsIn = CConfigValue<::Config::IComplexConfigValue>("general:gaps_in");
    const auto space = workspace ? workspace->space() : nullptr;
    auto* dwindle = space ? dynamic_cast<Layout::Tiled::CDwindleAlgorithm*>(space->algorithm()->tiledAlgo().get()) : nullptr;
    // shortcut: Special layouts and window rules retain native placement until they expose drop geometry.
    if ((space ? !dwindle : *layout != "dwindle") || *smartSplit || *precise || window->layoutTarget()->isPseudo())
        return std::nullopt;

    const auto& outer = *static_cast<::Config::CCssGapData*>(gapsOut.ptr());
    area = space ? space->workArea() : CBox{area.x + outer.m_left, area.y + outer.m_top,
                                          area.w - outer.m_left - outer.m_right, area.h - outer.m_top - outer.m_bottom};
    box = area;
    auto focalPoint = point;
    double distance = std::numeric_limits<double>::infinity();
    if (dwindle) {
        for (const auto& candidate : Desktop::windowState()->windows()) {
            if (candidate == window || candidate->m_workspace != workspace || !candidate->mapped() || candidate->isHidden())
                continue;
            const auto node = dwindle->getNodeFromWindow(candidate);
            if (!node || node->box.w <= 0 || node->box.h <= 0)
                continue;
            const auto& rect = node->box;
            const auto dx = point.x - std::clamp(point.x, rect.x, rect.x + rect.w);
            const auto dy = point.y - std::clamp(point.y, rect.y, rect.y + rect.h);
            if (const auto nearest = dx * dx + dy * dy; nearest < distance) {
                box = rect;
                distance = nearest;
            }
        }
    }
    if (const auto maximum = window->layoutTarget()->maxSize(); maximum &&
        (maximum->x < (distance < std::numeric_limits<double>::infinity() ? box.w : output.w) ||
         maximum->y < (distance < std::numeric_limits<double>::infinity() ? box.h : output.h)))
        return std::nullopt;
    if (distance < std::numeric_limits<double>::infinity()) {
        // Nudge the focal point inside the same tile to resolve shared edges consistently.
        focalPoint.x = std::clamp(point.x, box.x + .01, box.x + box.w - .01);
        focalPoint.y = std::clamp(point.y, box.y + .01, box.y + box.h - .01);
        const bool vertical = box.h * *multiplier > box.w;
        const bool first = vertical ? focalPoint.y < box.y + box.h / 2 : focalPoint.x < box.x + box.w / 2;
        double fraction = std::clamp(*ratio, .1f, 1.9f) / 2;
        if (*bias && first)
            fraction = 1 - fraction;
        auto& size = vertical ? box.h : box.w;
        auto& position = vertical ? box.y : box.x;
        const double split = size * fraction;
        if (!first)
            position += split;
        size = first ? split : size - split;
    }
    const auto rules = workspace ? ::Config::workspaceRuleMgr()->getWorkspaceRuleFor(workspace) : std::nullopt;
    const auto inner = rules && rules->m_gapsIn ? *rules->m_gapsIn : *static_cast<::Config::CCssGapData*>(gapsIn.ptr());
    const auto reserved = window->getFullWindowReservedArea();
    const auto left = reserved.topLeft.x + (std::abs(box.x - area.x) < 1 ? 0 : inner.m_left);
    const auto top = reserved.topLeft.y + (std::abs(box.y - area.y) < 1 ? 0 : inner.m_top);
    const auto right = reserved.bottomRight.x + (std::abs(box.x + box.w - area.x - area.w) < 1 ? 0 : inner.m_right);
    const auto bottom = reserved.bottomRight.y + (std::abs(box.y + box.h - area.y - area.h) < 1 ? 0 : inner.m_bottom);
    box.round();
    box = {box.x + left, box.y + top, box.w - left - right, box.h - top - bottom};
    return DropPlacement{card.id, focalPoint, box.round(), false};
}

class HyprlandCompositorDelegate : public ICompositorDelegate {
public:
    std::optional<DropPlacement> placement;
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

        auto pTargetWs = workspaceById(targetWorkspaceId);

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
            const auto target = pWindow->layoutTarget();
            const auto space = pTargetWs->space();
            if (placement && placement->workspaceId == targetWorkspaceId && target && target->space() == space) {
                if (placement->floating && target->floating()) {
                    target->setPositionGlobal(placement->box);
                    target->damageEntire();
                } else if (!target->floating() && !placement->floating && !pWindow->grouping().group() &&
                           space->algorithm()->tiledTargets() > 1) {
                    space->remove(target);
                    space->move(target, placement->point);
                }
            }
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
static CHyprSignalListener g_mouseButtonListener;
static SP<CEventLoopTimer> g_edgeTimer;
static std::optional<Hyprutils::Math::Vector2D> g_grabPoint;
static std::optional<Vector2D> g_grabAnchor;
static std::string g_dropMessage;

static inline uint64_t currentTimestampMs() noexcept {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
}

static void updatePointer(const Hyprutils::Math::Vector2D& coords, uint64_t now) {
    g_pDelegate->placement.reset();
    for (const auto& monitor : ::State::monitorState()->monitors()) {
        if (monitor && monitor->logicalBox().containsPoint(coords)) {
            const auto box = monitor->logicalBox();
            const auto topInset = std::max(0., monitor->logicalBoxMinusReserved().y - box.y);
            g_pAdapter->onPointerMotion({coords.x, coords.y}, {box.x, box.y, box.w, box.h, topInset}, now);
            const int targetId = g_pAdapter->getTargetWorkspaceId();
            if (targetId > 0) {
                const auto& controller = g_layoutManager->dragController();
                const auto target = controller->target();
                const auto cards = g_pAdapter->getWorkspaceCards();
                const auto card = std::ranges::find_if(cards, [&](const auto& candidate) {
                    return candidate.id == targetId && CBox{candidate.x, candidate.y, candidate.w, candidate.h}.containsPoint(coords);
                });
                if (card != cards.end() && target && target->window())
                    g_pDelegate->placement = dropPlacement(target->window(), controller->draggingTiled(), *card, monitor, coords,
                                                           g_grabAnchor.value_or(Vector2D{0.5, 0.5}));
            }
            auto message = std::to_string(targetId);
            if (const auto& placement = g_pDelegate->placement; placement) {
                const auto& rect = placement->box;
                message = std::format("{} {:.2f} {:.2f} {:.2f} {:.2f}", targetId, rect.x, rect.y, rect.w, rect.h);
            }
            if (message != g_dropMessage) {
                g_dropMessage = std::move(message);
                if (targetId > 0)
                    g_pIpcServer->broadcastDropBox(g_dropMessage);
            }
            return;
        }
    }
    g_pAdapter->onCancel(CancelReason::MonitorRemoved);
}

static void onEdgeDwell(SP<CEventLoopTimer>, void*) {
    if (g_pAdapter->getState() == State::EdgeArmed)
        updatePointer(g_pInputManager->getMouseCoordsInternal(), currentTimestampMs());
}

static void onMouseButton(const IPointer::SButtonEvent& event, Event::SCallbackInfo&) {
    if (event.button != BTN_LEFT)
        return;
    if (event.state == WL_POINTER_BUTTON_STATE_PRESSED)
        g_grabPoint = g_pInputManager->getMouseCoordsInternal();
    else {
        g_grabPoint.reset();
        return;
    }
    g_grabAnchor.reset();
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

    g_edgeTimer->updateTimeout(std::nullopt);
    const uint64_t now = currentTimestampMs();
    const auto state = g_pAdapter->getState();
    if (token && (state == State::StripOpen || state == State::HoverTarget))
        updatePointer(g_pInputManager->getMouseCoordsInternal(), now);
    const bool ended = g_pAdapter->onDragEnd(thisptr, token, sourceWs, now);
    g_pDelegate->placement.reset();
    g_dropMessage.clear();
    return ended;
}

static void onMouseMove(const Hyprutils::Math::Vector2D& coords, Event::SCallbackInfo& info) noexcept {
    // Pointer grab inviolability: never consume or cancel event
    info.cancelled = false;

    if (!g_pAdapter || !g_pStateMachine) return;

    const uint64_t now = currentTimestampMs();

    if (g_pAdapter->getState() == State::Idle) {
        const auto& controller = g_layoutManager->dragController();
        const auto target = controller->target();
        if (!target || controller->mode() != MBIND_MOVE || !target->window())
            return;
        if (!g_grabAnchor && g_grabPoint) {
            const auto box = target->position();
            g_grabAnchor = Vector2D{
                std::clamp((g_grabPoint->x - box.x) / std::max(1., box.w), 0., 1.),
                std::clamp((g_grabPoint->y - box.y) / std::max(1., box.h), 0., 1.)};
        }
        if (!controller->dragThresholdReached())
            return;
        const auto window = target->window();
        const uint64_t token = reinterpret_cast<uint64_t>(window.get());
        const int sourceWs = window->m_workspace ? static_cast<int>(window->m_workspace->numberedID().value_or(0)) : -1;
        g_pAdapter->onDragBegin(token, DragMode::Move, true, sourceWs, now, g_grabAnchor.value_or(Vector2D{0.5, 0.5}));
    }

    updatePointer(coords, now);
    if (g_pAdapter->getState() == State::EdgeArmed) {
        if (!g_edgeTimer->armed())
            g_edgeTimer->updateTimeout(std::chrono::milliseconds(g_pStateMachine->getConfig().dwellTimeMs + 1));
    } else if (g_edgeTimer->armed()) {
        g_edgeTimer->updateTimeout(std::nullopt);
    }
}

} // namespace Cod29

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    Cod29::g_pPluginHandle = handle;

    // Initialize State Machine with Config (default disabled per constraint)
    Cod29::Config cfg{};
    cfg.enabled = true; // Enabled when plugin is explicitly loaded
    cfg.stripHeight = 216; // Matches the Rice Shell workspace strip.
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

    Cod29::g_edgeTimer = makeShared<CEventLoopTimer>(std::nullopt, Cod29::onEdgeDwell, nullptr);
    g_pEventLoopManager->addTimer(Cod29::g_edgeTimer);

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
    Cod29::g_mouseButtonListener = Event::bus()->m_events.input.mouse.button.listen(Cod29::onMouseButton);

    return PLUGIN_DESCRIPTION_INFO{
        .name = "cod29_top_edge_drag",
        .description = "COD-29 Top-edge Workspace Drag for Rice Shell",
        .author = "Teamwork Engineering",
        .version = "0.1.0"
    };
}

APICALL EXPORT void PLUGIN_EXIT() {
    Cod29::g_mouseMoveListener.reset();
    Cod29::g_mouseButtonListener.reset();
    g_pEventLoopManager->removeTimer(Cod29::g_edgeTimer);
    Cod29::g_edgeTimer.reset();
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
