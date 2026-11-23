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
#include <hyprland/src/managers/SessionLockManager.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/SceneResources.hpp>
#include <hyprland/src/render/scene/SceneSelection.hpp>
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
#include <unordered_map>
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
    PHLWINDOWREF neighbor{};
    CBox resizedTile{};
};

static CBox tileContentBox(CBox tile, const CBox& area, const ::Config::CCssGapData& gaps, const PHLWINDOW& window) {
    const auto reserved = window->getFullWindowReservedArea();
    const auto left = reserved.topLeft.x + (std::abs(tile.x - area.x) < 1 ? 0 : gaps.m_left);
    const auto top = reserved.topLeft.y + (std::abs(tile.y - area.y) < 1 ? 0 : gaps.m_top);
    const auto right = reserved.bottomRight.x + (std::abs(tile.x + tile.w - area.x - area.w) < 1 ? 0 : gaps.m_right);
    const auto bottom = reserved.bottomRight.y + (std::abs(tile.y + tile.h - area.y - area.h) < 1 ? 0 : gaps.m_bottom);
    tile.round();
    return CBox{tile.x + left, tile.y + top, tile.w - left - right, tile.h - top - bottom}.round();
}

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
    PHLWINDOW neighbor;
    CBox neighborTile;
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
                neighbor = candidate;
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
        neighborTile = box;
        auto& neighborSize = vertical ? neighborTile.h : neighborTile.w;
        auto& neighborPosition = vertical ? neighborTile.y : neighborTile.x;
        if (first)
            neighborPosition += split;
        neighborSize = first ? size - split : split;
        if (!first)
            position += split;
        size = first ? split : size - split;
    }
    const auto rules = workspace ? ::Config::workspaceRuleMgr()->getWorkspaceRuleFor(workspace) : std::nullopt;
    const auto inner = rules && rules->m_gapsIn ? *rules->m_gapsIn : *static_cast<::Config::CCssGapData*>(gapsIn.ptr());
    DropPlacement placement{card.id, focalPoint, tileContentBox(box, area, inner, window), false, {}, {}};
    if (neighbor && !neighbor->grouping().group() && !neighbor->layoutTarget()->isPseudo()) {
        placement.neighbor = neighbor;
        placement.resizedTile = tileContentBox(neighborTile, area, inner, neighbor);
    }
    return placement;
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
using BeginRender = bool (*)(Render::IHyprRenderer*, PHLMONITOR, CRegion&, Render::eRenderMode, SP<IHLBuffer>, SP<Render::IFramebuffer>,
                             bool, const Render::SRenderOptions&, std::optional<Monitor::CDamageRing::CTransaction>*);
using RenderWorkspace = void (*)(Render::IHyprRenderer*, Render::CRenderContext&, PHLWORKSPACE, const Time::steady_tp&, Render::eSceneMode);
using RenderLayer = void (*)(Render::IHyprRenderer*, Render::CRenderContext&, PHLLS, PHLMONITOR, const Time::steady_tp&, bool, bool, bool);
static BeginRender g_beginRender = nullptr;
static RenderWorkspace g_renderWorkspace = nullptr;
static CFunctionHook* g_layerHook = nullptr;
static CHyprSignalListener g_renderListener;

static std::unordered_map<int, SP<Render::IFramebuffer>> g_cardFrames;
static SP<Render::IFramebuffer> g_liveFrame;
static SP<Render::CSceneResources> g_sceneResources;
static int g_liveWorkspaceId = -1;
static PHLMONITORREF g_stripMonitor;

static CBox previewBox(const WorkspaceCard& card) {
    return {card.preview.x, card.preview.y, card.preview.w, card.preview.h};
}

static void stopPreview() {
    g_stripMonitor.reset();
    g_cardFrames.clear();
    g_liveWorkspaceId = -1;
}

