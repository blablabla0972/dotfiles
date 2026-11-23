pragma ComponentBehavior: Bound

import QtQuick

QtObject {
    required property IslandShape shape
    required property bool active
    required property real contentWidth
    required property real contentHeight
    property real revealStart: 0.60
    property real presence: active ? 1 : 0
    Behavior on presence {
        id: fade
        NumberAnimation {
            duration: fade.targetValue === 1 ? 200 : 130
            easing.type: fade.targetValue === 1 ? Easing.InOutCubic : Easing.OutCubic
        }
    }
    readonly property real opacity: {
        // Unseen slots do not track per-frame geometry.
        if (presence <= 0) return 0;
        const fit = Math.min(shape.pillWidth / Math.max(1, contentWidth),
                             shape.pillHeight / Math.max(1, contentHeight));
        const t = Math.max(0, Math.min(1, (fit - revealStart) / (0.98 - revealStart)));
        return presence * t * t * (3 - 2 * t);
    }
    readonly property real scale: 0.96 + 0.04 * opacity
}
