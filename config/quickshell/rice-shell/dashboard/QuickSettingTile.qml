pragma ComponentBehavior: Bound

import QtQuick
import "../theme"

FocusScope {
    id: root

    property string icon: ""
    property string label: ""
    property string sublabel: ""
    property bool active: false
    property bool available: true
    property bool pending: false
    property bool hasDetails: false

    signal activated()
    signal detailsRequested()

    implicitWidth: 120
    implicitHeight: 54
    activeFocusOnTab: false

    Rectangle {
        anchors.fill: parent
        radius: Math.min(24, height / 2)
        color: !root.available
            ? Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.55)
            : root.active
                ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, tileHover.hovered ? 0.24 : 0.17)
                : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, tileHover.hovered ? 0.98 : 0.68)
        border.width: primaryAction.activeFocus || detailsAction.activeFocus ? 2 : 1
        border.color: primaryAction.activeFocus || detailsAction.activeFocus
            ? Tokens.focus_ring
            : root.active
                ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.28)
                : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.18)

        Behavior on color { ColorAnimation { duration: 140 } }
        Behavior on border.color { ColorAnimation { duration: 140 } }
    }

    HoverHandler { id: tileHover; cursorShape: Qt.PointingHandCursor }

    TapHandler {
        acceptedButtons: Qt.RightButton
        enabled: root.hasDetails
        onTapped: root.detailsRequested()
    }

    Item {
        id: primaryAction
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: root.hasDetails ? detailsAction.left : parent.right
        activeFocusOnTab: true
        enabled: root.available && !root.pending
        opacity: root.available ? 1 : 0.55

        Accessible.role: Accessible.Button
        Accessible.name: root.label
        Accessible.description: root.available
            ? (root.sublabel || (root.active ? qsTr("On") : qsTr("Off")))
            : (root.sublabel || qsTr("Unavailable"))
        Accessible.onPressAction: root.activated()

        Row {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 4
            spacing: 8

            Rectangle {
                width: 28
                height: 28
                radius: 14
                anchors.verticalCenter: parent.verticalCenter
                color: root.active ? Tokens.accent
                    : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.12)
                Text {
                    anchors.centerIn: parent
                    text: root.pending ? "󰔟" : root.icon
                    font.pixelSize: 16
                    color: root.active ? Tokens.on_accent : Tokens.text_secondary
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, parent.width - 36)
                spacing: 2

                Text {
                    width: parent.width
                    text: root.label
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    color: Tokens.text_primary
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    visible: root.sublabel.length > 0
                    text: root.sublabel
                    font.pixelSize: 10
                    color: root.available ? Tokens.text_secondary : Tokens.danger
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
            }
        }

        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                root.activated();
                event.accepted = true;
            }
        }

        TapHandler {
            acceptedButtons: Qt.LeftButton
            enabled: primaryAction.enabled
            onTapped: root.activated()
        }
    }

    Item {
        id: detailsAction
        visible: root.hasDetails
        width: 36
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        activeFocusOnTab: root.hasDetails

        Accessible.role: Accessible.Button
        Accessible.name: qsTr("Open %1 details").arg(root.label)
        Accessible.description: qsTr("Open detailed controls for %1").arg(root.label)
        Accessible.onPressAction: root.detailsRequested()

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: 10
            anchors.bottomMargin: 10
            width: 1
            color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.18)
        }

        Text {
            anchors.centerIn: parent
            text: "󰅂"
            font.pixelSize: 14
            color: detailsAction.activeFocus ? Tokens.focus_ring : Tokens.text_secondary
        }

        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                root.detailsRequested();
                event.accepted = true;
            }
        }

        TapHandler {
            acceptedButtons: Qt.LeftButton
            onTapped: root.detailsRequested()
        }
    }
}
