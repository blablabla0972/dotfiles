#pragma once

#include "cod29/top_edge_drag_logic.hpp"
#include "cod29/compositor_delegate.hpp"
#include "cod29/ipc_server.hpp"

#include <cstdint>
#include <atomic>
#include <mutex>
#include <vector>

namespace Cod29 {

/**
 * @brief Hook adapter orchestrating interaction between Hyprland input/drag events,
 *        the pure C++ StateMachine, and the UNIX domain socket IpcServer.
 *
 * Implements Hardening Rules:
 * - H1: Exception Quarantine (all entry points noexcept with try/catch quarantine).
 * - H2: Pre-Release Window Reference Capture via weak reference and post-release check.
 * - H3: Aborted Release Reset on false return from origDragEnd().
 * - Thread-Safe State Machine Synchronization (Defect C5).
 */
class DragHookAdapter {
public:
    DragHookAdapter(StateMachine& sm, IpcServer& ipc, ICompositorDelegate* delegate = nullptr) noexcept;
    ~DragHookAdapter() noexcept = default;

    // Gesture initiation
    void onDragBegin(uint64_t windowToken, DragMode mode, bool thresholdReached, int sourceWorkspaceId, uint64_t timestampMs) noexcept;

    // Passive pointer motion tracking (Rule H1)
    void onPointerMotion(const Vector2D& pointer, const OutputRect& output, uint64_t timestampMs) noexcept;

    // Intercepted dragEnd hook callback (Rules H1, H2, H3)
    bool onDragEnd(void* thisptr, uint64_t windowToken, int sourceWorkspaceId, uint64_t timestampMs) noexcept;

    // Explicit gesture cancellation (session lock, window unmapped, monitor hotplug)
    void onCancel(CancelReason reason) noexcept;

    // Delegate management
    void setDelegate(ICompositorDelegate* delegate) noexcept { m_delegate = delegate; }
    ICompositorDelegate* getDelegate() const noexcept { return m_delegate; }

    // Synchronized state machine access (Defect C5)
    State getState() const noexcept;
    int getTargetWorkspaceId() const noexcept;
    int getSourceWorkspaceId() const noexcept;
    std::vector<WorkspaceCard> getWorkspaceCards() const noexcept;
    void setWorkspaceCards(const std::vector<WorkspaceCard>& cards) noexcept;

    StateMachine& getStateMachine() noexcept { return m_stateMachine; }
    const StateMachine& getStateMachine() const noexcept { return m_stateMachine; }

    // Hardening Rule H1 inspection & test fault injection
    size_t getQuarantinedExceptionCount() const noexcept { return m_quarantinedExceptions.load(); }
    void injectMotionExceptionForTest(bool inject) noexcept { m_injectException = inject; }

private:
    void dispatchAction(const Action& action) noexcept;

    mutable std::mutex m_stateMutex;
    StateMachine& m_stateMachine;
    IpcServer& m_ipcServer;
    ICompositorDelegate* m_delegate = nullptr;

    std::atomic<size_t> m_quarantinedExceptions{0};
    bool m_injectException = false;
};

} // namespace Cod29
