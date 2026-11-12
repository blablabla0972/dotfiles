pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import "../theme"

Item {
    id: root

    NotificationServer {
        id: server
        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: true
        actionsSupported: true

        onNotification: (notif) => {
            // Forward alert to Dynamic Island if available
            if (parent && parent.islandNotify) {
                parent.islandNotify(notif.summary || "Notification", notif.body || "");
            }
        }
    }
}
