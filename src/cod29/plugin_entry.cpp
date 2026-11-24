#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/config/ConfigValue.hpp>
#include <hyprland/src/config/shared/workspace/WorkspaceRuleManager.hpp>
#include <hyprland/src/layout/algorithm/Algorithm.hpp>
#include <hyprland/src/layout/algorithm/tiled/dwindle/DwindleAlgorithm.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
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
#include <hyprland/src/protocols/core/Compositor.hpp>
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
#include <stdexcept>
#include <utility>
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
    PHLWINDOWREF neighbor;
    CBox neighborBox;
    bool clearMaximizedDestination = false;
};

static CBox contentBox(CBox tile, const CBox& workArea, const ::Config::CCssGapData& gaps, const PHLWINDOW& window) {
    const auto reserved = window->getFullWindowReservedArea();
    const auto left = reserved.topLeft.x + (std::abs(tile.x - workArea.x) < 1 ? 0 : gaps.m_left);
    const auto top = reserved.topLeft.y + (std::abs(tile.y - workArea.y) < 1 ? 0 : gaps.m_top);
    const auto right = reserved.bottomRight.x + (std::abs(tile.x + tile.w - workArea.x - workArea.w) < 1 ? 0 : gaps.m_right);
    const auto bottom = reserved.bottomRight.y + (std::abs(tile.y + tile.h - workArea.y - workArea.h) < 1 ? 0 : gaps.m_bottom);
    return CBox{tile.x + left, tile.y + top, tile.w - left - right, tile.h - top - bottom}.round();
}

static std::optional<DropPlacement> dropPlacement(const PHLWINDOW& window, bool tiled, const WorkspaceCard& card,
                                                  const PHLMONITOR& source, const Hyprutils::Math::Vector2D& cursor,
                                                  const Vector2D& anchor) {
    const auto workspace = workspaceById(card.id);
    const auto monitor = workspace ? workspace->m_monitor.lock() : source;
    if (!monitor || card.preview.w <= 0 || card.preview.h <= 0 || window->grouping().group() ||
        Fullscreen::controller()->isFullscreen(window))
        return std::nullopt;

    const bool maximizedDestination = workspace && Fullscreen::controller()->hasFullscreen(workspace);
    if (maximizedDestination) {
        // Following a tiled drop exits a lone maximized window in this focus mode.
        static auto focusUnderFullscreen = CConfigValue<::Config::INTEGER>("misc:on_focus_under_fullscreen");
        const auto mode = Fullscreen::controller()->getFullscreenModes(workspace).internal;
        if (!tiled || mode != Fullscreen::FSMODE_MAXIMIZED || *focusUnderFullscreen != 2 || workspace->getWindowCount() != 1)
            return std::nullopt;
    }

    const auto output = monitor->logicalBox();
    const Hyprutils::Math::Vector2D point{
        output.x + output.w * std::clamp((cursor.x - card.preview.x) / card.preview.w, 0., 1.),
        output.y + output.h * std::clamp((cursor.y - card.preview.y) / card.preview.h, 0., 1.)};
    if (!tiled) {
        auto box = window->layoutTarget()->position();
        const auto area = monitor->logicalBoxMinusReserved();
        box.x = std::clamp(point.x - box.w * anchor.x, area.x, area.x + std::max(0., area.w - box.w));
        box.y = std::clamp(point.y - box.h * anchor.y, area.y, area.y + std::max(0., area.h - box.h));
        return DropPlacement{card.id, point, box.round(), true, {}, {}};
    }

    static auto layout = CConfigValue<::Config::STRING>("general:layout");
    static auto smartSplit = CConfigValue<::Config::INTEGER>("dwindle:smart_split");
    static auto precise = CConfigValue<::Config::INTEGER>("dwindle:precise_mouse_move");
    const auto space = workspace ? workspace->space() : nullptr;
    auto* dwindle = space ? dynamic_cast<Layout::Tiled::CDwindleAlgorithm*>(space->algorithm()->tiledAlgo().get()) : nullptr;
    // shortcut: Special layouts and window rules retain native placement until they expose drop geometry.
    if ((space ? !dwindle : *layout != "dwindle") || *smartSplit || *precise || window->layoutTarget()->isPseudo())
        return std::nullopt;

    std::optional<CBox> nearestTile;
    PHLWINDOW neighbor;
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
                nearestTile = rect;
                neighbor = candidate;
                distance = nearest;
            }
        }
    }
    const auto available = nearestTile.value_or(output).size();
    if (const auto maximum = window->layoutTarget()->maxSize(); maximum &&
        (maximum->x < available.x || maximum->y < available.y))
        return std::nullopt;

    static auto gapsOut = CConfigValue<::Config::IComplexConfigValue>("general:gaps_out");
    static auto gapsIn = CConfigValue<::Config::IComplexConfigValue>("general:gaps_in");
    const auto& outer = *static_cast<::Config::CCssGapData*>(gapsOut.ptr());
    const auto usable = monitor->logicalBoxMinusReserved();
    const auto workArea = space ? space->workArea() : CBox{usable.x + outer.m_left, usable.y + outer.m_top,
                                                          usable.w - outer.m_left - outer.m_right, usable.h - outer.m_top - outer.m_bottom};
    const auto rules = workspace ? ::Config::workspaceRuleMgr()->getWorkspaceRuleFor(workspace) : std::nullopt;
    const auto& inner = rules && rules->m_gapsIn ? *rules->m_gapsIn : *static_cast<::Config::CCssGapData*>(gapsIn.ptr());

    if (!nearestTile) {
        if (maximizedDestination)
            return std::nullopt;
        return DropPlacement{card.id, point, contentBox(workArea, workArea, inner, window), false, {}, {}};
    }

    const auto& tile = *nearestTile;
    const Hyprutils::Math::Vector2D focalPoint{std::clamp(point.x, tile.x + .01, tile.x + tile.w - .01),
                              std::clamp(point.y, tile.y + .01, tile.y + tile.h - .01)};
    static auto multiplier = CConfigValue<::Config::FLOAT>("dwindle:split_width_multiplier");
    static auto ratio = CConfigValue<::Config::FLOAT>("dwindle:default_split_ratio");
    static auto bias = CConfigValue<::Config::INTEGER>("dwindle:split_bias");
    static auto preserveSplit = CConfigValue<::Config::INTEGER>("dwindle:preserve_split");
    const bool sideBySide = tile.w > tile.h * *multiplier;
    const bool first = sideBySide ? focalPoint.x < tile.middle().x : focalPoint.y < tile.middle().y;
    const bool vertical = *preserveSplit ? !sideBySide : tile.h * *multiplier > tile.w;
    double ratioForFirst = std::clamp(*ratio, .1f, 1.9f) / 2;
    if (*bias && first)
        ratioForFirst = 1 - ratioForFirst;
    const auto firstSize = (vertical ? tile.h : tile.w) * ratioForFirst;

    auto a = tile;
    auto b = tile;
    if (vertical) {
        a.h = firstSize;
        b.y += firstSize;
        b.h -= firstSize;
    } else {
        a.w = firstSize;
        b.x += firstSize;
        b.w -= firstSize;
    }
    return DropPlacement{card.id, focalPoint, contentBox(first ? a : b, workArea, inner, window), false,
                         neighbor, contentBox(first ? b : a, workArea, inner, neighbor), maximizedDestination};
}