static bool renderCard(const PHLWORKSPACE& workspace, SP<Render::IFramebuffer>& framebuffer, const DropPlacement* placement) {
    const auto monitor = workspace->m_monitor.lock();
    if (!monitor || !monitor->m_output)
        return false;
    if (!framebuffer)
        framebuffer = g_pHyprRenderer->createFB("cod29 preview");
    const auto size = monitor->m_pixelSize;
    if ((!framebuffer->isAllocated() || framebuffer->m_size != size) && !framebuffer->alloc(size.x, size.y, DRM_FORMAT_ARGB8888))
        return false;
    framebuffer->setImageDescription(NColorManagement::DEFAULT_SRGB_IMAGE_DESCRIPTION);
    if (!g_sceneResources)
        g_sceneResources = makeShared<Render::CSceneResources>(
            g_pHyprRenderer->createFB("cod29 preview blur"),
            Render::SSceneBufferDescription{DRM_FORMAT_ARGB8888, NColorManagement::DEFAULT_SRGB_IMAGE_DESCRIPTION});
    Render::SRenderOptions options{.sceneResources = g_sceneResources};
    CRegion damage{CBox{{}, monitor->m_transformedSize}};
    auto* renderer = g_pHyprRenderer.get();
    if (!g_beginRender(renderer, monitor, damage, Render::RENDER_MODE_FULL_FAKE, nullptr, framebuffer, false, options, nullptr))
        return false;

    auto& ctx = renderer->context();
    ctx.m_data.blockScreenShader = true;
    ctx.m_renderingCapture = true;
    ctx.m_blockSurfaceFeedback = true;
    renderer->draw(ctx, CClearPassElement::SClearData{{0, 0, 0, 0}}, damage);
    renderer->startRenderPass(ctx);

    // The offscreen pass gets the proposed tile geometry; input and layout retain their real state.
    struct RenderGeometry {
        PHLWINDOW window;
        CBox before;
        RenderGeometry(const PHLWINDOW& w, const CBox& box)
            : window(w), before(w ? CBox{w->positionAnimation()->value(), w->sizeAnimation()->value()} : CBox{}) {
            if (window) {
                window->positionAnimation()->value() = box.pos();
                window->sizeAnimation()->value() = box.size();
            }
        }
        ~RenderGeometry() {
            if (window) {
                window->positionAnimation()->value() = before.pos();
                window->sizeAnimation()->value() = before.size();
            }
        }
    };
    const auto now = Time::steadyNow();
    const auto target = g_layoutManager->dragController()->target();
    auto window = placement && target ? target->window() : nullptr;
    if (window && (!window->mapped() || window->m_workspace == workspace))
        window.reset();
    {
        const auto previousWorkspace = window ? window->m_workspace : nullptr;
        const auto previousMonitor = window ? window->m_monitor : PHLMONITORREF{};
        const auto restoreWorkspace = Hyprutils::Utils::CScopeGuard([&] {
            if (window) {
                window->m_workspace = previousWorkspace;
                window->m_monitor = previousMonitor;
            }
        });
        if (window) {
            window->m_workspace = workspace;
            window->m_monitor = monitor;
        }
        const RenderGeometry incoming(window, window ? placement->box : CBox{});
        const RenderGeometry displaced(window ? placement->neighbor.lock() : nullptr, window ? placement->resizedTile : CBox{});
        g_renderWorkspace(renderer, ctx, workspace, now, Render::eSceneMode::WORKSPACE_WITH_SHELL);
        renderer->endRender();
    }
    return true;
}

static void renderPreview(const Event::SRenderStageEvent& event) {
    if (event.stage != RENDER_POST || g_stripMonitor != event.monitor || g_pSessionLockManager->isSessionLocked())
        return;

    const int target = g_pAdapter->getTargetWorkspaceId();
    const auto cards = g_pAdapter->getWorkspaceCards();
    for (const auto& card : cards) {
        const auto box = previewBox(card);
        if (box.empty() || !event.monitor->logicalBox().containsPoint(box.middle()) || g_cardFrames.contains(card.id))
            continue;
        if (const auto workspace = workspaceById(card.id)) {
            SP<Render::IFramebuffer> frame;
            if (renderCard(workspace, frame, nullptr)) {
                g_cardFrames.emplace(card.id, std::move(frame));
                g_pHyprRenderer->damageBox(box);
            }
            return;
        }
    }

    const auto card = std::ranges::find_if(cards, [target](const auto& item) { return item.id == target; });
    if (card == cards.end())
        return;
    const auto box = previewBox(*card);
    const auto workspace = workspaceById(target);
    if (box.empty() || !event.monitor->logicalBox().containsPoint(box.middle()) || !workspace)
        return;
    const auto& placement = g_pDelegate->placement;
    if (renderCard(workspace, g_liveFrame, placement && placement->workspaceId == target ? &*placement : nullptr)) {
        g_liveWorkspaceId = target;
        const auto owner = workspace->m_monitor.lock();
        if (owner && workspace != owner->m_activeWorkspace)
            g_pHyprRenderer->sendFrameEventsToWorkspace(owner, workspace, Time::steadyNow());
        g_pHyprRenderer->damageBox(box);
    }
}

