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

    function publishNotification(notif): void {
        DesktopControls.lastSummary = notif.summary || "Notification";
        DesktopControls.lastBody = notif.body || "";
        DesktopControls.recordNotification(notif.id, DesktopControls.lastSummary,
            DesktopControls.lastBody, notif.appName || "", notif.appIcon || "", notif.lastGeneration);
        if (!notif.lastGeneration && !DesktopControls.doNotDisturb)
            root.notificationReceived(DesktopControls.lastSummary,
                DesktopControls.lastBody, notif.appName || "", notif.appIcon || "");
    }

    Component {
        id: expirationTimer

        Item {
            id: expiration
            required property var notification
            property bool disposed: false
            property bool updateQueued: false

            function restartTimer(): void {
                timer.stop();
                if (disposed || !notification || notification.expireTimeout === 0)
                    return;
                timer.interval = notification.expireTimeout < 0 ? 5000 : notification.expireTimeout;
                timer.start();
            }

            function scheduleUpdate(): void {
                if (updateQueued) return;
                updateQueued = true;
                updateTimer.restart();
            }

            function publishUpdate(): void {
                updateQueued = false;
                if (disposed || !notification) return;
                restartTimer();
                root.publishNotification(notification);
            }

            function dispose() {
                if (disposed)
                    return;
                disposed = true;
                timer.stop();
                updateTimer.stop();
                expiration.destroy();
            }

            Component.onCompleted: restartTimer()

            Timer {
                id: timer
                // Quickshell 0.3.2 exposes the raw D-Bus timeout in milliseconds.
                repeat: false
                onTriggered: {
                    if (expiration.disposed)
                        return;
                    timer.stop();
                    if (expiration.notification && expiration.notification.tracked)
                        expiration.notification.expire();
                    expiration.dispose();
                }
            }

            Timer {
                id: updateTimer
                interval: 0
                repeat: false
                onTriggered: expiration.publishUpdate()
            }

            Connections {
                target: expiration.notification
                function onClosed() {
                    expiration.dispose();
                }
                function onSummaryChanged() { expiration.scheduleUpdate(); }
                function onBodyChanged() { expiration.scheduleUpdate(); }
                function onAppNameChanged() { expiration.scheduleUpdate(); }
                function onAppIconChanged() { expiration.scheduleUpdate(); }
                function onExpireTimeoutChanged() { expiration.scheduleUpdate(); }
            }
        }
    }

    NotificationServer {
        id: server
        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: false
        bodyImagesSupported: false
        bodyHyperlinksSupported: false
        actionsSupported: false

        onNotification: (notif) => {
            notif.tracked = true;
            expirationTimer.createObject(root, { notification: notif });
            root.publishNotification(notif);
        }
    }
}
