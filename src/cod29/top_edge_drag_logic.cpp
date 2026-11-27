#include "cod29/top_edge_drag_logic.hpp"

namespace Cod29 {

const char* stateToString(State s) noexcept {
    switch (s) {
        case State::Idle:              return "Idle";
        case State::Dragging:          return "Dragging";
        case State::EdgeArmed:         return "EdgeArmed";
        case State::StripOpen:         return "StripOpen";
        case State::HoverTarget:       return "HoverTarget";
        case State::DropIntent:        return "DropIntent";
        case State::NativeReleaseOnly: return "NativeReleaseOnly";
        case State::Cleanup:           return "Cleanup";
    }
    return "Unknown";
}

const char* actionTypeToString(Action::Type t) noexcept {
    switch (t) {
        case Action::Type::None:          return "None";
        case Action::Type::ArmEdge:       return "ArmEdge";
        case Action::Type::DisarmEdge:    return "DisarmEdge";
        case Action::Type::ShowStrip:     return "ShowStrip";
        case Action::Type::HideStrip:     return "HideStrip";
        case Action::Type::TargetChanged: return "TargetChanged";
        case Action::Type::PrepareDrop:   return "PrepareDrop";
        case Action::Type::NativeEnd:     return "NativeEnd";
        case Action::Type::Reset:         return "Reset";
    }
    return "Unknown";
}

const char* dragModeToString(DragMode m) noexcept {
    switch (m) {
        case DragMode::None:   return "None";
        case DragMode::Move:   return "Move";
        case DragMode::Resize: return "Resize";
        case DragMode::Other:  return "Other";
    }
    return "Unknown";
}

const char* cancelReasonToString(CancelReason r) noexcept {
    switch (r) {
        case CancelReason::SessionLock:    return "SessionLock";
        case CancelReason::WindowUnmapped: return "WindowUnmapped";
        case CancelReason::MonitorRemoved: return "MonitorRemoved";
        case CancelReason::DragSuperseded: return "DragSuperseded";
        case CancelReason::Unknown:        return "Unknown";
    }
    return "Unknown";
}

StateMachine::StateMachine(const Config& cfg) noexcept
    : m_config(cfg) {
}

State StateMachine::getState() const noexcept {
    return m_state;
}

void StateMachine::setConfig(const Config& cfg) noexcept {
    m_config = cfg;
}

const Config& StateMachine::getConfig() const noexcept {
    return m_config;
}

int StateMachine::getSourceWorkspaceId() const noexcept {
    return m_sourceWorkspaceId;
}

int StateMachine::getTargetWorkspaceId() const noexcept {
    return m_targetWorkspaceId;
}

uint64_t StateMachine::getWindowToken() const noexcept {
    return m_windowToken;
}

uint64_t StateMachine::getEdgeArmedTimeMs() const noexcept {
    return m_edgeArmedTimeMs;
}

void StateMachine::setWorkspaceCards(const std::vector<WorkspaceCard>& cards) noexcept {
    m_workspaceCards = cards;
}

const std::vector<WorkspaceCard>& StateMachine::getWorkspaceCards() const noexcept {
    return m_workspaceCards;
}

bool StateMachine::isAtTopEdge(const Vector2D& pointer, const OutputRect& output) const noexcept {
    if (output.w <= 0.0 || output.h <= 0.0) {
        return false;
    }
    const bool withinX = (pointer.x >= output.x) && (pointer.x < (output.x + output.w));
    const bool withinY = (pointer.y >= (output.y - 1.0)) && (pointer.y <= (output.y + m_config.edgeTolerance));
    return withinX && withinY;
}

Action StateMachine::onNativeDragBegin(
    uint64_t windowToken,
    DragMode mode,
    bool thresholdReached,
    int sourceWorkspaceId,
    uint64_t timestampMs) noexcept {

    if (!m_config.enabled) {
        return Action{Action::Type::None, -1, 0};
    }

    if (mode != DragMode::Move || !thresholdReached || windowToken == 0) {
        return Action{Action::Type::None, -1, 0};
    }

    m_state = State::Dragging;
    m_windowToken = windowToken;
    m_sourceWorkspaceId = sourceWorkspaceId;
    m_targetWorkspaceId = -1;
    m_dragStartTimeMs = timestampMs;
    m_edgeArmedTimeMs = 0;

    return Action{Action::Type::None, -1, windowToken};
}

Action StateMachine::onPointerMotion(
    const Vector2D& pointer,
    const OutputRect& output,
    uint64_t timestampMs) noexcept {

    if (!m_config.enabled) {
        return Action{Action::Type::None, -1, 0};
    }

    if ((m_state == State::EdgeArmed || m_state == State::StripOpen || m_state == State::HoverTarget) &&
        (output.x != m_edgeOutput.x || output.y != m_edgeOutput.y ||
         output.w != m_edgeOutput.w || output.h != m_edgeOutput.h)) {
        const bool open = m_state != State::EdgeArmed;
        m_state = State::Dragging;
        m_targetWorkspaceId = -1;
        m_edgeArmedTimeMs = 0;
        return Action{open ? Action::Type::HideStrip : Action::Type::DisarmEdge, -1, m_windowToken};
    }

    switch (m_state) {
        case State::Idle:
            return Action{Action::Type::None, -1, 0};

        case State::Dragging: {
            if (isAtTopEdge(pointer, output)) {
                m_state = State::EdgeArmed;
                m_edgeArmedTimeMs = timestampMs;
                m_edgeOutput = output;
                return Action{Action::Type::ArmEdge, -1, m_windowToken};
            }
            return Action{Action::Type::None, -1, m_windowToken};
        }

        case State::EdgeArmed: {
            if (isAtTopEdge(pointer, output)) {
                // Pointer remains within top edge boundary; check dwell
                if (timestampMs >= m_edgeArmedTimeMs &&
                    (timestampMs - m_edgeArmedTimeMs) >= m_config.dwellTimeMs) {
                    m_state = State::StripOpen;
                    return Action{Action::Type::ShowStrip, -1, m_windowToken};
                }
                return Action{Action::Type::None, -1, m_windowToken};
            } else {
                // Retreated from top edge before dwell satisfied
                m_state = State::Dragging;
                m_edgeArmedTimeMs = 0;
                return Action{Action::Type::DisarmEdge, -1, m_windowToken};
            }
        }

        case State::StripOpen:
        case State::HoverTarget: {
            // Hysteresis exit check:
            // Strip closes below the visible strip and its hysteresis margin
            // or moves outside monitor horizontal bounds
            const double exitY = output.y + output.topInset + m_config.stripHeight + m_config.exitHysteresis;
            const bool outsideX = (pointer.x < output.x) || (pointer.x >= (output.x + output.w));
            const bool outsideY = (pointer.y < output.y) || (pointer.y > exitY);

            if (outsideX || outsideY) {
                m_state = State::Dragging;
                m_targetWorkspaceId = -1;
                m_edgeArmedTimeMs = 0;
                return Action{Action::Type::HideStrip, -1, m_windowToken};
            }

            // Inside strip bounds: check geometric hit-testing if workspace cards are registered
            {
                int foundCardId = -1;
                for (const auto& card : m_workspaceCards) {
                    if (pointer.x >= card.x && pointer.x < (card.x + card.w) &&
                        pointer.y >= card.y && pointer.y < (card.y + card.h)) {
                        foundCardId = card.id;
                        break;
                    }
                }

                if (foundCardId != -1) {
                    if (m_state != State::HoverTarget || m_targetWorkspaceId != foundCardId) {
                        m_state = State::HoverTarget;
                        m_targetWorkspaceId = foundCardId;
                        return Action{Action::Type::TargetChanged, foundCardId, m_windowToken};
                    }
                } else {
                    if (m_state == State::HoverTarget) {
                        m_state = State::StripOpen;
                        m_targetWorkspaceId = -1;
                        return Action{Action::Type::TargetChanged, -1, m_windowToken};
                    }
                }
            }

            return Action{Action::Type::None, m_targetWorkspaceId, m_windowToken};
        }

        case State::DropIntent:
        case State::NativeReleaseOnly:
        case State::Cleanup:
            return Action{Action::Type::None, -1, 0};
    }

    return Action{Action::Type::None, -1, 0};
}

Action StateMachine::onWorkspaceCardHover(int workspaceId) noexcept {
    if (!m_config.enabled) {
        return Action{Action::Type::None, -1, 0};
    }

    if (m_state == State::StripOpen || m_state == State::HoverTarget) {
        if (m_state == State::HoverTarget && m_targetWorkspaceId == workspaceId) {
            return Action{Action::Type::None, workspaceId, m_windowToken};
        }
        m_state = State::HoverTarget;
        m_targetWorkspaceId = workspaceId;
        return Action{Action::Type::TargetChanged, workspaceId, m_windowToken};
    }

    return Action{Action::Type::None, -1, 0};
}

Action StateMachine::onWorkspaceCardLeave() noexcept {
    if (!m_config.enabled) {
        return Action{Action::Type::None, -1, 0};
    }

    if (m_state == State::HoverTarget) {
        m_state = State::StripOpen;
        m_targetWorkspaceId = -1;
        return Action{Action::Type::TargetChanged, -1, m_windowToken};
    }

    return Action{Action::Type::None, -1, 0};
}

Action StateMachine::onNativeRelease(uint64_t timestampMs, int currentWorkspaceId) noexcept {
    (void)timestampMs;

    if (!m_config.enabled || m_state == State::Idle) {
        return Action{Action::Type::None, -1, 0};
    }

    const uint64_t token = m_windowToken;

    switch (m_state) {
        case State::HoverTarget: {
            if (m_targetWorkspaceId > 0 && m_targetWorkspaceId != (currentWorkspaceId > 0 ? currentWorkspaceId : m_sourceWorkspaceId)) {
                // Different workspace: commit drop intent!
                m_state = State::DropIntent;
                return Action{Action::Type::PrepareDrop, m_targetWorkspaceId, token};
            } else {
                // Same workspace drop is strict NO-OP (NativeEnd)
                m_state = State::NativeReleaseOnly;
                return Action{Action::Type::NativeEnd, -1, token};
            }
        }

        case State::StripOpen: {
            // Released outside cards (in whitespace) -> NativeEnd
            m_state = State::NativeReleaseOnly;
            return Action{Action::Type::NativeEnd, -1, token};
        }

        case State::EdgeArmed: {
            // Released during dwell before strip opened -> NativeEnd
            m_state = State::NativeReleaseOnly;
            return Action{Action::Type::NativeEnd, -1, token};
        }

        case State::Dragging: {
            // Normal move release below edge -> NativeEnd
            m_state = State::NativeReleaseOnly;
            return Action{Action::Type::NativeEnd, -1, token};
        }

        case State::DropIntent:
        case State::NativeReleaseOnly:
        case State::Cleanup: {
            // Already released; do not emit duplicate release actions
            return Action{Action::Type::None, -1, 0};
        }

        case State::Idle:
            return Action{Action::Type::None, -1, 0};
    }

    return Action{Action::Type::None, -1, 0};
}

Action StateMachine::onCancel(CancelReason reason) noexcept {
    (void)reason;

    if (m_state == State::Idle) {
        return Action{Action::Type::None, -1, 0};
    }

    const uint64_t token = m_windowToken;
    m_state = State::Idle;
    m_windowToken = 0;
    m_sourceWorkspaceId = -1;
    m_targetWorkspaceId = -1;
    m_dragStartTimeMs = 0;
    m_edgeArmedTimeMs = 0;

    return Action{Action::Type::Reset, -1, token};
}

void StateMachine::onCleanup() noexcept {
    m_state = State::Idle;
    m_windowToken = 0;
    m_sourceWorkspaceId = -1;
    m_targetWorkspaceId = -1;
    m_dragStartTimeMs = 0;
    m_edgeArmedTimeMs = 0;
}

} // namespace Cod29
