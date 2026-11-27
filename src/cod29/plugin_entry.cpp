#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/config/ConfigValue.hpp>
#include <hyprland/src/config/shared/workspace/WorkspaceRuleManager.hpp>
#include <hyprland/src/layout/algorithm/Algorithm.hpp>
#include <hyprland/src/layout/algorithm/tiled/dwindle/DwindleAlgorithm.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/desktop/view/window/WindowGroupMembership.hpp>
#include <hyprland/src/managers/fullscreen/FullscreenController.hpp>
#include <hyprland/src/managers/fullscreen/handler/FullscreenHandler.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
#include <hyprland/src/layout/target/WindowTarget.hpp>
#include <hyprland/src/layout/supplementary/DragController.hpp>
#include <hyprland/src/desktop/state/GlobalWindowController.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/view/window/WindowFullscreenPolicy.hpp>
#include <hyprland/src/desktop/view/window/WindowPresentation.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopManager.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/managers/SessionLockManager.hpp>
#include <hyprland/src/protocols/core/Compositor.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/SceneResources.hpp>
#include <hyprland/src/render/decorations/IHyprWindowDecoration.hpp>
#include <hyprland/src/render/decorations/DecorationPositioner.hpp>
#include <hyprland/src/render/ElementRenderer.hpp>
#include <hyprland/src/render/scene/SceneSelection.hpp>
#include <hyprland/src/state/MonitorState.hpp>
#include <hyprland/src/state/workspace/State.hpp>
#include <hyprland/src/debug/log/Logger.hpp>
#include <hyprutils/utils/ScopeGuard.hpp>

#include "cod29/top_edge_drag_logic.hpp"
#include "cod29/compositor_delegate.hpp"
#include "cod29/ipc_server.hpp"
#include "cod29/drag_hook_adapter.hpp"

#include <algorithm>
#include <array>
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
    PHLWINDOWREF leaveFullscreen;
};

static CBox contentBox(CBox tile, const CBox& workArea, const ::Config::CCssGapData& gaps, const PHLWINDOW& window) {
    const auto left = STICKS(tile.x, workArea.x) ? 0 : gaps.m_left;
    const auto top = STICKS(tile.y, workArea.y) ? 0 : gaps.m_top;
    const auto right = STICKS(tile.x + tile.w, workArea.x + workArea.w) ? 0 : gaps.m_right;
    const auto bottom = STICKS(tile.y + tile.h, workArea.y + workArea.h) ? 0 : gaps.m_bottom;
    tile.round();
    tile.x += left;
    tile.y += top;
    tile.w -= left + right;
    tile.h -= top + bottom;

    if (const auto target = window->layoutTarget(); target->isPseudo()) {
        const auto requested = target->pseudoSize();
        if (requested.x > 0 && requested.y > 0) {
            const auto size = requested * std::min({1., tile.w / requested.x, tile.h / requested.y});
            tile = CBox{tile.middle() - size / 2., size};
        }
    }

    const auto reserved = window->getFullWindowReservedArea();
    return CBox{tile.pos() + reserved.topLeft, tile.size() - reserved.topLeft - reserved.bottomRight}.round();
}