static void renderStripLayer(Render::IHyprRenderer* renderer, Render::CRenderContext& ctx, PHLLS layer, PHLMONITOR monitor,
                             const Time::steady_tp& now, bool popups, bool lockscreen, bool workspaceScene) {
    const bool strip = layer && layer->m_namespace == "cod29-workspace-strip";
    // Exclude the preview's own layer from workspace renders, including other workspace captures.
    if (strip && workspaceScene)
        return;
    reinterpret_cast<RenderLayer>(g_layerHook->m_original)(renderer, ctx, layer, monitor, now, popups, lockscreen, workspaceScene);
    if (!strip || popups || lockscreen || !layer->mapped() || !layer->alphaNonZero() || g_stripMonitor != monitor ||
        ctx.m_renderingCapture || ctx.m_mode != Render::RENDER_MODE_NORMAL ||
        g_pSessionLockManager->isSessionLocked())
        return;

    const int target = g_pAdapter->getTargetWorkspaceId();
    for (const auto& card : g_pAdapter->getWorkspaceCards()) {
        if (const auto it = g_cardFrames.find(card.id); it != g_cardFrames.end()) {
            const auto& frame = card.id == target && target == g_liveWorkspaceId ? g_liveFrame : it->second;
            auto box = previewBox(card);
            if (!monitor->logicalBox().containsPoint(box.middle()))
                continue;
            box.translate(-monitor->m_position).scale(monitor->m_scale).round();
            renderer->addPassElement(ctx, makeUnique<CTexPassElement>(
                CTexPassElement::SRenderData{.tex = frame->getTexture(), .box = box, .round = static_cast<int>(5 * monitor->m_scale)}));
        }
    }
}

static void* renderFunction(const char* symbol, const char* signature) {
    for (const auto& match : HyprlandAPI::findFunctionsByName(g_pPluginHandle, symbol)) {
        if (match.demangled.find(signature) != std::string::npos)
            return match.address;
    }
    return nullptr;
}

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
            const auto state = g_pAdapter->getState();
            if (state == State::StripOpen || state == State::HoverTarget) {
                if (g_stripMonitor != monitor)
                    stopPreview();
                g_stripMonitor = monitor;
            } else if (g_stripMonitor)
                stopPreview();
            return;
        }
    }
    stopPreview();
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
    stopPreview();
    g_pDelegate->placement.reset();
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
    cfg.stripHeight = 264; // Matches the Rice Shell workspace strip.
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

    Cod29::g_beginRender = reinterpret_cast<Cod29::BeginRender>(Cod29::renderFunction("beginRender", "Render::IHyprRenderer::beginRender("));
    Cod29::g_renderWorkspace = reinterpret_cast<Cod29::RenderWorkspace>(
        Cod29::renderFunction("renderWorkspace", "Render::eSceneMode)"));
    if (Cod29::g_beginRender && Cod29::g_renderWorkspace) {
        if (auto* address = Cod29::renderFunction("renderLayer", "Render::IHyprRenderer::renderLayer(")) {
            Cod29::g_layerHook = HyprlandAPI::createFunctionHook(handle, address, reinterpret_cast<void*>(&Cod29::renderStripLayer));
            if (Cod29::g_layerHook && Cod29::g_layerHook->hook())
                Cod29::g_renderListener = Event::bus()->m_events.render.stage.listen(Cod29::renderPreview);
        }
    }

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
    Cod29::g_renderListener.reset();
    if (Cod29::g_layerHook)
        HyprlandAPI::removeFunctionHook(Cod29::g_pPluginHandle, Cod29::g_layerHook);
    Cod29::stopPreview();
    Cod29::g_liveFrame.reset();
    Cod29::g_sceneResources.reset();
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
