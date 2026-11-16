import QtQuick
import QtQuick.Controls.Basic as Basic
import "../theme"

Basic.Menu {
    id: control
    popupType: Basic.Popup.Item
    transformOrigin: Basic.Popup.TopRight
    property bool reopenRequested: false
    // Qt Menu ignores open() during exit; let its native cleanup finish first.
    function requestOpen(): void {
        if (visible && exit.running) reopenRequested = true;
        else if (exit.running) Qt.callLater(control.open);
        else open();
    }
    onClosed: {
        if (reopenRequested) {
            reopenRequested = false;
            Qt.callLater(control.open);
        }
    }
    implicitWidth: Math.max(220, contentItem.implicitWidth + leftPadding + rightPadding)
    padding: 6
    overlap: 0
    background: Rectangle {
        radius: 18
        color: Tokens.surface
        border.width: 1
        border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.4)
    }
    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 130 }
        SpringAnimation { property: "scale"; from: 0.9; to: 1; spring: 4.0; damping: 0.34; epsilon: 0.001 }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; to: 0; duration: 90 }
        NumberAnimation { property: "scale"; to: 0.94; duration: 140; easing.type: Easing.InOutCubic }
    }
}
