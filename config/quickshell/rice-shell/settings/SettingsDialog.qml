pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import "../theme"
import "Registry.js" as Registry

Dialog {
    id: dialog
    property int bodyHeight: 58
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: parent ? Math.min(440, Math.max(160, parent.width - 32)) : 400
    implicitHeight: topPadding + bottomPadding + bodyHeight
        + (header && header.visible ? header.implicitHeight : 0)
        + (footer && footer.visible ? footer.implicitHeight : 0)
    modal: true
    padding: 17
    palette.window: Tokens.surface_low
    palette.windowText: Registry.readable(Tokens.text_primary, Tokens.surface_low, 4.5)
    palette.buttonText: Registry.readable(Tokens.text_primary, Tokens.surface, 4.5)
    palette.button: Tokens.surface
    background: Rectangle {
        radius: 15
        color: Tokens.surface_low
        border.color: Tokens.outline
    }
}