class HyprlandCompositorDelegate : public ICompositorDelegate {
public:
    std::optional<DropPlacement> placement;
    PHLWINDOWREF followWindow;
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

    bool moveWindowToWorkspace(uint64_t /*windowToken*/, int targetWorkspaceId, bool follow) override {
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
            if (placement && placement->workspaceId == targetWorkspaceId && placement->clearMaximizedDestination) {
                if (const auto maximized = Fullscreen::controller()->getFullscreenWindow(pTargetWs))
                    Fullscreen::controller()->setFullscreenMode(maximized, Fullscreen::FSMODE_NONE);
            }
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
            if (follow)
                followWindow = pWindow;
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
using RenderWindow = void (*)(Render::IHyprRenderer*, Render::CRenderContext&, PHLWINDOW, PHLMONITOR,
                             const Render::SWindowRenderPresentation&, const Time::steady_tp&, bool, Render::eRenderPassMode, bool, bool);
static BeginRender g_beginRender = nullptr;
static RenderWorkspace g_renderWorkspace = nullptr;
static CFunctionHook* g_layerHook = nullptr;
static CFunctionHook* g_windowHook = nullptr;
static CHyprSignalListener g_renderListener;

struct ProjectedDrop {
    PHLWINDOW window;
    DropPlacement placement;
};
static const ProjectedDrop* g_projection = nullptr;
static SP<Render::IFramebuffer> g_projectedFrame;
static int g_projectedWorkspace = -1;

static std::unordered_map<int, SP<Render::IFramebuffer>> g_cardFrames;
static SP<Render::CSceneResources> g_sceneResources;
static PHLMONITORREF g_stripMonitor;
static SP<CEventLoopTimer> g_previewTimer;
static constexpr auto PREVIEW_INTERVAL = std::chrono::milliseconds(7);
static size_t g_nextPreviewCard = 0;
static unsigned g_backgroundSlots = 0;

struct PreviewRequest {
    WorkspaceCard card;
    PHLWORKSPACEREF workspace;
};
static std::optional<PreviewRequest> g_pendingPreview;

static CBox previewBox(const WorkspaceCard& card) {
    return {card.preview.x, card.preview.y, card.preview.w, card.preview.h};
}

static void stopPreview() {
    if (g_previewTimer)
        g_previewTimer->updateTimeout(std::nullopt);
    g_pendingPreview.reset();
    g_nextPreviewCard = 0;
    g_backgroundSlots = 0;
    g_projectedWorkspace = -1;
    g_projectedFrame.reset();
    g_stripMonitor.reset();
    g_cardFrames.clear();
}

static void drawProjectedWindow(Render::IHyprRenderer* renderer, Render::CRenderContext& ctx, const PHLMONITOR& monitor,
                                const PHLWINDOW& window, const CBox& box) {
    if (!window || box.empty() || !ctx.shouldRenderContent(window->m_ruleApplicator->noScreenShare().valueOrDefault()))
        return;

    const auto surface = window->wlSurface()->resource();
    if (!surface || surface->m_current.size.x < 1 || surface->m_current.size.y < 1)
        return;

    const auto scale = box.size() / surface->m_current.size;
    const auto clip = box.copy().translate(-monitor->m_position).scale(monitor->m_scale).round();
    surface->breadthfirst([&](SP<CWLSurfaceResource> part, const Hyprutils::Math::Vector2D& offset, void*) {
        if (!part->m_current.texture || part->m_current.size.x < 1 || part->m_current.size.y < 1)
            return;
        auto region = CBox{box.pos() - monitor->m_position + offset * scale, part->m_current.size * scale};
        region.scale(monitor->m_scale).round();
        renderer->addPassElement(ctx, makeUnique<CTexPassElement>(
            CTexPassElement::SRenderData{.tex = part->m_current.texture, .box = region, .clipBox = clip}));
    }, nullptr);
}

static void renderProjectedSplit(Render::IHyprRenderer* renderer, Render::CRenderContext& ctx, PHLWINDOW window, PHLMONITOR monitor,
                                 const Render::SWindowRenderPresentation& presentation, const Time::steady_tp& now,
                                 bool decorate, Render::eRenderPassMode mode, bool ignorePosition, bool standalone) {
    if (g_projection && ctx.m_renderingCapture && window == g_projection->placement.neighbor) {
        if (mode != Render::RENDER_PASS_POPUP) {
            drawProjectedWindow(renderer, ctx, monitor, window, g_projection->placement.neighborBox);
            drawProjectedWindow(renderer, ctx, monitor, g_projection->window, g_projection->placement.box);
        }
        return;
    }
    reinterpret_cast<RenderWindow>(g_windowHook->m_original)(renderer, ctx, window, monitor, presentation, now, decorate, mode, ignorePosition, standalone);
}

static bool renderCard(const PHLWORKSPACE& workspace, SP<Render::IFramebuffer>& framebuffer, const ProjectedDrop* projection = nullptr) {
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

    // Draw the proposed split only in this offscreen pass. Live window geometry is never changed.
    {
        const auto reset = Hyprutils::Utils::CScopeGuard([] { g_projection = nullptr; });
        if (projection && projection->placement.neighbor)
            g_projection = projection;
        g_renderWorkspace(renderer, ctx, workspace, Time::steadyNow(), Render::eSceneMode::WORKSPACE_WITH_SHELL);
    }
    if (projection && !projection->placement.neighbor)
        drawProjectedWindow(renderer, ctx, monitor, projection->window, projection->placement.box);
    renderer->endRender();
    return true;
}

static void schedulePreview(SP<CEventLoopTimer> timer, void*) {
    const auto monitor = g_stripMonitor.lock();
    if (!monitor || g_pSessionLockManager->isSessionLocked())
        return;

    timer->updateTimeout(PREVIEW_INTERVAL);
    if (g_pendingPreview)
        return;

    const auto cards = g_pAdapter->getWorkspaceCards();
    const int hovered = g_pAdapter->getTargetWorkspaceId();
    const auto queue = [&](const WorkspaceCard& card) {
        const auto box = previewBox(card);
        if (box.empty() || !monitor->logicalBox().containsPoint(box.middle()))
            return false;
        const auto workspace = workspaceById(card.id);
        if (!workspace)
            return false;
        g_pendingPreview = PreviewRequest{card, workspace};
        g_pHyprRenderer->damageBox(box);
        return true;
    };

    // Give the destination every third turn. Distribute the other turns across the remaining cards.
    const auto priority = std::ranges::find(cards, hovered, &WorkspaceCard::id);
    if (priority != cards.end() && g_backgroundSlots == 0 && queue(*priority)) {
        g_backgroundSlots = 2;
        return;
    }
    for (size_t i = 0; i < cards.size(); ++i) {
        const auto& card = cards[g_nextPreviewCard++ % cards.size()];
        if (card.id != hovered && queue(card)) {
            if (g_backgroundSlots)
                --g_backgroundSlots;
            return;
        }
    }
    if (priority != cards.end())
        queue(*priority);
}

static void renderPreview(const Event::SRenderStageEvent& event) {
    // Capture before beginning the normal output pass so this frame can use the new thumbnail.
    if (event.stage != RENDER_PRE || g_stripMonitor != event.monitor || g_pSessionLockManager->isSessionLocked() ||
        !g_pendingPreview)
        return;

    const auto request = std::exchange(g_pendingPreview, std::nullopt);
    const auto workspace = request->workspace.lock();
    if (!workspace)
        return;

    const auto& card = request->card;
    std::optional<ProjectedDrop> projection;
    if (g_windowHook && card.id == g_pAdapter->getTargetWorkspaceId()) {
        const auto& controller = g_layoutManager->dragController();
        const auto target = controller->target();
        const auto window = target ? target->window() : nullptr;
        const auto pointer = g_pInputManager->getMouseCoordsInternal();
        if (window && window->m_workspace != workspace && CBox{card.x, card.y, card.w, card.h}.containsPoint(pointer)) {
            const auto placement = dropPlacement(window, controller->draggingTiled(), card, event.monitor, pointer,
                                                 g_grabAnchor.value_or(Vector2D{0.5, 0.5}));
            if (placement && !placement->box.empty())
                projection = ProjectedDrop{window, *placement};
        }
    }

    if (projection) {
        g_projectedWorkspace = renderCard(workspace, g_projectedFrame, &*projection) ? card.id : -1;
    } else {
        if (g_projectedWorkspace == card.id)
            g_projectedWorkspace = -1;
        auto [entry, inserted] = g_cardFrames.try_emplace(card.id);
        if (!renderCard(workspace, entry->second)) {
            if (inserted)
                g_cardFrames.erase(entry);
            return;
        }
    }

    // Hidden Wayland clients still need frame callbacks to produce the next preview frame.
    if (!workspace->visible()) {
        if (const auto owner = workspace->m_monitor.lock())
            g_pHyprRenderer->sendFrameEventsToWorkspace(owner, workspace, Time::steadyNow());
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

    const int hovered = g_pAdapter->getTargetWorkspaceId();
    for (const auto& card : g_pAdapter->getWorkspaceCards()) {
        SP<Render::IFramebuffer> frame;
        if (card.id == hovered && hovered == g_projectedWorkspace)
            frame = g_projectedFrame;
        else if (const auto it = g_cardFrames.find(card.id); it != g_cardFrames.end())
            frame = it->second;
        if (!frame)
            continue;
        auto box = previewBox(card);
        if (!monitor->logicalBox().containsPoint(box.middle()))
            continue;
        box.translate(-monitor->m_position).scale(monitor->m_scale).round();
        renderer->addPassElement(ctx, makeUnique<CTexPassElement>(
            CTexPassElement::SRenderData{.tex = frame->getTexture(), .box = box, .round = static_cast<int>(5 * monitor->m_scale)}));
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
    for (const auto& monitor : ::State::monitorState()->monitors()) {
        if (monitor && monitor->logicalBox().containsPoint(coords)) {
            const auto box = monitor->logicalBox();
            const auto topInset = std::max(0., monitor->logicalBoxMinusReserved().y - box.y);
            g_pAdapter->onPointerMotion({coords.x, coords.y}, {box.x, box.y, box.w, box.h, topInset}, now);
            const auto state = g_pAdapter->getState();
            if (state == State::StripOpen || state == State::HoverTarget) {
                if (g_stripMonitor != monitor) {
                    stopPreview();
                    g_stripMonitor = monitor;
                    if (g_previewTimer)
                        g_previewTimer->updateTimeout(PREVIEW_INTERVAL);
                }
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

    const auto controller = static_cast<Layout::Supplementary::CDragStateController*>(thisptr);
    const auto target = controller ? controller->target() : nullptr;
    const auto draggedWindow = target ? target->window() : nullptr;
    if (draggedWindow) {
        token = reinterpret_cast<uint64_t>(draggedWindow.get());
        if (draggedWindow->m_workspace)
            sourceWs = draggedWindow->m_workspace->numberedID().value_or(0);
    }

    g_edgeTimer->updateTimeout(std::nullopt);
    const uint64_t now = currentTimestampMs();
    const auto state = g_pAdapter->getState();
    if (g_pSessionLockManager->isSessionLocked())
        g_pAdapter->onCancel(CancelReason::SessionLock);
    else if (g_grabPoint)
        // Hyprland notifies the button release before ending a mouse drag.
        g_pAdapter->onCancel(CancelReason::DragSuperseded);
    else if (draggedWindow && (state == State::StripOpen || state == State::HoverTarget)) {
        const auto pointer = g_pInputManager->getMouseCoordsInternal();
        updatePointer(pointer, now);
        const int destination = g_pAdapter->getTargetWorkspaceId();
        if (destination > 0 && destination != sourceWs && g_stripMonitor) {
            const auto cards = g_pAdapter->getWorkspaceCards();
            const auto card = std::ranges::find_if(cards, [destination, &pointer](const auto& item) {
                return item.id == destination && CBox{item.x, item.y, item.w, item.h}.containsPoint(pointer);
            });
            if (card != cards.end())
                g_pDelegate->placement = dropPlacement(draggedWindow, controller->draggingTiled(), *card, g_stripMonitor.lock(), pointer,
                                                       g_grabAnchor.value_or(Vector2D{0.5, 0.5}));
        }
    }
    const bool ended = g_pAdapter->onDragEnd(thisptr, token, sourceWs, now);
    stopPreview();
    g_pDelegate->placement.reset();

    // Workspace focus can release buttons, so keep it outside the drag adapter's lock.
    if (const auto window = std::exchange(g_pDelegate->followWindow, {}).lock()) {
        if (const auto monitor = window->m_monitor.lock(); monitor && window->m_workspace) {
            window->m_workspace->rememberFocusedWindow(window);
            monitor->changeWorkspace(window->m_workspace, false, true);
            Desktop::focusState()->fullWindowFocus(window, Desktop::FOCUS_REASON_WORKSPACE_CHANGE);
        }
    }
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
    if (std::strcmp(__hyprland_api_get_hash(), __hyprland_api_get_client_hash()) != 0)
        throw std::runtime_error("COD-29 must be rebuilt for this Hyprland version");

    Cod29::g_pPluginHandle = handle;
    // Initialize State Machine with Config (default disabled per constraint)
    Cod29::Config cfg{};
    cfg.enabled = true; // Enabled when plugin is explicitly loaded
    cfg.stripHeight = 264; // Matches the Rice Shell workspace strip.
    cfg.dropFollow = true;
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
            if (Cod29::g_layerHook && Cod29::g_layerHook->hook()) {
                if (auto* renderWindow = Cod29::renderFunction("renderWindow", "Render::IHyprRenderer::renderWindow(")) {
                    auto* hook = HyprlandAPI::createFunctionHook(handle, renderWindow, reinterpret_cast<void*>(&Cod29::renderProjectedSplit));
                    if (hook && hook->hook())
                        Cod29::g_windowHook = hook;
                }
                Cod29::g_previewTimer = makeShared<CEventLoopTimer>(std::nullopt, Cod29::schedulePreview, nullptr);
                g_pEventLoopManager->addTimer(Cod29::g_previewTimer);
                Cod29::g_renderListener = Event::bus()->m_events.render.stage.listen(Cod29::renderPreview);
            }
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
    if (Cod29::g_windowHook) {
        HyprlandAPI::removeFunctionHook(Cod29::g_pPluginHandle, Cod29::g_windowHook);
        Cod29::g_windowHook = nullptr;
    }
    if (Cod29::g_layerHook)
        HyprlandAPI::removeFunctionHook(Cod29::g_pPluginHandle, Cod29::g_layerHook);
    Cod29::stopPreview();
    if (Cod29::g_previewTimer) {
        g_pEventLoopManager->removeTimer(Cod29::g_previewTimer);
        Cod29::g_previewTimer.reset();
    }
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
