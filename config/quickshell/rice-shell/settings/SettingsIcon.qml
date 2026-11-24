pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

Item {
    id: root

    property string name
    property color color
    implicitWidth: 18
    implicitHeight: 18
    Accessible.ignored: true

    readonly property string svg: {
        switch (name) {
        case "appearance": return "M12 3a9 9 0 1 0 0 18h1a2 2 0 0 0 1.5-3.3 2 2 0 0 1 1.5-3.2h2a3 3 0 0 0 3-3c0-4.8-4-8.5-9-8.5Z M7.5 10h.1 M9.7 6.9h.1 M14.1 6.9h.1 M17.3 9.2h.1";
        case "windows": return "M5 4h14a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2Z M10 4v16m0-8h11";
        case "shell": return "M3 7h6m6 0h6M3 17h10m6 0h2 M15 7a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z M19 17a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z";
        case "launcher": return "M4 4h6v6H4z M14 4h6v6h-6z M4 14h6v6H4z M14 14h6v6h-6z";
        case "wifi": return "M3 9a15 15 0 0 1 18 0 M6 12.5a10 10 0 0 1 12 0 M9 16a5 5 0 0 1 6 0 M12 19h.1";
        case "bluetooth": return "M6.5 7l11 10L12 21V3l5.5 4-11 10";
        case "sound": return "M10 5 6 9H3v6h3l4 4z M14 9a4.5 4.5 0 0 1 0 6m3-9a8.5 8.5 0 0 1 0 12";
        case "display": return "M5 4h14a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2Z M8 21h8m-4-4v4";
        case "power": return "M4 7h13a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2Z M22 10.5v3 M6 12h5";
        case "keyboard": return "M4 5h16a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2Z M6 9h.1 M10 9h.1 M14 9h.1 M18 9h.1 M6 13h.1 M10 13h.1 M14 13h.1 M18 13h.1 M9 16h6";
        case "notifications": return "M10 20a2 2 0 0 0 4 0 M18 8a6 6 0 0 0-12 0c0 6-2 7-2 9h16c0-2-2-3-2-9Z";
        case "maintenance": return "M14 5.7c1.8-1.8 4.3-2.1 6.1-1.4l-3.2 3.2 1.5 1.5 3.2-3.2c.8 2.2.1 4.7-1.4 6.2a5.3 5.3 0 0 1-5.4 1.3l-6.6 6.6a2.4 2.4 0 0 1-3.4-3.4l6.6-6.6A5.2 5.2 0 0 1 14 5.7Z";
        case "search": return "M10.5 4a6.5 6.5 0 1 0 0 13 6.5 6.5 0 0 0 0-13Z M16 16l4.5 4.5";
        case "back": return "M20 12H4m7-7-7 7 7 7";
        case "close": return "M6 6l12 12M18 6 6 18";
        case "image": return "M5 4h14a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2Z M3 17l4-4 4 4 4-5 6 6 M11 9a1.5 1.5 0 1 1-3 0 1.5 1.5 0 0 1 3 0Z";
        case "sun": return "M16 12a4 4 0 1 1-8 0 4 4 0 0 1 8 0Z M12 2v2m0 16v2m10-10h-2M4 12H2m3-7 1.5 1.5m11 11L19 19m0-14-1.5 1.5m-11 11L5 19";
        case "moon": return "M20.5 14.4a8.7 8.7 0 0 1-11-11 9 9 0 1 0 11 11Z";
        case "down": return "M6 9l6 6 6-6";
        case "check": return "M5 12l4 4L19 6";
        default: return "";
        }
    }

    Shape {
        preferredRendererType: Shape.CurveRenderer
        anchors.centerIn: parent
        width: 24
        height: 24
        scale: Math.min(root.width, root.height) / width

        ShapePath {
            fillColor: "transparent"
            strokeColor: root.color
            strokeWidth: 1.9
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: root.svg }
        }
    }
}

