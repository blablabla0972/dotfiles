// State Machine & Alert Priority Management for Dynamic Island

var State = {
    IDLE: "idle",
    MEDIA: "media",
    OSD: "volume",
    NOTIFICATION: "notification",
    EXPANDED: "expanded",
    DASHBOARD: "dashboard"
};

function resolveState(currentAlert, hasMedia, isHovered, isPinned, dashboardOpen) {
    if (dashboardOpen) return State.DASHBOARD;
    if (isPinned) return State.EXPANDED;
    if (currentAlert) return currentAlert.type;
    if (hasMedia) return isHovered ? State.EXPANDED : State.MEDIA;
    return State.IDLE;
}

function targetDimensions(state, details) {
    switch (state) {
        case State.IDLE:
            return { width: 138, height: 32, radius: 12 };
        case State.MEDIA:
            return { width: 232, height: 32, radius: 12 };
        case State.OSD:
            return { width: 264, height: 38, radius: 15 };
        case State.NOTIFICATION:
            return { width: 390, height: 88, radius: 20 };
        case State.DASHBOARD:
            return { width: 760, height: 440, radius: 22 };
        case State.EXPANDED:
            return { width: 376, height: 156, radius: 24 };
        default:
            return { width: 138, height: 32, radius: 12 };
    }
}
