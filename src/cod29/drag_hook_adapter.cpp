#include "cod29/drag_hook_adapter.hpp"

#include <stdexcept>
#include <iostream>

namespace Cod29 {

DragHookAdapter::DragHookAdapter(StateMachine& sm, IpcServer& ipc, ICompositorDelegate* delegate) noexcept
    : m_stateMachine(sm), m_ipcServer(ipc), m_delegate(delegate) {

    m_ipcServer.setHoverCallback([this](int wsId) {
        Action act = m_stateMachine.onWorkspaceCardHover(wsId);
        dispatchAction(act);
    });

    m_ipcServer.setLeaveCallback([this]() {
        Action act = m_stateMachine.onWorkspaceCardLeave();
        dispatchAction(act);
    });

    m_ipcServer.setSetCardsCallback([this](const std::vector<WorkspaceCard>& cards) {
        m_stateMachine.setWorkspaceCards(cards);
    });
}

void DragHookAdapter::dispatchAction(const Action& action) noexcept {
    switch (action.type) {
        case Action::Type::ShowStrip:
            m_ipcServer.broadcastShowStrip();
            break;
        case Action::Type::HideStrip:
            m_ipcServer.broadcastHideStrip();
            break;
        case Action::Type::TargetChanged:
            m_ipcServer.broadcastTargetChanged(action.targetWorkspaceId);
            break;
        case Action::Type::Reset:
            m_ipcServer.broadcastReset();
            break;
        default:
            break;
    }
}

void DragHookAdapter::onDragBegin(uint64_t windowToken, DragMode mode, bool thresholdReached, int sourceWorkspaceId, uint64_t timestampMs) noexcept {
    if (!m_stateMachine.getConfig().enabled) {
        return;
    }
    if (mode != DragMode::Move || !thresholdReached) {
        return;
    }

    Action act = m_stateMachine.onNativeDragBegin(windowToken, mode, thresholdReached, sourceWorkspaceId, timestampMs);
    dispatchAction(act);
}

void DragHookAdapter::onPointerMotion(const Vector2D& pointer, const OutputRect& output, uint64_t timestampMs) noexcept {
    try {
        if (m_injectException) {
            throw std::runtime_error("Simulated exception in DragHookAdapter::onPointerMotion");
        }

        if (m_stateMachine.getState() == State::Idle) {
            return;
        }

        Action act = m_stateMachine.onPointerMotion(pointer, output, timestampMs);
        dispatchAction(act);

    } catch (const std::exception& e) {
        // Hardening Rule H1: Exception Quarantine
        m_quarantinedExceptions++;
        if (m_delegate) {
            m_delegate->log("ERROR", std::string("Quarantined exception in onPointerMotion: ") + e.what());
        }
        m_stateMachine.onCancel(CancelReason::Unknown);
        m_ipcServer.broadcastHideStrip();
    } catch (...) {
        // Hardening Rule H1: Exception Quarantine
        m_quarantinedExceptions++;
        if (m_delegate) {
            m_delegate->log("ERROR", "Quarantined unknown exception in onPointerMotion");
        }
        m_stateMachine.onCancel(CancelReason::Unknown);
        m_ipcServer.broadcastHideStrip();
    }
}

bool DragHookAdapter::onDragEnd(void* thisptr, uint64_t windowToken, int sourceWorkspaceId, uint64_t timestampMs) noexcept {
    try {
        // Hardening Rule H2: Pre-Release Window Reference Capture
        if (m_delegate) {
            m_delegate->capturePreReleaseWindow(thisptr, windowToken);
        }

        // Query state machine for drop intent before grab termination
        const Action action = m_stateMachine.onNativeRelease(timestampMs);

        // Invoke original dragEnd() to release grab and update layout
        const bool origResult = m_delegate ? m_delegate->invokeOriginalDragEnd(thisptr) : false;

        // Hardening Rule H3: Aborted Release State Machine Reset
        if (!origResult) {
            m_stateMachine.onCancel(CancelReason::DragSuperseded);
            m_ipcServer.broadcastHideStrip();
            return false;
        }

        // Phase 3: Atomic Window Transfer Commit
        if (action.type == Action::Type::PrepareDrop) {
            // Hardening Rule H2: Check post-release validity of window
            if (m_delegate && !m_delegate->isWindowValid(windowToken)) {
                // Window was destroyed/unmapped during dragEnd; cleanly abort move
                m_stateMachine.onCleanup();
                m_ipcServer.broadcastHideStrip();
                return origResult;
            }

            const int targetWsId = action.targetWorkspaceId;
            if (targetWsId > 0 && targetWsId != sourceWorkspaceId) {
                if (m_delegate) {
                    m_delegate->moveWindowToWorkspace(windowToken, targetWsId, m_stateMachine.getConfig().dropFollow);
                }
            }
        }

        // Ephemeral cleanup & UI dismissal
        m_stateMachine.onCleanup();
        m_ipcServer.broadcastHideStrip();
        return origResult;

    } catch (const std::exception& e) {
        // Hardening Rule H1: Exception Quarantine
        m_quarantinedExceptions++;
        if (m_delegate) {
            m_delegate->log("ERROR", std::string("Quarantined exception in onDragEnd: ") + e.what());
        }
        m_stateMachine.onCancel(CancelReason::Unknown);
        m_ipcServer.broadcastHideStrip();
        if (m_delegate) {
            try { return m_delegate->invokeOriginalDragEnd(thisptr); } catch (...) {}
        }
        return false;
    } catch (...) {
        // Hardening Rule H1: Exception Quarantine
        m_quarantinedExceptions++;
        if (m_delegate) {
            m_delegate->log("ERROR", "Quarantined unknown exception in onDragEnd");
        }
        m_stateMachine.onCancel(CancelReason::Unknown);
        m_ipcServer.broadcastHideStrip();
        if (m_delegate) {
            try { return m_delegate->invokeOriginalDragEnd(thisptr); } catch (...) {}
        }
        return false;
    }
}

void DragHookAdapter::onCancel(CancelReason reason) noexcept {
    m_stateMachine.onCancel(reason);
    m_ipcServer.broadcastReset();
}

} // namespace Cod29
