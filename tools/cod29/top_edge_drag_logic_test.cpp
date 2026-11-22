#include "cod29/top_edge_drag_logic.hpp"

#include <iostream>
#include <iomanip>
#include <string_view>
#include <vector>
#include <cstdlib>

namespace {

int g_passCount = 0;
int g_failCount = 0;

void reportTest(std::string_view testId, std::string_view desc, bool passed, std::string_view detail = "") {
    if (passed) {
        ++g_passCount;
        std::cout << "  [\033[32mPASS\033[0m] " << testId << ": " << desc << "\n";
    } else {
        ++g_failCount;
        std::cout << "  [\033[31mFAIL\033[0m] " << testId << ": " << desc << "\n";
        if (!detail.empty()) {
            std::cout << "         Detail: " << detail << "\n";
        }
    }
}

#define TEST_ASSERT(cond, msg) \
    do { \
        if (!(cond)) { \
            reportTest(testId, desc, false, msg); \
            return false; \
        } \
    } while (0)

// -----------------------------------------------------------------------------
// L01: Feature flag OFF (remains Idle, zero actions emitted)
// -----------------------------------------------------------------------------
bool testL01() {
    constexpr std::string_view testId = "L01";
    constexpr std::string_view desc = "Feature flag OFF (remains Idle, zero actions emitted)";

    Cod29::StateMachine sm; // Default Config has enabled = false
    TEST_ASSERT(!sm.getConfig().enabled, "Config::enabled must default to false");
    TEST_ASSERT(!sm.getConfig().top_edge_drag_enabled, "Config::top_edge_drag_enabled must default to false");
    TEST_ASSERT(sm.getState() == Cod29::State::Idle, "Initial state must be Idle");

    auto a1 = sm.onNativeDragBegin(101, Cod29::DragMode::Move, true, 1, 100);
    TEST_ASSERT(a1.type == Cod29::Action::Type::None, "onNativeDragBegin must return Action::None when disabled");
    TEST_ASSERT(sm.getState() == Cod29::State::Idle, "State must remain Idle when disabled");

    Cod29::OutputRect mon{0.0, 0.0, 1920.0, 1080.0};
    auto a2 = sm.onPointerMotion({500.0, 2.0}, mon, 150);
    TEST_ASSERT(a2.type == Cod29::Action::Type::None, "onPointerMotion must return Action::None when disabled");
    TEST_ASSERT(sm.getState() == Cod29::State::Idle, "State must remain Idle on motion");

    auto a3 = sm.onNativeRelease(200);
    TEST_ASSERT(a3.type == Cod29::Action::Type::None, "onNativeRelease must return Action::None when disabled");
    TEST_ASSERT(sm.getState() == Cod29::State::Idle, "State must remain Idle on release");

    reportTest(testId, desc, true);
    return true;
}

// -----------------------------------------------------------------------------
// L02: Normal move below edge (Dragging state, never arms edge)
// -----------------------------------------------------------------------------
bool testL02() {
    constexpr std::string_view testId = "L02";
    constexpr std::string_view desc = "Normal move below edge (Dragging state, never arms edge)";

    Cod29::Config cfg;
    cfg.enabled = true;
    Cod29::StateMachine sm(cfg);

    auto a1 = sm.onNativeDragBegin(102, Cod29::DragMode::Move, true, 1, 100);
    TEST_ASSERT(a1.type == Cod29::Action::Type::None, "Valid drag begin emits Action::None");
    TEST_ASSERT(sm.getState() == Cod29::State::Dragging, "State must be Dragging");
    TEST_ASSERT(sm.getWindowToken() == 102, "Window token must be stored");
    TEST_ASSERT(sm.getSourceWorkspaceId() == 1, "Source workspace must be stored");

    Cod29::OutputRect mon{0.0, 0.0, 1920.0, 1080.0};
    auto a2 = sm.onPointerMotion({500.0, 200.0}, mon, 120);
    TEST_ASSERT(a2.type == Cod29::Action::Type::None, "Move below edge emits Action::None");
    TEST_ASSERT(sm.getState() == Cod29::State::Dragging, "State remains Dragging");

    auto a3 = sm.onPointerMotion({800.0, 500.0}, mon, 160);
    TEST_ASSERT(a3.type == Cod29::Action::Type::None, "Further move below edge emits Action::None");
    TEST_ASSERT(sm.getState() == Cod29::State::Dragging, "State remains Dragging");

    auto a4 = sm.onNativeRelease(200);
    TEST_ASSERT(a4.type == Cod29::Action::Type::NativeEnd, "Release below edge emits NativeEnd");
    TEST_ASSERT(sm.getState() == Cod29::State::NativeReleaseOnly, "State becomes NativeReleaseOnly");

    reportTest(testId, desc, true);
    return true;
}

// -----------------------------------------------------------------------------
// L03: Pointer at bar boundary (y = 40, 42; verifies 40px bar is ignored)
// -----------------------------------------------------------------------------
bool testL03() {
    constexpr std::string_view testId = "L03";
    constexpr std::string_view desc = "Pointer at bar boundary (y = 40, 42; verifies 40px bar is ignored)";

    Cod29::Config cfg;
    cfg.enabled = true;
    cfg.edgeTolerance = 4.0;
    Cod29::StateMachine sm(cfg);

    Cod29::OutputRect mon{0.0, 0.0, 1920.0, 1080.0};
    sm.onNativeDragBegin(103, Cod29::DragMode::Move, true, 1, 100);
    TEST_ASSERT(sm.getState() == Cod29::State::Dragging, "State is Dragging");

    // Pointer at y = 42.0 (below bar)
    auto a1 = sm.onPointerMotion({500.0, 42.0}, mon, 110);
    TEST_ASSERT(a1.type == Cod29::Action::Type::None, "y = 42.0 must not arm edge");
    TEST_ASSERT(sm.getState() == Cod29::State::Dragging, "State remains Dragging at y = 42.0");

    // Pointer at y = 40.0 (exact Rice bar reserved area boundary)
    auto a2 = sm.onPointerMotion({500.0, 40.0}, mon, 120);
    TEST_ASSERT(a2.type == Cod29::Action::Type::None, "y = 40.0 must not arm edge");
    TEST_ASSERT(sm.getState() == Cod29::State::Dragging, "State remains Dragging at y = 40.0");

    // Pointer at y = 20.0 (inside bar area, but > 4.0 physical top edge)
    auto a3 = sm.onPointerMotion({500.0, 20.0}, mon, 130);
    TEST_ASSERT(a3.type == Cod29::Action::Type::None, "y = 20.0 must not arm edge");
    TEST_ASSERT(sm.getState() == Cod29::State::Dragging, "State remains Dragging at y = 20.0");

    // Pointer at y = 4.0 (exact physical output edge tolerance)
    auto a4 = sm.onPointerMotion({500.0, 4.0}, mon, 140);
    TEST_ASSERT(a4.type == Cod29::Action::Type::ArmEdge, "y = 4.0 reaches physical edge tolerance, emits ArmEdge");
    TEST_ASSERT(sm.getState() == Cod29::State::EdgeArmed, "State becomes EdgeArmed at y = 4.0");

    reportTest(testId, desc, true);
    return true;
}

// -----------------------------------------------------------------------------
// L04: Pointer reaches edge + dwell satisfied (EdgeArmed -> StripOpen, ShowStrip emitted)
// -----------------------------------------------------------------------------
bool testL04() {
    constexpr std::string_view testId = "L04";
    constexpr std::string_view desc = "Pointer reaches edge + dwell satisfied (EdgeArmed -> StripOpen, ShowStrip emitted)";

    Cod29::Config cfg;
    cfg.enabled = true;
    cfg.dwellTimeMs = 80;
    cfg.edgeTolerance = 4.0;
    Cod29::StateMachine sm(cfg);

    Cod29::OutputRect mon{0.0, 0.0, 1920.0, 1080.0};
    sm.onNativeDragBegin(104, Cod29::DragMode::Move, true, 1, 100);

    // Reaches edge at t = 100
    auto a1 = sm.onPointerMotion({500.0, 2.0}, mon, 100);
    TEST_ASSERT(a1.type == Cod29::Action::Type::ArmEdge, "Reaching edge emits ArmEdge");
    TEST_ASSERT(sm.getState() == Cod29::State::EdgeArmed, "State becomes EdgeArmed");
    TEST_ASSERT(sm.getEdgeArmedTimeMs() == 100, "Armed timestamp recorded");

    // Still at edge at t = 150 (50ms < 80ms)
    auto a2 = sm.onPointerMotion({505.0, 1.5}, mon, 150);
    TEST_ASSERT(a2.type == Cod29::Action::Type::None, "Before dwell completes, emits Action::None");
    TEST_ASSERT(sm.getState() == Cod29::State::EdgeArmed, "State remains EdgeArmed during dwell");

    // Dwell satisfied at t = 180 (80ms >= 80ms)
    auto a3 = sm.onPointerMotion({510.0, 2.0}, mon, 180);
    TEST_ASSERT(a3.type == Cod29::Action::Type::ShowStrip, "Dwell satisfied emits ShowStrip");
    TEST_ASSERT(a3.windowToken == 104, "Action includes window token");
    TEST_ASSERT(sm.getState() == Cod29::State::StripOpen, "State becomes StripOpen");

    reportTest(testId, desc, true);
    return true;
}

// -----------------------------------------------------------------------------
// L05: Edge armed then retreat before dwell (disarms cleanly, ShowStrip NOT emitted)
// -----------------------------------------------------------------------------
bool testL05() {
    constexpr std::string_view testId = "L05";
    constexpr std::string_view desc = "Edge armed then retreat before dwell (disarms cleanly, ShowStrip NOT emitted)";

    Cod29::Config cfg;
    cfg.enabled = true;
    cfg.dwellTimeMs = 80;
    cfg.edgeTolerance = 4.0;
    Cod29::StateMachine sm(cfg);

    Cod29::OutputRect mon{0.0, 0.0, 1920.0, 1080.0};
    sm.onNativeDragBegin(105, Cod29::DragMode::Move, true, 1, 100);

    // Reaches edge at t = 100
    auto a1 = sm.onPointerMotion({500.0, 1.0}, mon, 100);
    TEST_ASSERT(a1.type == Cod29::Action::Type::ArmEdge, "Emits ArmEdge");
    TEST_ASSERT(sm.getState() == Cod29::State::EdgeArmed, "State is EdgeArmed");

    // User flicks down away from edge at t = 140 (40ms elapsed < 80ms dwell)
    auto a2 = sm.onPointerMotion({500.0, 50.0}, mon, 140);
    TEST_ASSERT(a2.type == Cod29::Action::Type::DisarmEdge, "Retreating before dwell emits DisarmEdge");
    TEST_ASSERT(sm.getState() == Cod29::State::Dragging, "State disarms back to Dragging");
    TEST_ASSERT(sm.getEdgeArmedTimeMs() == 0, "Armed timestamp cleared");

    // Continue normal dragging
    auto a3 = sm.onPointerMotion({500.0, 250.0}, mon, 200);
    TEST_ASSERT(a3.type == Cod29::Action::Type::None, "Motion in Dragging emits None");
    TEST_ASSERT(sm.getState() == Cod29::State::Dragging, "State remains Dragging");

    reportTest(testId, desc, true);
    return true;
}

// -----------------------------------------------------------------------------
// L06: Exit via hysteresis and re-entry (HideStrip on y > stripHeight + hysteresis, re-entry re-arms cleanly)
// -----------------------------------------------------------------------------
bool testL06() {
    constexpr std::string_view testId = "L06";
    constexpr std::string_view desc = "Exit via hysteresis and re-entry (HideStrip on y > stripHeight + hysteresis, re-entry re-arms cleanly)";

    Cod29::Config cfg;
    cfg.enabled = true;
    cfg.dwellTimeMs = 80;
    cfg.stripHeight = 140.0;
    cfg.exitHysteresis = 28.0;
    Cod29::StateMachine sm(cfg);

    Cod29::OutputRect mon{0.0, 0.0, 1920.0, 1080.0, 40.0};
    sm.onNativeDragBegin(106, Cod29::DragMode::Move, true, 1, 100);

    // Arm and open strip
    sm.onPointerMotion({500.0, 2.0}, mon, 100);
    auto aOpen = sm.onPointerMotion({500.0, 2.0}, mon, 180);
    TEST_ASSERT(aOpen.type == Cod29::Action::Type::ShowStrip, "ShowStrip emitted");
    TEST_ASSERT(sm.getState() == Cod29::State::StripOpen, "State is StripOpen");

    // At y = 175, the pointer is inside the strip only because of the 40 px top inset.
    auto a1 = sm.onPointerMotion({500.0, 175.0}, mon, 200);
    TEST_ASSERT(a1.type == Cod29::Action::Type::None, "Motion within strip emits None");
    TEST_ASSERT(sm.getState() == Cod29::State::StripOpen, "State remains StripOpen");

    // Move below strip height but within hysteresis zone:
    // Exit threshold is 40 + 140 + 28 = 208.
    auto a2 = sm.onPointerMotion({500.0, 200.0}, mon, 220);
    TEST_ASSERT(a2.type == Cod29::Action::Type::None, "Motion within hysteresis buffer emits None");
    TEST_ASSERT(sm.getState() == Cod29::State::StripOpen, "State remains StripOpen in hysteresis buffer");

    // Retreat past the hysteresis exit threshold.
    auto a3 = sm.onPointerMotion({500.0, 209.0}, mon, 240);
    TEST_ASSERT(a3.type == Cod29::Action::Type::HideStrip, "Retreat past hysteresis emits HideStrip");
    TEST_ASSERT(sm.getState() == Cod29::State::Dragging, "State returns to Dragging");

    // Move back up to top edge: re-entry re-arms cleanly
    auto a4 = sm.onPointerMotion({500.0, 2.0}, mon, 300);
    TEST_ASSERT(a4.type == Cod29::Action::Type::ArmEdge, "Re-entry at top edge emits ArmEdge");
    TEST_ASSERT(sm.getState() == Cod29::State::EdgeArmed, "State re-arms to EdgeArmed cleanly");

    reportTest(testId, desc, true);
    return true;
}

// -----------------------------------------------------------------------------
// L07: Native resize or threshold unreached (ignored, remains Idle)
// -----------------------------------------------------------------------------
bool testL07() {
    constexpr std::string_view testId = "L07";
    constexpr std::string_view desc = "Native resize or threshold unreached (ignored, remains Idle)";

    Cod29::Config cfg;
    cfg.enabled = true;

    // Subtest 1: Mode is Resize (Super + mouse:273)
    {
        Cod29::StateMachine sm(cfg);
        auto act = sm.onNativeDragBegin(1071, Cod29::DragMode::Resize, true, 1, 100);
        TEST_ASSERT(act.type == Cod29::Action::Type::None, "Resize mode drag emits None");
        TEST_ASSERT(sm.getState() == Cod29::State::Idle, "State must remain Idle on Resize");
    }

    // Subtest 2: Drag threshold not reached (jitter click)
    {
        Cod29::StateMachine sm(cfg);
        auto act = sm.onNativeDragBegin(1072, Cod29::DragMode::Move, false, 1, 100);
        TEST_ASSERT(act.type == Cod29::Action::Type::None, "Threshold not reached emits None");
        TEST_ASSERT(sm.getState() == Cod29::State::Idle, "State must remain Idle when threshold not reached");
    }

    // Subtest 3: Mode is Other
    {
        Cod29::StateMachine sm(cfg);
        auto act = sm.onNativeDragBegin(1073, Cod29::DragMode::Other, true, 1, 100);
        TEST_ASSERT(act.type == Cod29::Action::Type::None, "Other mode emits None");
        TEST_ASSERT(sm.getState() == Cod29::State::Idle, "State must remain Idle on Other mode");
    }

    // Subtest 4: Invalid window token 0
    {
        Cod29::StateMachine sm(cfg);
        auto act = sm.onNativeDragBegin(0, Cod29::DragMode::Move, true, 1, 100);
        TEST_ASSERT(act.type == Cod29::Action::Type::None, "Token 0 emits None");
        TEST_ASSERT(sm.getState() == Cod29::State::Idle, "State must remain Idle on token 0");
    }

    reportTest(testId, desc, true);
    return true;
}

// -----------------------------------------------------------------------------
// L08: Hover over valid target card (HoverTarget, TargetChanged emitted)
// -----------------------------------------------------------------------------
bool testL08() {
    constexpr std::string_view testId = "L08";
    constexpr std::string_view desc = "Hover over valid target card (HoverTarget, TargetChanged emitted)";

    Cod29::Config cfg;
    cfg.enabled = true;
    Cod29::StateMachine sm(cfg);

    Cod29::OutputRect mon{0.0, 0.0, 1920.0, 1080.0};
    sm.onNativeDragBegin(108, Cod29::DragMode::Move, true, 1, 100);
    sm.onPointerMotion({500.0, 2.0}, mon, 100);
    sm.onPointerMotion({500.0, 2.0}, mon, 180);
    TEST_ASSERT(sm.getState() == Cod29::State::StripOpen, "Strip must be open");

    // Hover over Card for Workspace 2
    auto a1 = sm.onWorkspaceCardHover(2);
    TEST_ASSERT(a1.type == Cod29::Action::Type::TargetChanged, "Hovering card emits TargetChanged");
    TEST_ASSERT(a1.targetWorkspaceId == 2, "Target workspace is 2");
    TEST_ASSERT(sm.getState() == Cod29::State::HoverTarget, "State is HoverTarget");
    TEST_ASSERT(sm.getTargetWorkspaceId() == 2, "Stored target workspace is 2");

    // Switch hover directly to Workspace 3
    auto a2 = sm.onWorkspaceCardHover(3);
    TEST_ASSERT(a2.type == Cod29::Action::Type::TargetChanged, "Switching card emits TargetChanged");
    TEST_ASSERT(a2.targetWorkspaceId == 3, "Target workspace is 3");
    TEST_ASSERT(sm.getState() == Cod29::State::HoverTarget, "State remains HoverTarget");
    TEST_ASSERT(sm.getTargetWorkspaceId() == 3, "Stored target workspace is 3");

    // Re-hovering same card is idempotent
    auto a2_dup = sm.onWorkspaceCardHover(3);
    TEST_ASSERT(a2_dup.type == Cod29::Action::Type::None, "Duplicate hover emits None");

    // Leave card into whitespace of strip
    auto a3 = sm.onWorkspaceCardLeave();
    TEST_ASSERT(a3.type == Cod29::Action::Type::TargetChanged, "Leaving card emits TargetChanged with -1");
    TEST_ASSERT(a3.targetWorkspaceId == -1, "Target workspace cleared to -1");
    TEST_ASSERT(sm.getState() == Cod29::State::StripOpen, "State returns to StripOpen");
    TEST_ASSERT(sm.getTargetWorkspaceId() == -1, "Stored target workspace is -1");

    reportTest(testId, desc, true);
    return true;
}

// -----------------------------------------------------------------------------
// L09: Release over different workspace (DropIntent committed with target workspace)
// -----------------------------------------------------------------------------
bool testL09() {
    constexpr std::string_view testId = "L09";
    constexpr std::string_view desc = "Release over different workspace (DropIntent committed with target workspace)";

    Cod29::Config cfg;
    cfg.enabled = true;
    Cod29::StateMachine sm(cfg);

    Cod29::OutputRect mon{0.0, 0.0, 1920.0, 1080.0};
    sm.onNativeDragBegin(109, Cod29::DragMode::Move, true, 1 /* sourceWs */, 100);
    sm.onPointerMotion({500.0, 2.0}, mon, 100);
    sm.onPointerMotion({500.0, 2.0}, mon, 180);
    sm.onWorkspaceCardHover(2 /* targetWs != sourceWs */);
    TEST_ASSERT(sm.getState() == Cod29::State::HoverTarget, "State is HoverTarget");

    // Native mouse release while hovering Workspace 2
    auto aRel = sm.onNativeRelease(250);
    TEST_ASSERT(aRel.type == Cod29::Action::Type::PrepareDrop, "Release on different workspace commits PrepareDrop");
    TEST_ASSERT(aRel.targetWorkspaceId == 2, "Action carries target workspace 2");
    TEST_ASSERT(aRel.windowToken == 109, "Action carries dragged window token 109");
    TEST_ASSERT(sm.getState() == Cod29::State::DropIntent, "State transitions to DropIntent");

    // Ephemeral cleanup
    sm.onCleanup();
    TEST_ASSERT(sm.getState() == Cod29::State::Idle, "Cleanup returns state to Idle");
    TEST_ASSERT(sm.getWindowToken() == 0, "Window token cleared on cleanup");

    reportTest(testId, desc, true);
    return true;
}

// -----------------------------------------------------------------------------
// L10: Release over same workspace (NativeReleaseOnly, strict NO-OP)
// -----------------------------------------------------------------------------
bool testL10() {
    constexpr std::string_view testId = "L10";
    constexpr std::string_view desc = "Release over same workspace (NativeReleaseOnly, strict NO-OP)";

    Cod29::Config cfg;
    cfg.enabled = true;
    Cod29::StateMachine sm(cfg);

    Cod29::OutputRect mon{0.0, 0.0, 1920.0, 1080.0};
    sm.onNativeDragBegin(110, Cod29::DragMode::Move, true, 1 /* sourceWs = 1 */, 100);
    sm.onPointerMotion({500.0, 2.0}, mon, 100);
    sm.onPointerMotion({500.0, 2.0}, mon, 180);
    sm.onWorkspaceCardHover(1 /* targetWs == sourceWs = 1 */);
    TEST_ASSERT(sm.getState() == Cod29::State::HoverTarget, "State is HoverTarget");

    // Release over same workspace
    auto aRel = sm.onNativeRelease(250);
    TEST_ASSERT(aRel.type == Cod29::Action::Type::NativeEnd, "Same workspace drop produces strict NO-OP NativeEnd");
    TEST_ASSERT(aRel.type != Cod29::Action::Type::PrepareDrop, "MUST NOT emit PrepareDrop for same workspace");
    TEST_ASSERT(sm.getState() == Cod29::State::NativeReleaseOnly, "State transitions to NativeReleaseOnly");

    sm.onCleanup();
    TEST_ASSERT(sm.getState() == Cod29::State::Idle, "State becomes Idle after cleanup");

    reportTest(testId, desc, true);
    return true;
}

// -----------------------------------------------------------------------------
// L11: Release outside cards (NativeReleaseOnly, no move)
// -----------------------------------------------------------------------------
bool testL11() {
    constexpr std::string_view testId = "L11";
    constexpr std::string_view desc = "Release outside cards (NativeReleaseOnly, no move)";

    Cod29::Config cfg;
    cfg.enabled = true;
    Cod29::StateMachine sm(cfg);

    Cod29::OutputRect mon{0.0, 0.0, 1920.0, 1080.0};
    sm.onNativeDragBegin(111, Cod29::DragMode::Move, true, 1, 100);
    sm.onPointerMotion({500.0, 2.0}, mon, 100);
    sm.onPointerMotion({500.0, 2.0}, mon, 180);
    TEST_ASSERT(sm.getState() == Cod29::State::StripOpen, "State is StripOpen without card hover");

    // Release in whitespace of strip outside any card
    auto aRel = sm.onNativeRelease(250);
    TEST_ASSERT(aRel.type == Cod29::Action::Type::NativeEnd, "Release outside cards emits NativeEnd");
    TEST_ASSERT(sm.getState() == Cod29::State::NativeReleaseOnly, "State becomes NativeReleaseOnly");

    sm.onCleanup();
    TEST_ASSERT(sm.getState() == Cod29::State::Idle, "Cleanup returns to Idle");

    reportTest(testId, desc, true);
    return true;
}

// -----------------------------------------------------------------------------
// L12: Cancel events (SessionLock / WindowUnmap / hotplug -> clean reset to Idle)
// -----------------------------------------------------------------------------
bool testL12() {
    constexpr std::string_view testId = "L12";
    constexpr std::string_view desc = "Cancel events (SessionLock / WindowUnmap / hotplug -> clean reset to Idle)";

    Cod29::Config cfg;
    cfg.enabled = true;

    Cod29::OutputRect mon{0.0, 0.0, 1920.0, 1080.0};

    // Subtest 12a: Cancel on SessionLock during Dragging
    {
        Cod29::StateMachine sm(cfg);
        sm.onNativeDragBegin(1121, Cod29::DragMode::Move, true, 1, 100);
        auto c = sm.onCancel(Cod29::CancelReason::SessionLock);
        TEST_ASSERT(c.type == Cod29::Action::Type::Reset, "SessionLock cancel emits Reset");
        TEST_ASSERT(sm.getState() == Cod29::State::Idle, "State resets to Idle");
    }

    // Subtest 12b: Cancel on WindowUnmapped during EdgeArmed
    {
        Cod29::StateMachine sm(cfg);
        sm.onNativeDragBegin(1122, Cod29::DragMode::Move, true, 1, 100);
        sm.onPointerMotion({500.0, 2.0}, mon, 100);
        auto c = sm.onCancel(Cod29::CancelReason::WindowUnmapped);
        TEST_ASSERT(c.type == Cod29::Action::Type::Reset, "WindowUnmapped cancel emits Reset");
        TEST_ASSERT(sm.getState() == Cod29::State::Idle, "State resets to Idle");
    }

    // Subtest 12c: Cancel on MonitorRemoved during StripOpen
    {
        Cod29::StateMachine sm(cfg);
        sm.onNativeDragBegin(1123, Cod29::DragMode::Move, true, 1, 100);
        sm.onPointerMotion({500.0, 2.0}, mon, 100);
        sm.onPointerMotion({500.0, 2.0}, mon, 180);
        auto c = sm.onCancel(Cod29::CancelReason::MonitorRemoved);
        TEST_ASSERT(c.type == Cod29::Action::Type::Reset, "MonitorRemoved cancel emits Reset");
        TEST_ASSERT(sm.getState() == Cod29::State::Idle, "State resets to Idle");
    }

    // Subtest 12d: Cancel on DragSuperseded during HoverTarget
    {
        Cod29::StateMachine sm(cfg);
        sm.onNativeDragBegin(1124, Cod29::DragMode::Move, true, 1, 100);
        sm.onPointerMotion({500.0, 2.0}, mon, 100);
        sm.onPointerMotion({500.0, 2.0}, mon, 180);
        sm.onWorkspaceCardHover(2);
        auto c = sm.onCancel(Cod29::CancelReason::DragSuperseded);
        TEST_ASSERT(c.type == Cod29::Action::Type::Reset, "DragSuperseded cancel emits Reset");
        TEST_ASSERT(sm.getState() == Cod29::State::Idle, "State resets to Idle");
    }

    // Subtest 12e: Cancel when already Idle is a safe no-op
    {
        Cod29::StateMachine sm(cfg);
        auto c = sm.onCancel(Cod29::CancelReason::Unknown);
        TEST_ASSERT(c.type == Cod29::Action::Type::None, "Cancel while Idle emits None");
        TEST_ASSERT(sm.getState() == Cod29::State::Idle, "State stays Idle");
    }

    reportTest(testId, desc, true);
    return true;
}

// -----------------------------------------------------------------------------
// L13: Logical output offset / negative origin (detects top edge at monitor.y)
// -----------------------------------------------------------------------------
bool testL13() {
    constexpr std::string_view testId = "L13";
    constexpr std::string_view desc = "Logical output offset / negative origin (detects top edge at monitor.y)";

    Cod29::Config cfg;
    cfg.enabled = true;
    cfg.edgeTolerance = 4.0;
    cfg.dwellTimeMs = 80;
    Cod29::StateMachine sm(cfg);

    // Negative origin monitor: x in [-1920, 0], y in [-1080, 0]
    Cod29::OutputRect monOffset{-1920.0, -1080.0, 1920.0, 1080.0};
    sm.onNativeDragBegin(113, Cod29::DragMode::Move, true, 1, 100);

    // Pointer at (-960.0, 0.0) -> this is y = 0, which is the bottom/middle of this monitor, not top!
    auto a0 = sm.onPointerMotion({-960.0, 0.0}, monOffset, 110);
    TEST_ASSERT(a0.type == Cod29::Action::Type::None, "y = 0.0 is not top edge of negative origin monitor");
    TEST_ASSERT(sm.getState() == Cod29::State::Dragging, "State remains Dragging");

    // Pointer at (-960.0, -1070.0) -> 10px below top edge (outside 4px tolerance)
    auto a1 = sm.onPointerMotion({-960.0, -1070.0}, monOffset, 120);
    TEST_ASSERT(a1.type == Cod29::Action::Type::None, "y = -1070.0 is outside edge tolerance");
    TEST_ASSERT(sm.getState() == Cod29::State::Dragging, "State remains Dragging");

    // Pointer at (-960.0, -1078.0) -> exactly 2px below top edge (mon.y = -1080.0)
    auto a2 = sm.onPointerMotion({-960.0, -1078.0}, monOffset, 130);
    TEST_ASSERT(a2.type == Cod29::Action::Type::ArmEdge, "Top edge detected at mon.y (-1080.0 + 2.0)");
    TEST_ASSERT(sm.getState() == Cod29::State::EdgeArmed, "State becomes EdgeArmed");

    // Dwell satisfied on negative origin monitor
    auto a3 = sm.onPointerMotion({-960.0, -1078.0}, monOffset, 210);
    TEST_ASSERT(a3.type == Cod29::Action::Type::ShowStrip, "Dwell satisfied on negative origin monitor");
    TEST_ASSERT(sm.getState() == Cod29::State::StripOpen, "State becomes StripOpen");

    reportTest(testId, desc, true);
    return true;
}

// -----------------------------------------------------------------------------
// L14: Multi-monitor coordinate containment (arms correct monitor without coordinate bleed)
// -----------------------------------------------------------------------------
bool testL14() {
    constexpr std::string_view testId = "L14";
    constexpr std::string_view desc = "Multi-monitor coordinate containment (arms correct monitor without coordinate bleed)";

    Cod29::Config cfg;
    cfg.enabled = true;
    cfg.edgeTolerance = 4.0;
    Cod29::StateMachine sm(cfg);

    Cod29::OutputRect monLeft{0.0, 0.0, 1920.0, 1080.0};
    Cod29::OutputRect monRight{1920.0, 0.0, 2560.0, 1440.0};

    sm.onNativeDragBegin(114, Cod29::DragMode::Move, true, 1, 100);

    // Pointer is on the top edge of the right monitor: x = 2500.0, y = 2.0
    // Test against left monitor: x is outside [0, 1920] -> must NOT arm
    auto aLeft = sm.onPointerMotion({2500.0, 2.0}, monLeft, 110);
    TEST_ASSERT(aLeft.type == Cod29::Action::Type::None, "Cursor on right monitor must not arm left monitor");
    TEST_ASSERT(sm.getState() == Cod29::State::Dragging, "Left monitor rejects cursor outside bounds");

    // Test against right monitor: x is in [1920, 4480], y is in [0, 4] -> must arm!
    auto aRight = sm.onPointerMotion({2500.0, 2.0}, monRight, 115);
    TEST_ASSERT(aRight.type == Cod29::Action::Type::ArmEdge, "Right monitor correctly arms");
    TEST_ASSERT(sm.getState() == Cod29::State::EdgeArmed, "State becomes EdgeArmed for right monitor");

    // Disarm on right monitor
    sm.onPointerMotion({2500.0, 50.0}, monRight, 130);
    TEST_ASSERT(sm.getState() == Cod29::State::Dragging, "State disarmed to Dragging");

    // Pointer moves to left monitor top edge: x = 500.0, y = 2.0
    // Test against right monitor: x < 1920 -> must NOT arm
    auto aRight2 = sm.onPointerMotion({500.0, 2.0}, monRight, 140);
    TEST_ASSERT(aRight2.type == Cod29::Action::Type::None, "Cursor on left monitor must not arm right monitor");
    TEST_ASSERT(sm.getState() == Cod29::State::Dragging, "Right monitor rejects cursor outside bounds");

    // Test against left monitor: x in [0, 1920], y in [0, 4] -> must arm!
    auto aLeft2 = sm.onPointerMotion({500.0, 2.0}, monLeft, 145);
    TEST_ASSERT(aLeft2.type == Cod29::Action::Type::ArmEdge, "Left monitor correctly arms");
    TEST_ASSERT(sm.getState() == Cod29::State::EdgeArmed, "State becomes EdgeArmed for left monitor");

    reportTest(testId, desc, true);
    return true;
}

// -----------------------------------------------------------------------------
// L15: Release during dwell or post-cleanup (clean single commit, no duplicate release)
// -----------------------------------------------------------------------------
bool testL15() {
    constexpr std::string_view testId = "L15";
    constexpr std::string_view desc = "Release during dwell or post-cleanup (clean single commit, no duplicate release)";

    Cod29::Config cfg;
    cfg.enabled = true;
    cfg.dwellTimeMs = 80;

    Cod29::OutputRect mon{0.0, 0.0, 1920.0, 1080.0};

    // Subtest 15a: Release during dwell (EdgeArmed)
    {
        Cod29::StateMachine sm(cfg);
        sm.onNativeDragBegin(1151, Cod29::DragMode::Move, true, 1, 100);
        sm.onPointerMotion({500.0, 2.0}, mon, 100);
        TEST_ASSERT(sm.getState() == Cod29::State::EdgeArmed, "State is EdgeArmed");

        // Release at t = 140 (40ms elapsed < 80ms dwell)
        auto relDwell = sm.onNativeRelease(140);
        TEST_ASSERT(relDwell.type == Cod29::Action::Type::NativeEnd, "Release during dwell emits NativeEnd");
        TEST_ASSERT(sm.getState() == Cod29::State::NativeReleaseOnly, "State transitions to NativeReleaseOnly");

        // Subsequent release before cleanup emits None (no duplicate release)
        auto relDup = sm.onNativeRelease(150);
        TEST_ASSERT(relDup.type == Cod29::Action::Type::None, "Duplicate release emits Action::None");

        // Cleanup
        sm.onCleanup();
        TEST_ASSERT(sm.getState() == Cod29::State::Idle, "Cleanup returns to Idle");

        // Release after cleanup emits None
        auto relPostCleanup = sm.onNativeRelease(160);
        TEST_ASSERT(relPostCleanup.type == Cod29::Action::Type::None, "Release after cleanup emits Action::None");
    }

    // Subtest 15b: Double release after PrepareDrop commit
    {
        Cod29::StateMachine sm(cfg);
        sm.onNativeDragBegin(1152, Cod29::DragMode::Move, true, 1, 100);
        sm.onPointerMotion({500.0, 2.0}, mon, 100);
        sm.onPointerMotion({500.0, 2.0}, mon, 180);
        sm.onWorkspaceCardHover(2);
        TEST_ASSERT(sm.getState() == Cod29::State::HoverTarget, "State is HoverTarget");

        // First release commits PrepareDrop
        auto rel1 = sm.onNativeRelease(250);
        TEST_ASSERT(rel1.type == Cod29::Action::Type::PrepareDrop, "First release commits PrepareDrop");
        TEST_ASSERT(sm.getState() == Cod29::State::DropIntent, "State is DropIntent");

        // Accidental duplicate release invocation
        auto rel2 = sm.onNativeRelease(260);
        TEST_ASSERT(rel2.type == Cod29::Action::Type::None, "Duplicate release invocation emits None");
        TEST_ASSERT(sm.getState() == Cod29::State::DropIntent, "State remains DropIntent without double commit");

        sm.onCleanup();
        TEST_ASSERT(sm.getState() == Cod29::State::Idle, "Cleanup returns to Idle");
    }

    reportTest(testId, desc, true);
    return true;
}

} // namespace

int main() {
    std::cout << "====================================================================\n";
    std::cout << " COD-29 Phase C: Pure C++ State Machine Deterministic Unit Tests\n";
    std::cout << "====================================================================\n\n";

    testL01();
    testL02();
    testL03();
    testL04();
    testL05();
    testL06();
    testL07();
    testL08();
    testL09();
    testL10();
    testL11();
    testL12();
    testL13();
    testL14();
    testL15();

    std::cout << "\n--------------------------------------------------------------------\n";
    std::cout << " Test Summary: "
              << g_passCount << " / " << (g_passCount + g_failCount) << " passed ("
              << g_failCount << " failed)\n";
    std::cout << "--------------------------------------------------------------------\n";

    if (g_failCount == 0 && g_passCount == 15) {
        std::cout << " [\033[32mSUCCESS\033[0m] ALL 15 UNIT TESTS (L01-L15) PASSED DETERMINISTICALLY.\n";
        return 0;
    }

    std::cout << " [\033[31mFAILURE\033[0m] " << g_failCount << " test(s) failed.\n";
    return 1;
}
