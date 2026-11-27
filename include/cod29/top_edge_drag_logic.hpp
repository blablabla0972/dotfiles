#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace Cod29 {

enum class State {
    Idle,
    Dragging,
    EdgeArmed,
    StripOpen,
    HoverTarget,
    DropIntent,
    NativeReleaseOnly,
    Cleanup
};

enum class DragMode {
    None,
    Move,
    Resize,
    Other
};

enum class CancelReason {
    SessionLock,
    WindowUnmapped,
    MonitorRemoved,
    DragSuperseded,
    Unknown
};

struct Config {
    union {
        bool enabled = false;              // Feature flag: MUST default strictly to false (OFF)
        bool top_edge_drag_enabled;
    };
    double edgeTolerance = 4.0;        // pixels from output physical top (range 0..6)
    uint64_t dwellTimeMs = 80;         // dwell duration (range 60..100)
    double exitHysteresis = 28.0;      // pixels below strip to trigger exit (range 24..32)
    double stripHeight = 140.0;        // strip height
    bool dropFollow = false;           // follow=false
};

struct Vector2D {
    double x = 0;
    double y = 0;
};

struct OutputRect {
    double x = 0;
    double y = 0;
    double w = 0;
    double h = 0;
    double topInset = 0;
};

struct WorkspaceCard {
    int id = 0;
    double x = 0;
    double y = 0;
    double w = 0;
    double h = 0;
    OutputRect preview{};
};

struct Action {
    enum class Type {
        None,
        ArmEdge,
        DisarmEdge,
        ShowStrip,
        HideStrip,
        TargetChanged,
        PrepareDrop,
        NativeEnd,
        Reset
    } type = Type::None;

    int targetWorkspaceId = -1;
    uint64_t windowToken = 0;

    constexpr bool operator==(const Action& other) const noexcept = default;
};

const char* stateToString(State s) noexcept;
const char* actionTypeToString(Action::Type t) noexcept;
const char* dragModeToString(DragMode m) noexcept;
const char* cancelReasonToString(CancelReason r) noexcept;

class StateMachine {
public:
    explicit StateMachine(const Config& cfg = Config{}) noexcept;
    ~StateMachine() noexcept = default;

    State getState() const noexcept;
    void setConfig(const Config& cfg) noexcept;
    const Config& getConfig() const noexcept;

    int getSourceWorkspaceId() const noexcept;
    int getTargetWorkspaceId() const noexcept;
    uint64_t getWindowToken() const noexcept;
    uint64_t getEdgeArmedTimeMs() const noexcept;

    // Events
    Action onNativeDragBegin(uint64_t windowToken, DragMode mode, bool thresholdReached, int sourceWorkspaceId, uint64_t timestampMs) noexcept;
    Action onPointerMotion(const Vector2D& pointer, const OutputRect& output, uint64_t timestampMs) noexcept;
    Action onWorkspaceCardHover(int workspaceId) noexcept;
    Action onWorkspaceCardLeave() noexcept;
    Action onNativeRelease(uint64_t timestampMs, int currentWorkspaceId = 0) noexcept;
    Action onCancel(CancelReason reason) noexcept;
    void onCleanup() noexcept;

    // Optional card list management for geometric hit-testing
    void setWorkspaceCards(const std::vector<WorkspaceCard>& cards) noexcept;
    const std::vector<WorkspaceCard>& getWorkspaceCards() const noexcept;

private:
    bool isAtTopEdge(const Vector2D& pointer, const OutputRect& output) const noexcept;

    Config m_config;
    State m_state = State::Idle;
    uint64_t m_windowToken = 0;
    int m_sourceWorkspaceId = -1;
    int m_targetWorkspaceId = -1;
    uint64_t m_dragStartTimeMs = 0;
    uint64_t m_edgeArmedTimeMs = 0;
    OutputRect m_edgeOutput{};
    std::vector<WorkspaceCard> m_workspaceCards;
};

} // namespace Cod29
