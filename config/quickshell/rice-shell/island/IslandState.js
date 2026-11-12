// State Machine & Alert Priority Management for Dynamic Island

var State = {
    IDLE: "idle",
    MEDIA: "media",
    OSD: "volume",
    NOTIFICATION: "notification",
    EXPANDED: "expanded"
};

var Priority = {
    idle: 0,
    media: 20,
    volume: 40,
    notification: 60,
    expanded: 50
};

var activeAlert = null;
var alertTimer = null;

function resolveState(currentAlert, hasMedia, isHovered, isPinned) {
    if (isPinned) return State.EXPANDED;
    if (currentAlert) return currentAlert.type;
    if (isHovered && hasMedia) return State.EXPANDED;
    if (hasMedia) return State.MEDIA;
    return State.IDLE;
}

function targetDimensions(state, details) {
    switch (state) {
        case State.IDLE:
            return { width: 0, height: 0, radius: 0 };
        case State.MEDIA:
            return { width: 240, height: 32, radius: 16 };
        case State.OSD:
            return { width: 260, height: 42, radius: 21 };
        case State.NOTIFICATION:
            return { width: 320, height: 56, radius: 18 };
        case State.EXPANDED:
            return { width: 360, height: 110, radius: 20 };
        default:
            return { width: 0, height: 0, radius: 0 };
    }
}