static std::optional<DropPlacement> dropPlacement(const PHLWINDOW& window, bool tiled, const WorkspaceCard& card,
                                                  const PHLWORKSPACE& workspace, const PHLMONITOR& monitor,
                                                  const Hyprutils::Math::Vector2D& cursor, const Vector2D& anchor) {
    if (!monitor || card.preview.w <= 0 || card.preview.h <= 0 || window->grouping().group() ||
        Fullscreen::controller()->isFullscreen(window))
        return std::nullopt;

    const auto fullscreen = workspace ? Fullscreen::controller()->getFullscreenWindow(workspace) : nullptr;
    if (tiled && fullscreen) {
        static auto focusUnderFullscreen = CConfigValue<::Config::INTEGER>("misc:on_focus_under_fullscreen");
        if (*focusUnderFullscreen != 2 || fullscreen->isFloating() || fullscreen->grouping().group())
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
        return DropPlacement{card.id, point, box.round(), true, {}, {}, {}};
    }

    static auto layout = CConfigValue<::Config::STRING>("general:layout");
    static auto smartSplit = CConfigValue<::Config::INTEGER>("dwindle:smart_split");
    static auto precise = CConfigValue<::Config::INTEGER>("dwindle:precise_mouse_move");
    const auto space = workspace ? workspace->space() : nullptr;
    auto* dwindle = space ? dynamic_cast<Layout::Tiled::CDwindleAlgorithm*>(space->algorithm()->tiledAlgo().get()) : nullptr;
    // shortcut: Special layouts and window rules retain native placement until they expose drop geometry.
    if ((space ? !dwindle : *layout != "dwindle") || *smartSplit || *precise)
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
                if (distance == 0.)
                    break;
            }
        }
    }
    const auto available = nearestTile.value_or(output).size();
    if (const auto maximum = window->layoutTarget()->maxSize(); maximum &&
        (maximum->x < available.x || maximum->y < available.y))
        return std::nullopt;

    CBox workArea;
    if (space) {
        workArea = space->workArea();
    } else {
        static auto gapsOut = CConfigValue<::Config::IComplexConfigValue>("general:gaps_out");
        const auto& outer = *static_cast<::Config::CCssGapData*>(gapsOut.ptr());
        const auto usable = monitor->logicalBoxMinusReserved();
        workArea = {usable.x + outer.m_left, usable.y + outer.m_top,
                    usable.w - outer.m_left - outer.m_right, usable.h - outer.m_top - outer.m_bottom};
    }
    static auto gapsIn = CConfigValue<::Config::IComplexConfigValue>("general:gaps_in");
    const auto rules = workspace ? ::Config::workspaceRuleMgr()->getWorkspaceRuleFor(workspace) : std::nullopt;
    const auto& inner = rules && rules->m_gapsIn ? *rules->m_gapsIn : *static_cast<::Config::CCssGapData*>(gapsIn.ptr());

    if (!nearestTile) {
        if (fullscreen)
            return std::nullopt;
        return DropPlacement{card.id, point, contentBox(workArea, workArea, inner, window), false, {}, {}, {}};
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
    float splitRatio = std::clamp(*ratio, .1f, 1.9f);
    if (*bias && first)
        splitRatio = 2.f - splitRatio;
    const float firstSize = (vertical ? tile.h : tile.w) / 2. * splitRatio;

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
                         neighbor, contentBox(first ? b : a, workArea, inner, neighbor), fullscreen};
}

class HyprlandCompositorDelegate : public ICompositorDelegate {
public:
    std::optional<DropPlacement> placement;
    PHLWINDOWREF followWindow;
    using origDragEnd_t = bool (*)(void* thisptr);

    void setOrigDragEnd(origDragEnd_t fn) noexcept {
        m_origDragEnd = fn;
    }

