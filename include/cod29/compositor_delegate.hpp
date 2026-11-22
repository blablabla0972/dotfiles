#pragma once

#include <cstdint>
#include <string>

namespace Cod29 {

/**
 * @brief Abstract interface mediating interactions between the COD-29 hook
 *        adapter and the Hyprland compositor.
 *
 * This abstraction enables deterministic, headless integration testing of the
 * entire drag-to-workspace pipeline and Hardening Rules (H1, H2, H3) without
 * requiring a live Wayland compositor instance.
 */
class ICompositorDelegate {
public:
    virtual ~ICompositorDelegate() = default;

    /**
     * @brief Capture weak reference to target window prior to grab dissolution.
     *        Satisfies Hardening Rule H2.
     * @param thisptr Pointer to CDragStateController instance.
     * @param windowToken Unique token identifying the window being dragged.
     */
    virtual void capturePreReleaseWindow(void* thisptr, uint64_t windowToken) = 0;

    /**
     * @brief Invoke original CDragStateController::dragEnd() via trampoline hook.
     * @param thisptr Pointer to CDragStateController instance.
     * @return true if compositor drag session was cleanly terminated; false otherwise.
     */
    virtual bool invokeOriginalDragEnd(void* thisptr) = 0;

    /**
     * @brief Check whether the captured window weak reference is still valid post-release.
     *        Satisfies Hardening Rule H2 (detects destruction during release).
     * @param windowToken Unique token identifying the window.
     * @return true if window reference is valid and alive; false if destroyed/unmapped.
     */
    virtual bool isWindowValid(uint64_t windowToken) const = 0;

    /**
     * @brief Atomically dispatch window movement to target workspace.
     * @param windowToken Unique token identifying the window.
     * @param targetWorkspaceId Numerical ID of the destination workspace.
     * @param follow Whether focus should switch to the destination workspace (must be false).
     * @return true if dispatch succeeded; false otherwise.
     */
    virtual bool moveWindowToWorkspace(uint64_t windowToken, int targetWorkspaceId, bool follow) = 0;

    /**
     * @brief Log message to compositor logging facility.
     * @param level Severity level ("INFO", "WARN", "ERROR").
     * @param message Text message to log.
     */
    virtual void log(const std::string& level, const std::string& message) = 0;
};

} // namespace Cod29
