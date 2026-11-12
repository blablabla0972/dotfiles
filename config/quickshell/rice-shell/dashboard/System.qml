pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../theme"

Item {
    id: root

    implicitWidth: 724
    implicitHeight: 370

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

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        // 1. Top Summary Strip: Hostname, Kernel, Uptime & Session Status
        Rectangle {
            Layout.fillWidth: true
            height: 42
            radius: 12
            color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.75)
            border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 16

                // Host
                Row {
                    spacing: 6
                    Layout.alignment: Qt.AlignVCenter
                    Text {
                        text: "󰌢"
                        font.pixelSize: 14
                        color: Tokens.accent
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "cachyos-x8664"
                        font.pixelSize: 11
                        font.bold: true
                        color: Tokens.text_primary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // Kernel
                Row {
                    spacing: 6
                    Layout.alignment: Qt.AlignVCenter
                    Text {
                        text: "󰌽"
                        font.pixelSize: 14
                        color: Tokens.accent
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "Linux CachyOS"
                        font.pixelSize: 11
                        color: Tokens.text_secondary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // Uptime
                Row {
                    spacing: 6
                    Layout.alignment: Qt.AlignVCenter
                    Text {
                        text: "󰔟"
                        font.pixelSize: 14
                        color: Tokens.accent
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "Up: " + root.uptime
                        font.pixelSize: 11
                        font.bold: true
                        color: Tokens.text_primary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Item { Layout.fillWidth: true }

                // Live Active Dot
                Row {
                    spacing: 6
                    Layout.alignment: Qt.AlignVCenter
                    Rectangle {
                        width: 8
                        height: 8
                        radius: 4
                        color: "#4ade80"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "Wayland Active"
                        font.pixelSize: 10
                        font.bold: true
                        color: "#4ade80"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }

        // 2. Three Metric Cards: CPU, RAM, Storage
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            // CPU Card
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 14
                color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.75)
                border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            width: 32
                            height: 32
                            radius: 16
                            color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2)

                            Text {
                                anchors.centerIn: parent
                                text: "󰍛"
                                font.pixelSize: 16
                                color: Tokens.accent
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Text {
                                text: "Processor"
                                font.pixelSize: 12
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
                            font.pixelSize: 18
                            font.bold: true
                            color: Tokens.accent
                        }
                    }

                    Item { Layout.fillHeight: true }

                    // Usage Bar
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
                            font.pixelSize: 10
                            color: Tokens.text_secondary
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: "Live CPU"
                            font.pixelSize: 9
                            color: Qt.rgba(Tokens.text_secondary.r, Tokens.text_secondary.g, Tokens.text_secondary.b, 0.6)
                        }
                    }
                }
            }

            // RAM Card
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 14
                color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.75)
                border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            width: 32
                            height: 32
                            radius: 16
                            color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2)

                            Text {
                                anchors.centerIn: parent
                                text: "󰘚"
                                font.pixelSize: 16
                                color: Tokens.accent
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Text {
                                text: "Memory (RAM)"
                                font.pixelSize: 12
                                font.bold: true
                                color: Tokens.text_primary
                            }

                            Text {
                                text: root.ramUsed + " / " + root.ramTotal
                                font.pixelSize: 10
                                color: Tokens.text_secondary
                            }
                        }

                        Text {
                            text: root.ramPct + "%"
                            font.pixelSize: 18
                            font.bold: true
                            color: Tokens.accent
                        }
                    }

                    Item { Layout.fillHeight: true }

                    // Usage Bar
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
                            font.pixelSize: 10
                            color: Tokens.text_secondary
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: "Physical RAM"
                            font.pixelSize: 9
                            color: Qt.rgba(Tokens.text_secondary.r, Tokens.text_secondary.g, Tokens.text_secondary.b, 0.6)
                        }
                    }
                }
            }

            // Storage Card
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 14
                color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.75)
                border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            width: 32
                            height: 32
                            radius: 16
                            color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2)

                            Text {
                                anchors.centerIn: parent
                                text: "󰋊"
                                font.pixelSize: 16
                                color: Tokens.accent
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Text {
                                text: "Storage (/)"
                                font.pixelSize: 12
                                font.bold: true
                                color: Tokens.text_primary
                            }

                            Text {
                                text: root.diskUsed + " / " + root.diskTotal
                                font.pixelSize: 10
                                color: Tokens.text_secondary
                            }
                        }

                        Text {
                            text: root.diskPct + "%"
                            font.pixelSize: 18
                            font.bold: true
                            color: Tokens.accent
                        }
                    }

                    Item { Layout.fillHeight: true }

                    // Usage Bar
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
                            text: "Root Filesystem"
                            font.pixelSize: 10
                            color: Tokens.text_secondary
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: "Btrfs NVMe"
                            font.pixelSize: 9
                            color: Qt.rgba(Tokens.text_secondary.r, Tokens.text_secondary.g, Tokens.text_secondary.b, 0.6)
                        }
                    }
                }
            }
        }

        // 3. Bottom Environment Details Strip
        Rectangle {
            Layout.fillWidth: true
            height: 52
            radius: 12
            color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.75)
            border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 20

                ColumnLayout {
                    spacing: 2
                    Text {
                        text: "Compositor"
                        font.pixelSize: 10
                        color: Tokens.text_secondary
                    }
                    Text {
                        text: "Hyprland 0.57.0"
                        font.pixelSize: 11
                        font.bold: true
                        color: Tokens.text_primary
                    }
                }

                Rectangle {
                    width: 1
                    height: 24
                    color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
                }

                ColumnLayout {
                    spacing: 2
                    Text {
                        text: "Desktop Shell"
                        font.pixelSize: 10
                        color: Tokens.text_secondary
                    }
                    Text {
                        text: "Quickshell 0.3.2"
                        font.pixelSize: 11
                        font.bold: true
                        color: Tokens.accent
                    }
                }

                Rectangle {
                    width: 1
                    height: 24
                    color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
                }

                ColumnLayout {
                    spacing: 2
                    Text {
                        text: "Palette Engine"
                        font.pixelSize: 10
                        color: Tokens.text_secondary
                    }
                    Text {
                        text: "Matugen Dynamic"
                        font.pixelSize: 11
                        font.bold: true
                        color: Tokens.text_primary
                    }
                }

                Item { Layout.fillWidth: true }

                ColumnLayout {
                    spacing: 2
                    Layout.alignment: Qt.AlignRight
                    Text {
                        text: "Telemetry Interval"
                        font.pixelSize: 10
                        color: Tokens.text_secondary
                    }
                    Text {
                        text: "2.0s Polling"
                        font.pixelSize: 11
                        color: Qt.rgba(Tokens.text_secondary.r, Tokens.text_secondary.g, Tokens.text_secondary.b, 0.8)
                    }
                }
            }
        }
    }
}