    void capturePreReleaseWindow(void* thisptr, uint64_t windowToken) override {
        m_capturedWindowRef.reset();
        if (!thisptr) return;
        auto pController = static_cast<Layout::Supplementary::CDragStateController*>(thisptr);
        if (pController) {
            auto spTarget = pController->target();
            if (spTarget) {
                auto pWindow = spTarget->window();
                if (pWindow && pWindow->mapped() && reinterpret_cast<uint64_t>(pWindow.get()) == windowToken) {
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

    bool isWindowValid(uint64_t windowToken) const override {
        const auto window = m_capturedWindowRef.lock();
        return window && window->mapped() && reinterpret_cast<uint64_t>(window.get()) == windowToken;
    }

    bool moveWindowToWorkspace(uint64_t /*windowToken*/, int targetWorkspaceId, bool follow) override {
        auto pWindow = m_capturedWindowRef.lock();
        if (!pWindow || !pWindow->mapped() || targetWorkspaceId <= 0) {
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
            if (placement && placement->workspaceId == targetWorkspaceId) {
                if (const auto fullscreen = placement->leaveFullscreen.lock())
                    Fullscreen::controller()->setFullscreenMode(fullscreen, Fullscreen::FSMODE_NONE);
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
static bool g_releasePending = false;
using BeginRender = bool (*)(Render::IHyprRenderer*, PHLMONITOR, CRegion&, Render::eRenderMode, SP<IHLBuffer>, SP<Render::IFramebuffer>,
                             bool, const Render::SRenderOptions&, std::optional<Monitor::CDamageRing::CTransaction>*);
using RenderWorkspace = void (*)(Render::IHyprRenderer*, Render::CRenderContext&, PHLWORKSPACE, const Time::steady_tp&, Render::eSceneMode);
using RenderLayer = void (*)(Render::IHyprRenderer*, Render::CRenderContext&, PHLLS, PHLMONITOR, const Time::steady_tp&, bool, bool, bool);
static BeginRender g_beginRender = nullptr;
static RenderWorkspace g_renderWorkspace = nullptr;
static CFunctionHook* g_layerHook = nullptr;
static CFunctionHook* g_previewDecorationHook = nullptr;
static CFunctionHook* g_previewSurfaceHook = nullptr;
static CHyprSignalListener g_renderListener;

struct ProjectedDrop {
    PHLWINDOW window;
    DropPlacement placement;
};
static SP<Render::IFramebuffer> g_projectedFrame;
struct ProjectedFrameGeometry {
    DropPlacement placement;
    CBox output;
};
static std::optional<ProjectedFrameGeometry> g_projectedGeometry;

struct PreviewFrame {
    SP<Render::IFramebuffer> framebuffer;
    bool ready = false;
};
static std::unordered_map<int, PreviewFrame> g_cardFrames;
static SP<Render::CSceneResources> g_sceneResources;
static PHLMONITORREF g_stripMonitor;
static SP<CEventLoopTimer> g_previewTimer;
static constexpr auto PREVIEW_INTERVAL = std::chrono::milliseconds(16);
static size_t g_nextPreviewCard = 0;
static unsigned g_backgroundSlots = 0;

struct PreviewRequest {
    WorkspaceCard card;
    PHLWORKSPACEREF workspace;
};
static std::array<std::optional<PreviewRequest>, 2> g_pendingPreviews;
static std::vector<PHLWINDOWREF> g_previewClients;

static CBox previewBox(const WorkspaceCard& card) {
    return {card.preview.x, card.preview.y, card.preview.w, card.preview.h};
}

static void hidePreview() {
    if (g_previewTimer)
        g_previewTimer->updateTimeout(std::nullopt);
    g_pendingPreviews = {};
    for (const auto& ref : g_previewClients) {
        if (const auto window = ref.lock(); window && window->mapped())
            window->setSuspended(window->isHidden() || !window->m_workspace || !window->m_workspace->visible());
    }
    g_previewClients.clear();
    g_nextPreviewCard = 0;
    g_backgroundSlots = 0;
    g_projectedGeometry.reset();
    g_stripMonitor.reset();
    for (auto& entry : g_cardFrames)
        entry.second.ready = false;
}

static void stopPreview() {
    hidePreview();
    g_projectedFrame.reset();
    g_cardFrames.clear();
}

static std::array<std::pair<const Desktop::View::CWindow*, CBox>, 3> g_previewGeometry;

static const CBox* projectedBox(const PHLWINDOW& window) {
    if (!g_previewGeometry.front().first || !window)
        return nullptr;
    const auto* candidate = window.get();
    for (const auto& [owner, box] : g_previewGeometry) {
        if (owner == candidate)
            return &box;
    }
    return nullptr;
}

static CBox previewDecorationBox(CDecorationPositioner* positioner, PHLWINDOW window) {
    using Original = CBox (*)(CDecorationPositioner*, PHLWINDOW);
    const auto original = reinterpret_cast<Original>(g_previewDecorationHook->m_original);
    auto result = original(positioner, window);
    if (const auto box = projectedBox(window)) {
        auto limit = *box;
        limit.addExtents(window->getFullWindowReservedArea());
        limit.expand(window->presentation().borderSize());
        result = result.intersection(limit);
    }
    return result;
}

static void previewSurfaceUV(Render::IElementRenderer* renderer, Render::CRenderContext& ctx, PHLWINDOW window,
                             SP<CWLSurfaceResource> surface, PHLMONITOR monitor, bool main,
                             const Hyprutils::Math::Vector2D& physicalSize, const Hyprutils::Math::Vector2D& logicalSize,
                             bool fractionalCorrection) {
    using Original = void (*)(Render::IElementRenderer*, Render::CRenderContext&, PHLWINDOW, SP<CWLSurfaceResource>, PHLMONITOR,
                              bool, const Hyprutils::Math::Vector2D&, const Hyprutils::Math::Vector2D&, bool);
    const auto original = reinterpret_cast<Original>(g_previewSurfaceHook->m_original);
    if (main && surface && projectedBox(window)) {
        // Preserve the entire committed client buffer while the native scene uses the projected window bounds.
        auto size = surface->m_current.size;
        const auto& viewport = surface->m_current.viewport;
        if (viewport.hasDestination)
            size = viewport.destination;
        else if (viewport.hasSource)
            size = viewport.source.size();
        if (size.x > 0 && size.y > 0) {
            original(renderer, ctx, window, surface, monitor, main, (size * monitor->m_scale).round(), size, false);
            return;
        }
    }
    original(renderer, ctx, window, surface, monitor, main, physicalSize, logicalSize, fractionalCorrection);
}

static void updatePreviewDecorations(const PHLWINDOW& window) {
    // The shadow pass can cache positioning for every decoration on this window.
    g_pDecorationPositioner->onWindowUpdate(window);
    for (const auto& decoration : window->presentation().decorations()) {
        if (decoration->getDecorationType() == DECORATION_SHADOW) {
            decoration->updateWindow(window);
            return;
        }
    }
}

class PreviewWindowGeometry {
public:
    PreviewWindowGeometry(const PHLWINDOW& window, const CBox& box)
        : m_window(window), m_box(window->positionAnimation()->value(), window->sizeAnimation()->value()) {
        // Update the renderer's current values without scheduling animations or configuring clients.
        window->positionAnimation()->value() = box.pos();
        window->sizeAnimation()->value() = box.size();
        updatePreviewDecorations(window);
    }

    PreviewWindowGeometry(const PreviewWindowGeometry&) = delete;
    PreviewWindowGeometry& operator=(const PreviewWindowGeometry&) = delete;

    ~PreviewWindowGeometry() {
        m_window->positionAnimation()->value() = m_box.pos();
        m_window->sizeAnimation()->value() = m_box.size();
        updatePreviewDecorations(m_window);
    }

private:
    PHLWINDOW m_window;
    CBox m_box;
};

// The plugin ABI check pins this layout to Hyprland's installed fullscreen handler.
struct FullscreenStates {
    using Map = std::unordered_map<WP<Layout::ITarget>, Fullscreen::SFullscreenMode>;
    using Member = Map Fullscreen::IFullscreenHandler::*;
    friend Member fullscreenStatesMember(FullscreenStates);
};

template <FullscreenStates::Member Member>
struct FullscreenStateAccess {
    friend FullscreenStates::Member fullscreenStatesMember(FullscreenStates) { return Member; }
};
template struct FullscreenStateAccess<&Fullscreen::IFullscreenHandler::m_fsTargets>;

class PreviewFullscreen {
public:
    PreviewFullscreen(const PHLWORKSPACE& workspace, const PHLWINDOW& fullscreen) {
        if (!fullscreen)
            return;
        const auto& tiled = workspace->space()->algorithm()->tiledAlgo();
        m_handler = Fullscreen::controller()->layoutManagedFS(fullscreen) ? tiled->getFSHandler()
                                                                        : tiled->IModeAlgorithm::getFSHandler();
        if (!m_handler)
            return;
        auto& modes = m_handler.get()->*fullscreenStatesMember(FullscreenStates{});
        const auto mode = modes.find(fullscreen->windowTarget());
        if (mode == modes.end())
            return;

        // Collect changed alpha values before editing the native scene.
        for (const auto& window : Desktop::windowState()->windows()) {
            if (window->m_workspace != workspace || !window->mapped() || window->isHidden())
                continue;
            const float alpha = window->presentation().alpha(Desktop::View::WINDOW_ALPHA_FULLSCREEN)->value();
            if (alpha != 1.f)
                m_savedAlpha.emplace_back(window, alpha);
        }
        m_state = modes.extract(mode);
        for (const auto& entry : m_savedAlpha)
            entry.first->presentation().alpha(Desktop::View::WINDOW_ALPHA_FULLSCREEN)->value() = 1.f;
    }

    PreviewFullscreen(const PreviewFullscreen&) = delete;
    PreviewFullscreen& operator=(const PreviewFullscreen&) = delete;

    ~PreviewFullscreen() {
        for (const auto& [window, saved] : m_savedAlpha)
            window->presentation().alpha(Desktop::View::WINDOW_ALPHA_FULLSCREEN)->value() = saved;
        if (!m_state.empty())
            (m_handler.get()->*fullscreenStatesMember(FullscreenStates{})).insert(std::move(m_state));
    }

private:
    WP<Fullscreen::IFullscreenHandler> m_handler;
    FullscreenStates::Map::node_type m_state;
    std::vector<std::pair<PHLWINDOW, float>> m_savedAlpha;
};

static bool renderCard(const PHLWORKSPACE& workspace, const PHLMONITOR& monitor,
                       SP<Render::IFramebuffer>& framebuffer, const ProjectedDrop* projection = nullptr) {
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

    const auto fullscreen = projection ? projection->placement.leaveFullscreen.lock() : nullptr;
    const PreviewFullscreen fullscreenPreview(workspace, fullscreen);
    std::optional<PreviewWindowGeometry> draggedGeometry;
    std::optional<PreviewWindowGeometry> neighborGeometry;
    std::optional<PreviewWindowGeometry> fullscreenGeometry;
    const auto dragged = projection ? projection->window : nullptr;
    const auto target = dragged ? dragged->windowTarget() : nullptr;
    const auto originalWorkspace = dragged ? dragged->m_workspace : nullptr;
    const auto originalMonitor = dragged ? dragged->m_monitor : PHLMONITORREF{};
    const bool originalFloating = target && target->floating();
    const bool originallyOverFullscreen = dragged && dragged->fullscreenPolicy().allowedOverFullscreen();
    const auto restore = Hyprutils::Utils::CScopeGuard([&] {
        g_previewGeometry = {};
        if (dragged) {
            dragged->m_workspace = originalWorkspace;
            dragged->m_monitor = originalMonitor;
            target->setFloatingInitial(originalFloating);
            dragged->fullscreenPolicy().setAllowedOverFullscreen(originallyOverFullscreen);
        }
    });

    if (dragged) {
        // Selection and z-order belong to the native workspace renderer, including popups and panels.
        dragged->m_workspace = workspace;
        dragged->m_monitor = monitor;
        target->setFloatingInitial(projection->placement.floating);
        if (projection->placement.floating)
            dragged->fullscreenPolicy().setAllowedOverFullscreen(true);
        g_previewGeometry[0] = {dragged.get(), projection->placement.box};
        draggedGeometry.emplace(dragged, projection->placement.box);
        const auto neighbor = projection->placement.neighbor.lock();
        if (neighbor) {
            g_previewGeometry[1] = {neighbor.get(), projection->placement.neighborBox};
            neighborGeometry.emplace(neighbor, projection->placement.neighborBox);
        }
        if (fullscreen && fullscreen != neighbor) {
            const auto& space = workspace->space();
            auto* dwindle = static_cast<Layout::Tiled::CDwindleAlgorithm*>(space->algorithm()->tiledAlgo().get());
            static auto gapsIn = CConfigValue<::Config::IComplexConfigValue>("general:gaps_in");
            const auto rules = ::Config::workspaceRuleMgr()->getWorkspaceRuleFor(workspace);
            const auto& gaps = rules && rules->m_gapsIn ? *rules->m_gapsIn : *static_cast<::Config::CCssGapData*>(gapsIn.ptr());
            if (const auto node = dwindle->getNodeFromWindow(fullscreen)) {
                const auto box = contentBox(node->box, space->workArea(), gaps, fullscreen);
                g_previewGeometry[2] = {fullscreen.get(), box};
                fullscreenGeometry.emplace(fullscreen, box);
            }
        }
    }

    g_renderWorkspace(renderer, ctx, workspace, Time::steadyNow(), Render::eSceneMode::WORKSPACE_WITH_SHELL);
    renderer->endRender();
    return true;
}

static void schedulePreview(SP<CEventLoopTimer> timer, void*) {
    const auto monitor = g_stripMonitor.lock();
    if (!monitor || g_pSessionLockManager->isSessionLocked())
        return;

    timer->updateTimeout(PREVIEW_INTERVAL);
    if (g_pendingPreviews[0])
        return;

    static WorkspacePreviewState snapshot;
    g_pAdapter->copyPreviewState(snapshot);
    const auto& cards = snapshot.cards;
    const int hovered = snapshot.targetWorkspaceId;
    const auto output = monitor->logicalBox();
    const auto queue = [&](const WorkspaceCard& card, size_t slot) {
        const auto box = previewBox(card);
        if (box.empty() || !output.containsPoint(box.middle()))
            return false;
        const auto workspace = workspaceById(card.id);
        if (!workspace)
            return false;
        g_pendingPreviews[slot] = PreviewRequest{card, workspace};
        g_pHyprRenderer->damageBox(box);
        return true;
    };

    const auto priority = std::ranges::find_if(cards, [&](const auto& card) {
        return card.id == hovered && output.containsPoint(previewBox(card).middle());
    });
    // Refresh the destination on every tick and share every second tick with the other cards.
    const bool queuedDestination = priority != cards.end() && queue(*priority, 0);
    if (queuedDestination && ++g_backgroundSlots % 2 != 0)
        return;
    for (size_t i = 0; i < cards.size(); ++i) {
        const auto& card = cards[g_nextPreviewCard++ % cards.size()];
        if (card.id != hovered && queue(card, queuedDestination ? 1 : 0))
            return;
    }
}

static void renderPreviewRequest(const PreviewRequest& request, int hovered) {
    const auto workspace = request.workspace.lock();
    if (!workspace)
        return;

    const auto owner = workspace->m_monitor.lock();
    const auto& card = request.card;
    std::optional<ProjectedDrop> projection;
    if (card.id == hovered) {
        const auto& controller = g_layoutManager->dragController();
        const auto target = controller->target();
        const auto window = target ? target->window() : nullptr;
        const auto pointer = g_pInputManager->getMouseCoordsInternal();
        if (window && window->windowTarget() && window->m_workspace != workspace &&
            CBox{card.x, card.y, card.w, card.h}.containsPoint(pointer)) {
            const bool tiled = controller->draggingTiled();
            const auto placement = dropPlacement(window, tiled, card, workspace, owner, pointer,
                                                 g_grabAnchor.value_or(Vector2D{0.5, 0.5}));
            if (placement && !placement->box.empty())
                projection = ProjectedDrop{window, *placement};
        }
    }

    if (projection) {
        if (renderCard(workspace, owner, g_projectedFrame, &*projection))
            g_projectedGeometry = ProjectedFrameGeometry{projection->placement, owner->logicalBox()};
        else
            g_projectedGeometry.reset();
    } else {
        if (g_projectedGeometry && g_projectedGeometry->placement.workspaceId == card.id)
            g_projectedGeometry.reset();
        auto [entry, inserted] = g_cardFrames.try_emplace(card.id);
        auto& frame = entry->second;
        if (!renderCard(workspace, owner, frame.framebuffer)) {
            if (inserted)
                g_cardFrames.erase(entry);
            return;
        }
        frame.ready = true;
    }

    if (workspace->visible())
        return;

    // Inactive xdg-toplevels can stop rendering while suspended, even when sent frame callbacks.
    for (const auto& window : Desktop::windowState()->windows()) {
        if (window->m_workspace != workspace || !window->mapped() || window->isHidden())
            continue;
        window->setSuspended(false);
        if (!std::ranges::contains(g_previewClients, window))
            g_previewClients.emplace_back(window);
    }
    if (owner)
        g_pHyprRenderer->sendFrameEventsToWorkspace(owner, workspace, Time::steadyNow());
}

static void renderPreview(const Event::SRenderStageEvent& event) {
    if (event.stage != RENDER_PRE || !g_pendingPreviews[0] || g_stripMonitor != event.monitor ||
        g_pSessionLockManager->isSessionLocked())
        return;
    const auto requests = std::exchange(g_pendingPreviews, {});
    const int hovered = g_pAdapter->getTargetWorkspaceId();
    for (const auto& request : requests) {
        if (request)
            renderPreviewRequest(*request, hovered);
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

    static WorkspacePreviewState snapshot;
    g_pAdapter->copyPreviewState(snapshot);
    const int hovered = snapshot.targetWorkspaceId;
    const auto output = monitor->logicalBox();
    for (const auto& card : snapshot.cards) {
        const bool projected = card.id == hovered && g_projectedGeometry && g_projectedGeometry->placement.workspaceId == hovered;
        SP<Render::IFramebuffer> frame;
        if (projected)
            frame = g_projectedFrame;
        else if (const auto it = g_cardFrames.find(card.id); it != g_cardFrames.end() && it->second.ready)
            frame = it->second.framebuffer;
        if (!frame)
            continue;
        const auto box = previewBox(card);
        if (!output.containsPoint(box.middle()))
            continue;
        CTexPassElement::SRenderData data;
        data.tex = frame->getTexture();
        data.box = box.copy().translate(-monitor->m_position).scale(monitor->m_scale).round();
        data.round = static_cast<int>(5. * monitor->m_scale);
        renderer->addPassElement(ctx, makeUnique<CTexPassElement>(data));
        if (projected) {
            const auto& geometry = *g_projectedGeometry;
            const auto& source = geometry.output;
            auto outline = geometry.placement.box.intersection(source).translate(-source.pos())
                               .scale({data.box.w / source.w, data.box.h / source.h}).translate(data.box.pos()).round();
            outline = outline.intersection(data.box.copy().expand(-std::ceil(monitor->m_scale)));
            if (!outline.empty()) {
                // A native window border can fall between samples when the live scene is shrunk.
                static auto accent = CConfigValue<::Config::IComplexConfigValue>("general:col.active_border");
                CBorderPassElement::SBorderData border;
                border.box = outline;
                border.grad1 = *static_cast<::Config::CGradientValueData*>(accent.ptr());
                border.round = static_cast<int>(2. * monitor->m_scale);
                renderer->addPassElement(ctx, makeUnique<CBorderPassElement>(border));
            }
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
    const auto target = g_layoutManager->dragController()->target();
    const auto window = target ? target->window() : nullptr;
    if (g_pSessionLockManager->isSessionLocked() || !window || !window->mapped() ||
        reinterpret_cast<uint64_t>(window.get()) != g_pAdapter->getWindowToken()) {
        stopPreview();
        g_pAdapter->onCancel(CancelReason::DragSuperseded);
        return;
    }
    for (const auto& monitor : ::State::monitorState()->monitors()) {
        if (monitor && monitor->logicalBox().containsPoint(coords)) {
            const auto box = monitor->logicalBox();
            const auto topInset = std::max(0., monitor->logicalBoxMinusReserved().y - box.y);
            g_pAdapter->onPointerMotion({coords.x, coords.y}, {box.x, box.y, box.w, box.h, topInset}, now);
            const int hovered = g_pAdapter->getTargetWorkspaceId();
            if (g_projectedGeometry && g_projectedGeometry->placement.workspaceId != hovered)
                g_projectedGeometry.reset();
            const auto state = g_pAdapter->getState();
            if (state == State::StripOpen || state == State::HoverTarget) {
                if (g_stripMonitor != monitor) {
                    hidePreview();
                    g_stripMonitor = monitor;
                    if (g_previewTimer)
                        g_previewTimer->updateTimeout(PREVIEW_INTERVAL);
                }
            } else if (g_stripMonitor) {
                // Keep the allocations for this drag. A reopened strip starts with fresh captures.
                hidePreview();
            }
            return;
        }
    }
    stopPreview();
    g_pAdapter->onCancel(CancelReason::MonitorRemoved);
}

static void onEdgeDwell(SP<CEventLoopTimer> timer, void*) {
    if (g_pAdapter->getState() != State::Idle) {
        updatePointer(g_pInputManager->getMouseCoordsInternal(), currentTimestampMs());
        if (g_pAdapter->getState() != State::Idle)
            timer->updateTimeout(std::chrono::milliseconds(16));
    }
}

static void onMouseButton(const IPointer::SButtonEvent& event, Event::SCallbackInfo&) {
    if (event.button != BTN_LEFT)
        return;
    if (event.state == WL_POINTER_BUTTON_STATE_PRESSED) {
        g_releasePending = false;
        g_grabPoint = g_pInputManager->getMouseCoordsInternal();
    } else {
        g_releasePending = true;
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
    else if (!std::exchange(g_releasePending, false))
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
            if (card != cards.end()) {
                const auto workspace = workspaceById(destination);
                const auto monitor = workspace ? workspace->m_monitor.lock() : g_stripMonitor.lock();
                const bool tiled = controller->draggingTiled();
                if (g_projectedGeometry && g_projectedGeometry->placement.workspaceId == destination)
                    g_pDelegate->placement = g_projectedGeometry->placement;
                else
                    g_pDelegate->placement = dropPlacement(draggedWindow, tiled, *card, workspace, monitor,
                                                           pointer, g_grabAnchor.value_or(Vector2D{0.5, 0.5}));
            }
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

static void onMouseMove() noexcept {
    if (!g_pAdapter || !g_pStateMachine) return;

    const auto coords = g_pInputManager->getMouseCoordsInternal();
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
        g_releasePending = false;
        const uint64_t token = reinterpret_cast<uint64_t>(window.get());
        const int sourceWs = window->m_workspace ? static_cast<int>(window->m_workspace->numberedID().value_or(0)) : -1;
        g_pAdapter->onDragBegin(token, DragMode::Move, true, sourceWs, now, g_grabAnchor.value_or(Vector2D{0.5, 0.5}));
    }

    updatePointer(coords, now);
    if (g_pAdapter->getState() != State::Idle && !g_edgeTimer->armed())
        g_edgeTimer->updateTimeout(std::chrono::milliseconds(16));
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

    // Initialize Drag Hook Adapter
    Cod29::g_pAdapter = std::make_unique<Cod29::DragHookAdapter>(
        *Cod29::g_pStateMachine,
        *Cod29::g_pIpcServer,
        Cod29::g_pDelegate.get()
    );
    if (!Cod29::g_pIpcServer->start())
        throw std::runtime_error("COD-29 IPC socket could not start");

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
        Cod29::g_pIpcServer->stop();
        throw std::runtime_error("COD-29 dragEnd symbol unavailable");
    }

    Cod29::g_edgeTimer = makeShared<CEventLoopTimer>(std::nullopt, Cod29::onEdgeDwell, nullptr);
    g_pEventLoopManager->addTimer(Cod29::g_edgeTimer);

    // Register function hook
    Cod29::g_pDragEndHook = HyprlandAPI::createFunctionHook(handle, targetFunc, reinterpret_cast<void*>(&Cod29::hkDragEnd));
    if (Cod29::g_pDragEndHook && Cod29::g_pDragEndHook->hook()) {
        Cod29::g_pDelegate->setOrigDragEnd(
            reinterpret_cast<Cod29::HyprlandCompositorDelegate::origDragEnd_t>(Cod29::g_pDragEndHook->m_original)
        );
    } else {
        Cod29::g_pIpcServer->stop();
        g_pEventLoopManager->removeTimer(Cod29::g_edgeTimer);
        Cod29::g_edgeTimer.reset();
        throw std::runtime_error("COD-29 dragEnd hook failed");
    }

    // Register mouse move signal listener
    Cod29::g_mouseMoveListener = g_layoutManager->dragController()->m_events.motion.listen(Cod29::onMouseMove);
    Cod29::g_mouseButtonListener = Event::bus()->m_events.input.mouse.button.listen(Cod29::onMouseButton);

    Cod29::g_beginRender = reinterpret_cast<Cod29::BeginRender>(Cod29::renderFunction("beginRender", "Render::IHyprRenderer::beginRender("));
    Cod29::g_renderWorkspace = reinterpret_cast<Cod29::RenderWorkspace>(
        Cod29::renderFunction("renderWorkspace", "Render::eSceneMode)"));
    if (Cod29::g_beginRender && Cod29::g_renderWorkspace) {
        const auto hookRenderer = [&](const char* symbol, const char* signature, void* callback) -> CFunctionHook* {
            const auto address = Cod29::renderFunction(symbol, signature);
            if (!address)
                return nullptr;
            const auto hook = HyprlandAPI::createFunctionHook(handle, address, callback);
            if (hook && hook->hook())
                return hook;
            if (hook)
                HyprlandAPI::removeFunctionHook(handle, hook);
            return nullptr;
        };
        Cod29::g_layerHook = hookRenderer("renderLayer", "Render::IHyprRenderer::renderLayer(",
                                          reinterpret_cast<void*>(&Cod29::renderStripLayer));
        Cod29::g_previewDecorationHook = hookRenderer("getBoxWithIncludedDecos", "CDecorationPositioner::getBoxWithIncludedDecos(",
                                                      reinterpret_cast<void*>(&Cod29::previewDecorationBox));
        Cod29::g_previewSurfaceHook = hookRenderer("calculateUVForSurface", "Render::IElementRenderer::calculateUVForSurface(",
                                                   reinterpret_cast<void*>(&Cod29::previewSurfaceUV));
        if (Cod29::g_layerHook && Cod29::g_previewDecorationHook && Cod29::g_previewSurfaceHook) {
            Cod29::g_previewTimer = makeShared<CEventLoopTimer>(std::nullopt, Cod29::schedulePreview, nullptr);
            g_pEventLoopManager->addTimer(Cod29::g_previewTimer);
            Cod29::g_renderListener = Event::bus()->m_events.render.stage.listen(Cod29::renderPreview);
        }
    }

    return PLUGIN_DESCRIPTION_INFO{
        .name = "cod29_top_edge_drag",
        .description = "COD-29 Top-edge Workspace Drag for Rice Shell",
        .author = "Teamwork Engineering",
        .version = "0.1.5"
    };
}

APICALL EXPORT void PLUGIN_EXIT() {
    Cod29::g_mouseMoveListener.reset();
    Cod29::g_mouseButtonListener.reset();
    Cod29::g_renderListener.reset();
    if (Cod29::g_previewSurfaceHook)
        HyprlandAPI::removeFunctionHook(Cod29::g_pPluginHandle, Cod29::g_previewSurfaceHook);
    if (Cod29::g_previewDecorationHook)
        HyprlandAPI::removeFunctionHook(Cod29::g_pPluginHandle, Cod29::g_previewDecorationHook);
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
