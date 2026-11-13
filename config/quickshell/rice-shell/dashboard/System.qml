pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../theme"

Item {
    id: root

    implicitWidth: 724
    implicitHeight: width < 700 ? 600 : 370
    readonly property int layoutColumns: metricsGrid.columns

    property var sample: ({})
    property var cpuHistory: []
    property bool sampleHealthy: false
    readonly property bool hasSample: sample && typeof sample === "object" && Object.keys(sample).length > 0
    readonly property var cpuPct: validPercent(sample.cpu_pct) ? sample.cpu_pct : null
    readonly property var ramPct: validPercent(sample.ram_pct) ? sample.ram_pct : null
    readonly property var diskPct: validPercent(sample.disk_pct) ? sample.disk_pct : null
    readonly property bool cpuAvailable: cpuPct !== null
    readonly property color cpuColor: cpuPct === null ? Tokens.text_secondary
        : cpuPct >= 85 ? Tokens.danger : Tokens.accent
    readonly property color cardColor: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.75)
    readonly property string cpuModel: (sample.cpu_model || "Processor").replace(/\(R\)|\(TM\)/g, "").replace(/ @ .+$/, "")

    function validPercent(value): bool {
        return typeof value === "number" && isFinite(value) && value >= 0 && value <= 100;
    }

    function validSnapshot(data): bool {
        if (!data || typeof data !== "object" || Array.isArray(data)) return false;
        if (data.hostname !== undefined && typeof data.hostname !== "string") return false;
        if (data.uptime !== undefined && data.uptime !== null && typeof data.uptime !== "string") return false;
        var hasKnownField = typeof data.hostname === "string";
        var metrics = ["cpu_pct", "ram_pct", "disk_pct"];
        for (var i = 0; i < metrics.length; i++) {
            var key = metrics[i];
            if (data[key] === undefined) continue;
            hasKnownField = true;
            if (data[key] !== null && !root.validPercent(data[key])) return false;
        }
        return hasKnownField;
    }

    Timer {
        id: processRestart
        interval: 1500
        repeat: false
        onTriggered: if (root.visible && !telemetryProcess.running) telemetryProcess.running = true
    }

    Timer {
        id: sampleWatchdog
        interval: 12000
        repeat: false
        onTriggered: {
            root.sampleHealthy = false;
            if (root.visible && telemetryProcess.running) telemetryProcess.running = false;
        }
    }

    onVisibleChanged: {
        if (visible) {
            if (!telemetryProcess.running) telemetryProcess.running = true;
        } else {
            processRestart.stop();
            sampleWatchdog.stop();
            root.sampleHealthy = false;
            root.cpuHistory = [];
            if (telemetryProcess.running) telemetryProcess.running = false;
        }
    }

    Component.onCompleted: if (root.visible && !telemetryProcess.running) telemetryProcess.running = true

    Process {
        id: telemetryProcess
        command: ["python3", Quickshell.shellDir + "/dashboard/telemetry.py", "--watch"]
        onRunningChanged: {
            if (running) {
                processRestart.stop();
                sampleWatchdog.restart();
            } else {
                sampleWatchdog.stop();
                root.sampleHealthy = false;
                if (root.visible) processRestart.restart();
            }
        }
        stdout: SplitParser {
            onRead: line => {
                try {
                    const data = JSON.parse(line);
                    if (!root.validSnapshot(data)) {
                        root.sampleHealthy = false;
                        return;
                    }
                    root.sample = data;
                    root.sampleHealthy = true;
                    sampleWatchdog.restart();
                    root.cpuHistory = root.cpuHistory.concat([
                        root.validPercent(data.cpu_pct) ? data.cpu_pct : null
                    ]).slice(-30);
                } catch (e) {
                    root.sampleHealthy = false;
                }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 50
            radius: 12
            color: root.cardColor

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 13
                anchors.rightMargin: 13
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    radius: 9
                    color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.16)
                    Text {
                        anchors.centerIn: parent
                        text: "󰣇"
                        font.pixelSize: 16
                        color: Tokens.accent
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        text: "System overview"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: Tokens.text_primary
                    }
                    Text {
                        Layout.fillWidth: true
                        text: (root.sample.os_name || "Linux") + " · " + (root.sample.hostname || "—")
                        font.pixelSize: 10
                        color: Tokens.text_secondary
                        elide: Text.ElideRight
                    }
                }
                Rectangle {
                    width: 7
                    height: 7
                    radius: 3.5
                    color: root.sampleHealthy ? Tokens.accent : Tokens.text_secondary
                }
                Text {
                    text: root.sampleHealthy ? "Live · 5s" : root.hasSample ? "Stale data" : "Sampling…"
                    font.pixelSize: 11
                    color: root.sampleHealthy ? Tokens.accent : Tokens.text_secondary
                }
            }
        }

        GridLayout {
            id: metricsGrid
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: root.width < 700 ? 1 : 2
            rowSpacing: 10
            columnSpacing: 10

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 360
                Layout.minimumWidth: 0
                radius: 12
                color: root.cardColor

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 7

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 7
                        Text {
                            text: "󰍛"
                            font.pixelSize: 17
                            color: Tokens.accent
                        }
                        Text {
                            text: "Processor"
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            color: Tokens.text_primary
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: root.sample.cpu_threads ? root.sample.cpu_threads + " threads" : "—"
                            font.pixelSize: 11
                            color: Tokens.text_secondary
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 5
                        Text {
                            text: root.cpuAvailable ? root.cpuPct : "—"
                            font.pixelSize: 40
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                            color: root.cpuColor
                        }
                        Text {
                            text: "%"
                            font.pixelSize: 19
                            color: Tokens.text_secondary
                            Layout.alignment: Qt.AlignBaseline
                        }
                        Item { Layout.fillWidth: true }
                        ColumnLayout {
                            spacing: 2
                            Text {
                                Layout.alignment: Qt.AlignRight
                                text: root.sample.load_1m || "—"
                                font.pixelSize: 17
                                font.weight: Font.DemiBold
                                font.features: { "tnum": 1 }
                                color: Tokens.text_primary
                            }
                            Text {
                                text: "1 min load"
                                font.pixelSize: 10
                                color: Tokens.text_secondary
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.cpuModel
                        font.pixelSize: 11
                        color: Tokens.text_secondary
                        elide: Text.ElideRight
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 65
                        spacing: 7

                        Canvas {
                            id: historyGraph
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            property color graphColor: root.cpuColor
                            property color gridColor: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.55)
                            onGraphColorChanged: requestPaint()
                            onGridColorChanged: requestPaint()
                            onWidthChanged: requestPaint()
                            onHeightChanged: requestPaint()

                            Connections {
                                target: root
                                function onCpuHistoryChanged() { historyGraph.requestPaint(); }
                            }

                            onPaint: {
                                const ctx = getContext("2d");
                                ctx.clearRect(0, 0, width, height);
                                const pad = 4;
                                const w = Math.max(1, width - 2 * pad);
                                const h = Math.max(1, height - 2 * pad);
                                ctx.strokeStyle = gridColor;
                                ctx.lineWidth = 1;
                                ctx.beginPath();
                                for (let i = 0; i < 3; i++) {
                                    const y = pad + h * i / 2;
                                    ctx.moveTo(pad, y);
                                    ctx.lineTo(pad + w, y);
                                }
                                ctx.stroke();

                                const values = root.cpuHistory;
                                if (!values.length) return;
                                const dx = w / 29;
                                const start = pad + w - dx * (values.length - 1);
                                const yAt = v => pad + h * (1 - v / 100);
                                ctx.strokeStyle = graphColor;
                                ctx.lineWidth = 1.8;
                                ctx.lineJoin = "round";
                                ctx.lineCap = "round";
                                ctx.beginPath();
                                let segmentOpen = false;
                                for (let i = 0; i < values.length; i++) {
                                    if (!root.validPercent(values[i])) {
                                        segmentOpen = false;
                                        continue;
                                    }
                                    const x = start + i * dx;
                                    const y = yAt(values[i]);
                                    if (segmentOpen) ctx.lineTo(x, y);
                                    else ctx.moveTo(x, y);
                                    segmentOpen = true;
                                }
                                ctx.stroke();
                                const latest = values[values.length - 1];
                                if (root.validPercent(latest)) {
                                    ctx.fillStyle = graphColor;
                                    ctx.beginPath();
                                    ctx.arc(pad + w, yAt(latest), 2.6, 0, Math.PI * 2);
                                    ctx.fill();
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillHeight: true
                            spacing: 0
                            Text { text: "100%"; font.pixelSize: 9; color: Tokens.text_secondary }
                            Item { Layout.fillHeight: true }
                            Text { text: "50%"; font.pixelSize: 9; color: Tokens.text_secondary }
                            Item { Layout.fillHeight: true }
                            Text { text: "0%"; font.pixelSize: 9; color: Tokens.text_secondary }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "CPU history"
                            font.pixelSize: 10
                            color: Tokens.text_secondary
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: root.cpuHistory.length < 30 ? root.cpuHistory.length + "/30 samples" : "Last 2.5m"
                            font.pixelSize: 10
                            color: Tokens.text_secondary
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 354
                Layout.minimumWidth: 0
                spacing: 10

                Repeater {
                    model: 2
                    delegate: Rectangle {
                        id: card
                        required property int index
                        readonly property bool memory: index === 0
                        readonly property string metricName: memory ? "Memory" : "Storage"
                        readonly property string metricIcon: memory ? "󰘚" : "󰋊"
                        readonly property string used: (memory ? root.sample.ram_used : root.sample.disk_used) || "—"
                        readonly property string total: (memory ? root.sample.ram_total : root.sample.disk_total) || "—"
                        readonly property string available: memory ? (root.sample.ram_available || "—") + " available"
                            : (root.sample.disk_free || "—") + " free"
                        readonly property string detail: memory ? "RAM" : (root.sample.filesystem || "—").toUpperCase() + " · /"
                        readonly property var percent: memory ? root.ramPct : root.diskPct
                        readonly property color valueColor: percent === null ? Tokens.text_secondary
                            : percent >= 90 ? Tokens.danger : Tokens.accent

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredHeight: 110
                        radius: 12
                        color: root.cardColor

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 13
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 7
                                Text {
                                    text: card.metricIcon
                                    font.pixelSize: 16
                                    color: Tokens.accent
                                }
                                Text {
                                    text: card.metricName
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    color: Tokens.text_primary
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: card.percent === null ? "—" : card.percent + "%"
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    font.features: { "tnum": 1 }
                                    color: card.valueColor
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 5
                                Text {
                                    text: card.used.split(" ")[0]
                                    font.pixelSize: 24
                                    font.weight: Font.DemiBold
                                    font.features: { "tnum": 1 }
                                    color: Tokens.text_primary
                                }
                                Text {
                                    text: "/ " + card.total
                                    font.pixelSize: 11
                                    color: Tokens.text_secondary
                                    Layout.alignment: Qt.AlignBaseline
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 6
                                radius: 3
                                color: Tokens.surface
                                clip: true
                                Rectangle {
                                    width: card.percent === null ? 0
                                        : parent.width * Math.max(0, Math.min(1, card.percent / 100))
                                    height: parent.height
                                    radius: 3
                                    color: card.valueColor
                                    Behavior on width {
                                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    Layout.fillWidth: true
                                    text: card.available
                                    font.pixelSize: 10
                                    color: Tokens.text_secondary
                                    elide: Text.ElideRight
                                }
                                Text {
                                    text: card.detail
                                    font.pixelSize: 10
                                    color: Tokens.text_secondary
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: root.width < 700 ? 72 : 52
            radius: 12
            color: root.cardColor

            GridLayout {
                anchors.fill: parent
                anchors.margins: 13
                columns: root.width < 700 ? 2 : 3
                rowSpacing: 2
                columnSpacing: 13

                Repeater {
                    model: [
                        { label: "Uptime", value: root.sample.uptime || "—" },
                        { label: "Kernel", value: root.sample.kernel || "—" },
                        { label: "Desktop", value: root.sample.desktop || "—" }
                    ]
                    delegate: RowLayout {
                        id: detailRow
                        required property int index
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: index === 1 ? 250 : 180
                        spacing: 8

                        Rectangle {
                            visible: detailRow.index > 0 && root.width >= 700
                            width: 1
                            height: 23
                            color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.5)
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                text: detailRow.modelData.label
                                font.pixelSize: 10
                                color: Tokens.text_secondary
                            }
                            Text {
                                Layout.fillWidth: true
                                text: detailRow.modelData.value
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                color: Tokens.text_primary
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }
    }
}
