#include "cod29/drag_hook_adapter.hpp"

#include <stdexcept>
#include <iostream>

namespace Cod29 {

DragHookAdapter::DragHookAdapter(StateMachine& sm, IpcServer& ipc, ICompositorDelegate* delegate) noexcept
    : m_stateMachine(sm), m_ipcServer(ipc), m_delegate(delegate) {

    m_ipcServer.setHoverCallback([this](int wsId) {
        std::lock_guard<std::mutex> lock(m_stateMutex);
        Action act = m_stateMachine.onWorkspaceCardHover(wsId);
        dispatchAction(act);
    });

    m_ipcServer.setLeaveCallback([this]() {
        std::lock_guard<std::mutex> lock(m_stateMutex);
        Action act = m_stateMachine.onWorkspaceCardLeave();
        dispatchAction(act);
    });

    m_ipcServer.setSetCardsCallback([this](const std::vector<WorkspaceCard>& cards) {
        setWorkspaceCards(cards);
    });
}

void DragHookAdapter::dispatchAction(const Action& action) noexcept {
    switch (action.type) {
        case Action::Type::ShowStrip:
            m_stateMachine.setWorkspaceCards({});
            m_ipcServer.broadcastShowStrip(action.windowToken);
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

void DragHookAdapter::onDragBegin(uint64_t windowToken, DragMode mode, bool thresholdReached, int sourceWorkspaceId, uint64_t timestampMs,
                                  Vector2D /*grabAnchor*/) noexcept {
    std::lock_guard<std::mutex> lock(m_stateMutex);

    if (!m_stateMachine.getConfig().enabled) {
        return;
    }
    if (mode != DragMode::Move || !thresholdReached) {
        return;
    }

    if (m_stateMachine.getState() != State::Idle)
        dispatchAction(m_stateMachine.onCancel(CancelReason::DragSuperseded));
    Action act = m_stateMachine.onNativeDragBegin(windowToken, mode, thresholdReached, sourceWorkspaceId, timestampMs);
    dispatchAction(act);
}

void DragHookAdapter::onPointerMotion(const Vector2D& pointer, const OutputRect& output, uint64_t timestampMs) noexcept {
    try {
        if (m_injectException) {
            throw std::runtime_error("Simulated exception in DragHookAdapter::onPointerMotion");
        }

        std::lock_guard<std::mutex> lock(m_stateMutex);

        if (m_stateMachine.getState() == State::Idle) {
            return;
        }

        m_pointer = pointer;
        m_output = output;
        m_pointerTime = timestampMs;
        Action act = m_stateMachine.onPointerMotion(pointer, output, timestampMs);
        dispatchAction(act);

    } catch (const std::exception& e) {
        // Hardening Rule H1: Exception Quarantine
        m_quarantinedExceptions++;
        if (m_delegate) {
            try {
                m_delegate->log("ERROR", std::string("Quarantined exception in onPointerMotion: ") + e.what());
            } catch (...) {}
        }
        std::lock_guard<std::mutex> lock(m_stateMutex);
        m_stateMachine.onCancel(CancelReason::Unknown);
        m_ipcServer.broadcastHideStrip();
    } catch (...) {
        // Hardening Rule H1: Exception Quarantine
        m_quarantinedExceptions++;
        if (m_delegate) {
            try {
                m_delegate->log("ERROR", "Quarantined unknown exception in onPointerMotion");
            } catch (...) {}
        }
        std::lock_guard<std::mutex> lock(m_stateMutex);
        m_stateMachine.onCancel(CancelReason::Unknown);
        m_ipcServer.broadcastHideStrip();
    }
}

bool DragHookAdapter::onDragEnd(void* thisptr, uint64_t windowToken, int sourceWorkspaceId, uint64_t timestampMs) noexcept {
    bool nativeInvoked = false;
    bool origResult = false;
    try {
        if (m_delegate)
            m_delegate->capturePreReleaseWindow(thisptr, windowToken);

        Action action;
        bool follow = false;
        {
            std::lock_guard<std::mutex> lock(m_stateMutex);
            if (windowToken != m_stateMachine.getWindowToken())
                m_stateMachine.onCancel(CancelReason::DragSuperseded);
            action = m_stateMachine.onNativeRelease(timestampMs, sourceWorkspaceId);
            follow = m_stateMachine.getConfig().dropFollow;
        }

        // Native release can reenter callbacks; never hold the state lock across it.
        nativeInvoked = true;
        origResult = m_delegate ? m_delegate->invokeOriginalDragEnd(thisptr) : false;
        bool commit = false;
        {
            std::lock_guard<std::mutex> lock(m_stateMutex);
            commit = origResult && action.type == Action::Type::PrepareDrop &&
                m_stateMachine.getState() == State::DropIntent && m_stateMachine.getWindowToken() == windowToken;
        }
        if (commit && action.targetWorkspaceId > 0 && action.targetWorkspaceId != sourceWorkspaceId &&
            m_delegate && m_delegate->isWindowValid(windowToken))
            m_delegate->moveWindowToWorkspace(windowToken, action.targetWorkspaceId, follow);
    } catch (...) {
        ++m_quarantinedExceptions;
        if (m_delegate) {
            try { m_delegate->log("ERROR", "Quarantined exception in onDragEnd"); } catch (...) {}
            if (!nativeInvoked) {
                try { origResult = m_delegate->invokeOriginalDragEnd(thisptr); } catch (...) {}
            }
        }
    }
    {
        std::lock_guard<std::mutex> lock(m_stateMutex);
        m_stateMachine.onCleanup();
    }
    m_ipcServer.broadcastHideStrip();
    return origResult;
}

void DragHookAdapter::onCancel(CancelReason reason) noexcept {
    std::lock_guard<std::mutex> lock(m_stateMutex);
    m_stateMachine.onCancel(reason);
    m_ipcServer.broadcastReset();
}

State DragHookAdapter::getState() const noexcept {
    std::lock_guard<std::mutex> lock(m_stateMutex);
    return m_stateMachine.getState();
}

int DragHookAdapter::getTargetWorkspaceId() const noexcept {
    std::lock_guard<std::mutex> lock(m_stateMutex);
    return m_stateMachine.getTargetWorkspaceId();
}

int DragHookAdapter::getSourceWorkspaceId() const noexcept {
    std::lock_guard<std::mutex> lock(m_stateMutex);
    return m_stateMachine.getSourceWorkspaceId();
}

uint64_t DragHookAdapter::getWindowToken() const noexcept {
    std::lock_guard<std::mutex> lock(m_stateMutex);
    return m_stateMachine.getWindowToken();
}

std::vector<WorkspaceCard> DragHookAdapter::getWorkspaceCards() const noexcept {
    std::lock_guard<std::mutex> lock(m_stateMutex);
    return m_stateMachine.getWorkspaceCards();
}

void DragHookAdapter::copyPreviewState(WorkspacePreviewState& snapshot) const {
    std::lock_guard<std::mutex> lock(m_stateMutex);
    const auto& cards = m_stateMachine.getWorkspaceCards();
    snapshot.cards.assign(cards.begin(), cards.end());
    snapshot.targetWorkspaceId = m_stateMachine.getTargetWorkspaceId();
}

void DragHookAdapter::setWorkspaceCards(const std::vector<WorkspaceCard>& cards) noexcept {
    std::lock_guard<std::mutex> lock(m_stateMutex);
    m_stateMachine.setWorkspaceCards(cards);
    if (m_stateMachine.getState() == State::StripOpen || m_stateMachine.getState() == State::HoverTarget)
        dispatchAction(m_stateMachine.onPointerMotion(m_pointer, m_output, m_pointerTime));
}

} // namespace Cod29
