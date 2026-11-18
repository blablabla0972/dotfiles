// State Machine & Alert Priority Management for Dynamic Island

var State = {
    IDLE: "idle",
    MEDIA: "media",
    OSD: "volume",
    NOTIFICATION: "notification",
    EXPANDED: "expanded",
    DASHBOARD: "dashboard"
};

var Dashboard = {
    width: 900,
    height: 520,
    radius: 24,
    drawerWidth: 360
};

function normalizeDashboardTab(tab) {
    return tab === "Power" || tab === "System" || tab === "Notifications" || tab === "Config" ? tab : "Home";
}

function normalizeSideDrawer(type) {
    if (typeof type !== "string") return "";
    var drawer = type.trim().toLowerCase();
    return drawer === "wifi" || drawer === "bluetooth" || drawer === "hotspot" ? drawer : "";
}

function resolveState(currentAlert, hasMedia, isHovered, isPinned, dashboardOpen) {
    if (dashboardOpen) return State.DASHBOARD;
    if (isPinned) return State.EXPANDED;
    if (currentAlert) return currentAlert.type;
    if (hasMedia) return isHovered ? State.EXPANDED : State.MEDIA;
    return State.IDLE;
}

function dashboardGeometry(screenWidth, screenHeight, antiCornerRadius) {
    // QsScreen dimensions are already in logical pixels.
    var width = typeof screenWidth === "number" && isFinite(screenWidth) && screenWidth > 0
        ? screenWidth : 1920;
    var height = typeof screenHeight === "number" && isFinite(screenHeight) && screenHeight > 0
        ? screenHeight : 1080;
    var anti = typeof antiCornerRadius === "number" && isFinite(antiCornerRadius)
        ? Math.max(0, antiCornerRadius) : 7;
    var margin = 12;
    var cardWidth = Math.min(Dashboard.width, Math.max(1, width - 2 * margin - 2 * anti));
    var cardHeight = Math.min(Dashboard.height, Math.max(1, height - 16));
    var drawerWidth = Math.min(Dashboard.drawerWidth, cardWidth);
    var sideBySide = width >= cardWidth + drawerWidth + 12 + 2 * margin + 2 * anti;
    return {
        width: cardWidth,
        height: cardHeight,
        radius: Dashboard.radius,
        sideBySide: sideBySide,
        drawerOverlay: !sideBySide,
        drawerWidth: drawerWidth,
        margin: margin
    };
}

function targetDimensions(state, details) {
    switch (state) {
        case State.IDLE:
            return { width: 138, height: 32, radius: 16 };
        case State.MEDIA:
            return { width: 232, height: 32, radius: 16 };
        case State.OSD:
            return { width: 244, height: 48, radius: 24 };
        case State.NOTIFICATION:
            return {
                width: 390,
                height: details && details.actions && details.actions.length > 0 ? 120 : 88,
                radius: 20
            };
        case State.DASHBOARD:
            return { width: Dashboard.width, height: Dashboard.height, radius: Dashboard.radius };
        case State.EXPANDED:
            return { width: 420, height: 160, radius: 26 };
        default:
            return { width: 138, height: 32, radius: 16 };
    }
}

function normalizeOsdProgress(progress, kind) {
    if (typeof progress !== "number" || !isFinite(progress)) return 0;
    var limit = kind === "volume" ? 1.5 : 1;
    return Math.max(0, Math.min(limit, progress));
}

function osdFill(progress) {
    if (typeof progress !== "number" || !isFinite(progress)) return 0;
    return Math.max(0, Math.min(1, progress));
}
