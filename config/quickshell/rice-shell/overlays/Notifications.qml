pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import "../theme"
import "../services"

Item {
    id: root

    signal notificationReceived(string summary, string body, string appName, string appIcon)

    Component {
        id: expirationTimer

        Item {
            id: expiration
            required property var notification
            property bool disposed: false

            function dispose() {
                if (disposed)
                    return;
                disposed = true;
                timer.stop();
                expiration.destroy();
            }

            Timer {
                id: timer
                // Quickshell 0.3.2 exposes the raw D-Bus timeout in milliseconds.
                interval: expiration.notification.expireTimeout < 0
                    ? 5000 : expiration.notification.expireTimeout
                running: expiration.notification.expireTimeout !== 0
                onTriggered: {
                    if (expiration.disposed)
                        return;
                    timer.stop();
                    if (expiration.notification && expiration.notification.tracked)
                        expiration.notification.expire();
                    expiration.dispose();
                }
            }

            Connections {
                target: expiration.notification
                function onClosed() {
                    expiration.dispose();
                }
            }
        }
    }

    NotificationServer {
        id: server
        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: true
        actionsSupported: false

        onNotification: (notif) => {
            notif.tracked = true;
            expirationTimer.createObject(root, { notification: notif });
            DesktopControls.lastSummary = notif.summary || "Notification";
            DesktopControls.lastBody = notif.body || "";
            DesktopControls.recordNotification(DesktopControls.lastSummary,
                DesktopControls.lastBody, notif.appName || "", notif.appIcon || "");
            if (!notif.lastGeneration && !DesktopControls.doNotDisturb)
                root.notificationReceived(
                    DesktopControls.lastSummary,
                    DesktopControls.lastBody,
                    notif.appName || "",
                    notif.appIcon || ""
                );
        }
    }
}
