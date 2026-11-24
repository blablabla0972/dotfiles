pragma ComponentBehavior: Bound

import QtQuick

QtObject {
    id: motion
    required property IslandShape shape
    required property bool active
    required property real contentWidth
    required property real contentHeight
    property real revealStart: 0.40
    property int enterDuration: 220
    property int exitDuration: 115
    property real presence: active ? 1 : 0
    Behavior on presence {
        id: fade
        NumberAnimation {
            duration: fade.targetValue === 1 ? motion.enterDuration : motion.exitDuration
            easing.type: Easing.OutCubic
        }
    }
    readonly property real opacity: {
        // Unseen slots do not track per-frame geometry.
        if (presence <= 0) return 0;
        const widthRatio = shape.pillWidth / Math.max(1, contentWidth);
        const heightRatio = shape.pillHeight / Math.max(1, contentHeight);
        // On collapse, hold the smaller label back until the surface is near its size.
        const fit = Math.min(widthRatio, heightRatio, 1.7 / widthRatio, 3 / heightRatio);
        const t = Math.max(0, Math.min(1, (fit - revealStart) / (0.98 - revealStart)));
        return presence * t * t * (3 - 2 * t);
    }
    readonly property real scale: 1 - Math.min(0.025, 6 / Math.max(1, contentWidth)) * (1 - opacity)
    readonly property real offsetY: -Math.min(8, contentHeight * 0.10) * (1 - opacity)
}
