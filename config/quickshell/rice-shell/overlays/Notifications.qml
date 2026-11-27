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

    property var liveNotifications: ({})
    signal notificationReceived(int notificationId, string summary, string body,
                                string appName, string appIcon, string actionsJson)

    function actionMetadata(notification): var {
        var result = [];
        var actions = notification.actions || [];
        for (var i = 0; i < actions.length; i++) {
            var action = actions[i];
            if (!action || !action.identifier || !action.text) continue;
            result.push({
                id: action.identifier,
                text: action.text,
                isDefault: action.identifier === "default"
            });
        }
        return result;
    }

    function registerNotification(notification): void {
        liveNotifications[notification.id] = {
            notification: notification,
            invokedActions: ({})
        };
    }

    function unregisterNotification(notificationId: int): void {
        delete liveNotifications[notificationId];
        DesktopControls.deactivateNotification(notificationId);
    }

    function invokeNotificationAction(notificationId: int, actionId: string): void {
        var live = liveNotifications[notificationId];
        if (!live || !live.notification || !live.notification.tracked
                || live.invokedActions[actionId]) return;
        var actions = live.notification.actions || [];
        for (var i = 0; i < actions.length; i++) {
            var action = actions[i];
            if (!action || action.identifier !== actionId) continue;
            live.invokedActions[actionId] = true;
            action.invoke();
            return;
        }
    }

    Connections {
        target: DesktopControls
        function onNotificationActionRequested(notificationId, actionId) {
            root.invokeNotificationAction(notificationId, actionId);
        }
        function onNotificationDismissRequested(notificationId) {
            var live = root.liveNotifications[notificationId];
            if (live && live.notification && live.notification.tracked)
                live.notification.dismiss();
        }
    }

    function publishNotification(notif): void {
        DesktopControls.lastSummary = notif.summary || "Notification";
        DesktopControls.lastBody = notif.body || "";
        DesktopControls.recordNotification(notif.id, DesktopControls.lastSummary,
            DesktopControls.lastBody, notif.appName || "", notif.appIcon || "",
            notif.lastGeneration, root.actionMetadata(notif));
        if (!notif.lastGeneration && !DesktopControls.doNotDisturb)
            root.notificationReceived(notif.id, DesktopControls.lastSummary,
                DesktopControls.lastBody, notif.appName || "", notif.appIcon || "",
                JSON.stringify(root.actionMetadata(notif)));
    }

    Component {
        id: expirationTimer

        Item {
            id: expiration
            required property var notification
            property int notificationId: -1
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
                if (notificationId >= 0)
                    root.unregisterNotification(notificationId);
                expiration.destroy();
            }

            Component.onCompleted: {
                notificationId = notification.id;
                restartTimer();
            }

            Timer {
                id: timer
                // Quickshell 0.3.2 exposes the raw D-Bus timeout in milliseconds.
                repeat: false
                onTriggered: {
                    if (expiration.disposed)
                        return;
                    timer.stop();
                    if (expiration.notification && expiration.notification.tracked) {
                        root.unregisterNotification(expiration.notification.id);
                        expiration.notification.expire();
                    }
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
        actionIconsSupported: false
        inlineReplySupported: false
        actionsSupported: true

        onNotification: (notif) => {
            notif.tracked = true;
            root.registerNotification(notif);
            expirationTimer.createObject(root, { notification: notif });
            root.publishNotification(notif);
        }
    }
}
