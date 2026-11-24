pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../theme"

RowLayout {
    id: root

    required property string title
    required property string icon
    signal closeRequested()

    spacing: 10

    Rectangle {
        Layout.preferredWidth: 36
        Layout.preferredHeight: 36
        radius: 12
        color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.15)
        Accessible.ignored: true

        Text {
            anchors.centerIn: parent
            text: root.icon
            font.pixelSize: 18
            color: Tokens.accent
        }
    }

    Text {
        Layout.fillWidth: true
        text: root.title
        color: Tokens.text_primary
        font.pixelSize: 18
        font.weight: Font.DemiBold
        elide: Text.ElideRight
    }

    RoundedButton {
        id: closeButton
        implicitWidth: 32
        implicitHeight: 32
        padding: 0
        horizontalPadding: 0
        font.pixelSize: 16
        text: "󰅖"
        Accessible.name: qsTr("Close %1 menu").arg(root.title)
        onClicked: root.closeRequested()
        Keys.onReturnPressed: closeButton.clicked()
        HoverHandler { cursorShape: Qt.PointingHandCursor }
    }
}
