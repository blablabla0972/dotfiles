pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../theme"

Item {
    id: root

    property int cpuPct: 0
    property string cpuLoad: "0.00"
    property string cpuModel: "Linux Processor"
    property string ramUsed: "0 GB"
    property string ramTotal: "0 GB"
    property int ramPct: 0
    property string diskUsed: "0 GB"
    property string diskTotal: "0 GB"
    property int diskPct: 0
    property string uptime: "0m"

    function refreshTelemetry(): void {
        if (!telemetryProcess.running) {
            telemetryProcess.running = true;
        }
    }

    Component.onCompleted: refreshTelemetry()
    onVisibleChanged: {
        if (visible) refreshTelemetry();
    }

    Timer {
        interval: 2000
        running: root.visible
        repeat: true
        onTriggered: root.refreshTelemetry()
    }

    Process {
        id: telemetryProcess
        command: ["python3", Quickshell.shellDir + "/dashboard/telemetry.py"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text);
                    if (data) {
                        root.cpuPct = data.cpu_pct !== undefined ? data.cpu_pct : 0;
                        root.cpuLoad = data.cpu_load || "0.00";
                        root.cpuModel = data.cpu_model || "Linux Processor";
                        root.ramUsed = data.ram_used || "0 GB";
                        root.ramTotal = data.ram_total || "0 GB";
                        root.ramPct = data.ram_pct !== undefined ? data.ram_pct : 0;
                        root.diskUsed = data.disk_used || "0 GB";
                        root.diskTotal = data.disk_total || "0 GB";
                        root.diskPct = data.disk_pct !== undefined ? data.disk_pct : 0;
                        root.uptime = data.uptime || "0m";
                    }
                } catch (e) {
                    // Ignore JSON parse errors
                }
            }
        }
    }

    GridLayout {
        anchors.fill: parent
        columns: 2
        rowSpacing: 12
        columnSpacing: 12

        // 1. CPU Telemetry Card
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 14
            color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.75)
            border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Rectangle {
                        width: 34
                        height: 34
                        radius: 17
                        color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2)

                        Text {
                            anchors.centerIn: parent
                            text: "󰍛"
                            font.pixelSize: 18
                            color: Tokens.accent
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: "Processor (CPU)"
                            font.pixelSize: 13
                            font.bold: true
                            color: Tokens.text_primary
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.cpuModel
                            font.pixelSize: 10
                            color: Tokens.text_secondary
                            elide: Text.ElideRight
                        }
                    }

                    Text {
                        text: root.cpuPct + "%"
                        font.pixelSize: 20
                        font.bold: true
                        color: Tokens.accent
                    }
                }

                Item { Layout.fillHeight: true }

                // CPU Usage Bar
                Rectangle {
                    Layout.fillWidth: true
                    height: 8
                    radius: 4
                    color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.9)

                    Rectangle {
                        height: parent.height
                        width: Math.min(parent.width, Math.max(0, parent.width * (root.cpuPct / 100.0)))
                        radius: 4
                        color: root.cpuPct > 85 ? Tokens.danger : Tokens.accent

                        Behavior on width {
                            NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "Load: " + root.cpuLoad
                        font.pixelSize: 11
                        color: Tokens.text_secondary
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: "Live Telemetry"
                        font.pixelSize: 10
                        color: Qt.rgba(Tokens.text_secondary.r, Tokens.text_secondary.g, Tokens.text_secondary.b, 0.7)
                    }
                }
            }
        }

        // 2. Memory (RAM) Card
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 14
            color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.75)
            border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Rectangle {
                        width: 34
                        height: 34
                        radius: 17
                        color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2)

                        Text {
                            anchors.centerIn: parent
                            text: "󰘚"
                            font.pixelSize: 18
                            color: Tokens.accent
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: "Memory (RAM)"
                            font.pixelSize: 13
                            font.bold: true
                            color: Tokens.text_primary
                        }

                        Text {
                            text: root.ramUsed + " / " + root.ramTotal
                            font.pixelSize: 11
                            color: Tokens.text_secondary
                        }
                    }

                    Text {
                        text: root.ramPct + "%"
                        font.pixelSize: 20
                        font.bold: true
                        color: Tokens.accent
                    }
                }

                Item { Layout.fillHeight: true }

                // RAM Usage Bar
                Rectangle {
                    Layout.fillWidth: true
                    height: 8
                    radius: 4
                    color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.9)

                    Rectangle {
                        height: parent.height
                        width: Math.min(parent.width, Math.max(0, parent.width * (root.ramPct / 100.0)))
                        radius: 4
                        color: root.ramPct > 90 ? Tokens.danger : Tokens.accent

                        Behavior on width {
                            NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "Available: " + (100 - root.ramPct) + "%"
                        font.pixelSize: 11
                        color: Tokens.text_secondary
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: "Physical RAM"
                        font.pixelSize: 10
                        color: Qt.rgba(Tokens.text_secondary.r, Tokens.text_secondary.g, Tokens.text_secondary.b, 0.7)
                    }
                }
            }
        }

        // 3. Storage (Disk /) Card
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 14
            color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.75)
            border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Rectangle {
                        width: 34
                        height: 34
                        radius: 17
                        color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2)

                        Text {
                            anchors.centerIn: parent
                            text: "󰋊"
                            font.pixelSize: 18
                            color: Tokens.accent
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: "Root Filesystem (/)"
                            font.pixelSize: 13
                            font.bold: true
                            color: Tokens.text_primary
                        }

                        Text {
                            text: root.diskUsed + " / " + root.diskTotal
                            font.pixelSize: 11
                            color: Tokens.text_secondary
                        }
                    }

                    Text {
                        text: root.diskPct + "%"
                        font.pixelSize: 20
                        font.bold: true
                        color: Tokens.accent
                    }
                }

                Item { Layout.fillHeight: true }

                // Disk Usage Bar
                Rectangle {
                    Layout.fillWidth: true
                    height: 8
                    radius: 4
                    color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.9)

                    Rectangle {
                        height: parent.height
                        width: Math.min(parent.width, Math.max(0, parent.width * (root.diskPct / 100.0)))
                        radius: 4
                        color: root.diskPct > 90 ? Tokens.danger : Tokens.accent

                        Behavior on width {
                            NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "NVMe Btrfs System"
                        font.pixelSize: 11
                        color: Tokens.text_secondary
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: "Storage Volume"
                        font.pixelSize: 10
                        color: Qt.rgba(Tokens.text_secondary.r, Tokens.text_secondary.g, Tokens.text_secondary.b, 0.7)
                    }
                }
            }
        }

        // 4. System Uptime Card
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 14
            color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.75)
            border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Rectangle {
                        width: 34
                        height: 34
                        radius: 17
                        color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2)

                        Text {
                            anchors.centerIn: parent
                            text: "󰔟"
                            font.pixelSize: 18
                            color: Tokens.accent
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: "System Uptime"
                            font.pixelSize: 13
                            font.bold: true
                            color: Tokens.text_primary
                        }

                        Text {
                            text: "Session duration"
                            font.pixelSize: 11
                            color: Tokens.text_secondary
                        }
                    }

                    Text {
                        text: root.uptime
                        font.pixelSize: 20
                        font.bold: true
                        color: Tokens.accent
                    }
                }

                Item { Layout.fillHeight: true }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        width: 8
                        height: 8
                        radius: 4
                        color: "#4ade80" // Active green status dot
                    }

                    Text {
                        text: "Host: cachyos-x8664 • Hyprland active"
                        font.pixelSize: 11
                        color: Tokens.text_secondary
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "Kernel: Linux 6.17 CachyOS"
                        font.pixelSize: 10
                        color: Qt.rgba(Tokens.text_secondary.r, Tokens.text_secondary.g, Tokens.text_secondary.b, 0.7)
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: "Wayland Display"
                        font.pixelSize: 10
                        color: Qt.rgba(Tokens.text_secondary.r, Tokens.text_secondary.g, Tokens.text_secondary.b, 0.7)
                    }
                }
            }
        }
    }
}
