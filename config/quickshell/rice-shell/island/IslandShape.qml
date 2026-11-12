pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

Item {
    id: root

    property real pillWidth: 140
    property real pillHeight: 28
    property real antiCornerRadius: 12
    property real bottomRadius: 14
    property color fillColor: "#1a1b21"
    property color borderColor: "#43474e"
    property bool showAntiCorners: true

    property int animDurationWidth: 240
    property int animDurationHeight: 220
    property real overshoot: 0.25
    property int easingTypeWidth: overshoot > 0 ? Easing.OutBack : Easing.OutCubic
    property int easingTypeHeight: Easing.OutCubic

    // Budgeted radii to prevent self-intersecting arcs
    readonly property real r: Math.max(0, Math.min(root.bottomRadius, root.pillHeight / 2, root.pillWidth / 2))
    readonly property real a: root.showAntiCorners ? Math.max(0, Math.min(root.antiCornerRadius, root.pillHeight - r)) : 0
    readonly property real w: root.pillWidth
    readonly property real h: root.pillHeight

    width: pillWidth + (showAntiCorners ? a * 2 : 0)
    height: pillHeight

    // Smooth geometry morphing transitions
    Behavior on pillWidth {
        NumberAnimation {
            duration: root.animDurationWidth
            easing.type: root.easingTypeWidth
            easing.overshoot: root.overshoot
        }
    }
    Behavior on pillHeight {
        NumberAnimation {
            duration: root.animDurationHeight
            easing.type: root.easingTypeHeight
        }
    }

    // Unified Surface Mesh: zero internal seams, zero vertical border lines
    Shape {
        id: surfaceShape
        anchors.fill: parent
        antialiasing: true
        preferredRendererType: Shape.CurveRenderer

        // 1. Fill Path (Closed)
        ShapePath {
            fillColor: root.fillColor
            strokeColor: "transparent"
            strokeWidth: 0
            startX: 0
            startY: 0

            // Left Anti-Corner (Concave)
            PathCubic {
                x: root.a
                y: root.a
                control1X: root.a * 0.45
                control1Y: 0
                control2X: root.a
                control2Y: root.a * 0.55
            }

            // Left vertical side
            PathLine { x: root.a; y: root.h - root.r }

            // Bottom-Left rounded corner
            PathArc {
                x: root.a + root.r
                y: root.h
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Counterclockwise
            }

            // Bottom horizontal edge
            PathLine { x: root.a + root.w - root.r; y: root.h }

            // Bottom-Right rounded corner
            PathArc {
                x: root.a + root.w
                y: root.h - root.r
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Counterclockwise
            }

            // Right vertical side
            PathLine { x: root.a + root.w; y: root.a }

            // Right Anti-Corner (Concave)
            PathCubic {
                x: root.a * 2 + root.w
                y: 0
                control1X: root.a + root.w
                control1Y: root.a * 0.55
                control2X: root.a * 1.55 + root.w
                control2Y: 0
            }

            // Close across the top edge
            PathLine { x: 0; y: 0 }
        }

        // 2. Continuous Outer Perimeter Stroke (Open path - NO stroke along the screen bezel!)
        ShapePath {
            fillColor: "transparent"
            strokeColor: Qt.rgba(root.borderColor.r, root.borderColor.g, root.borderColor.b, 0.4)
            strokeWidth: 1
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            startX: 0
            startY: 0

            // Left Anti-Corner
            PathCubic {
                x: root.a
                y: root.a
                control1X: root.a * 0.45
                control1Y: 0
                control2X: root.a
                control2Y: root.a * 0.55
            }

            // Left vertical side
            PathLine { x: root.a; y: root.h - root.r }

            // Bottom-Left corner
            PathArc {
                x: root.a + root.r
                y: root.h
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Counterclockwise
            }

            // Bottom edge
            PathLine { x: root.a + root.w - root.r; y: root.h }

            // Bottom-Right corner
            PathArc {
                x: root.a + root.w
                y: root.h - root.r
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Counterclockwise
            }

            // Right vertical side
            PathLine { x: root.a + root.w; y: root.a }

            // Right Anti-Corner
            PathCubic {
                x: root.a * 2 + root.w
                y: 0
                control1X: root.a + root.w
                control1Y: root.a * 0.55
                control2X: root.a * 1.55 + root.w
                control2Y: 0
            }
        }
    }
}
