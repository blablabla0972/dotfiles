# Notification Actions and D-Bus Design

## Goal

Support real D-Bus notification actions in the Notification Center and popup/island while keeping history serializable and stale actions safe.

## Architecture

`Notifications.qml` owns the live notification registry and enables Quickshell actions. `DesktopControls.qml` stores serializable history metadata plus action labels and a stable notification id. The Center and island render those metadata entries, while action handlers resolve the live object through the registry before invoking it once.

Closed, expired, or reloaded notifications are removed from the live registry but remain in history. Inline reply remains disabled because this change only implements the documented `NotificationAction.invoke()` API.

## Error handling and lifecycle

Every action click checks that the live notification is still tracked, that the action object is still present, and that the notification has not already been invoked. Close and timer disposal unregister the live object. History never stores QML objects or action handles.

## Testing

Static QML regression tests cover advertised capabilities, action metadata flow, default action handling, duplicate guards, close/expiry cleanup, and history persistence. Repository validation, QML/native checks available in the checkout, and the full Python suite will run without reloading the live desktop.
