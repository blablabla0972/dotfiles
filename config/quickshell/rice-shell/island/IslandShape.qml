pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

Item {
    id: root

    property vector3d targetGeometry: Qt.vector3d(140, 28, 14)
    readonly property real pillWidth: Math.max(1, spring.position.x)
    readonly property real pillHeight: Math.max(1, spring.position.y)
    property real antiCornerRadius: 12
    readonly property real bottomRadius: spring.position.z
    property color fillColor: "#1a1b21"
    property color borderColor: "#43474e"
    property bool showAntiCorners: true

    property bool contracting: false
    property bool mediaBounce: false
    readonly property bool morphing: spring.running

    IslandSpring {
        id: spring
        target: root.targetGeometry
        contracting: root.contracting
        mediaBounce: root.mediaBounce
    }

    // Budgeted radii to prevent self-intersecting arcs
    readonly property real r: Math.max(0, Math.min(root.bottomRadius, root.pillHeight / 2, root.pillWidth / 2))
    readonly property real a: root.showAntiCorners ? Math.max(0, Math.min(root.antiCornerRadius, root.pillHeight - r)) : 0
    readonly property real w: root.pillWidth
    readonly property real h: root.pillHeight

    width: pillWidth + 2 * a
    height: pillHeight

    Rectangle {
        id: roundedRect
        anchors.fill: parent
        visible: !root.showAntiCorners
        radius: root.r
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.tint(root.fillColor, "#0cffffff") }
            GradientStop { position: 1; color: root.fillColor }
        }
        border.color: root.borderColor
        Behavior on border.color { ColorAnimation { duration: 150 } }
        border.width: 1
    }

    Loader {
        anchors.fill: parent
        active: root.showAntiCorners
        sourceComponent: Shape {
            preferredRendererType: Shape.CurveRenderer
            antialiasing: true

            // Fill closes the open path implicitly; the top bezel gets no stroke.
            ShapePath {
                fillColor: root.fillColor
                strokeColor: root.borderColor
                strokeWidth: 1
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                startX: 0
                startY: 0

                PathCubic {
                    x: root.a
                    y: root.a
                    control1X: root.a * 0.45
                    control1Y: 0
                    control2X: root.a
                    control2Y: root.a * 0.55
                }

                PathLine { x: root.a; y: root.h - root.r }

                PathArc {
                    x: root.a + root.r
                    y: root.h
                    radiusX: root.r
                    radiusY: root.r
                    direction: PathArc.Counterclockwise
                }

                PathLine { x: root.a + root.w - root.r; y: root.h }

                PathArc {
                    x: root.a + root.w
                    y: root.h - root.r
                    radiusX: root.r
                    radiusY: root.r
                    direction: PathArc.Counterclockwise
                }

                PathLine { x: root.a + root.w; y: root.a }

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
}
