pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

Item {
    id: group

    default property alias rows: body.data
    required property color surface
    required property color rule
    Layout.fillWidth: true
    implicitHeight: body.implicitHeight

    Rectangle {
        anchors.fill: parent
        radius: 10
        color: group.surface
        border.color: group.rule
    }
    ColumnLayout {
        id: body
        anchors.fill: parent
        spacing: 0
    }
}
