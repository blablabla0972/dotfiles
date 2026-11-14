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
    readonly property int layoutColumns: width < 700 ? 1 : 2

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

    function displayText(value): string {
        return value === undefined || value === null || String(value).length === 0 ? "—" : String(value);
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
        spacing: 8

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 46
            radius: 12
            color: root.cardColor
            border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.35)
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 14
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
                    spacing: 1

                    Text {
                        text: "System"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: Tokens.text_primary
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.displayText(root.sample.os_name) + " · " + root.cpuModel
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
                    text: root.sampleHealthy ? "Live · 5s"
                        : root.hasSample ? "Stale · last sample" : "Waiting for data"
                    font.pixelSize: 10
                    color: root.sampleHealthy ? Tokens.accent : Tokens.text_secondary
                }
            }
        }

        GridLayout {
            id: metricsGrid
            Layout.fillWidth: true
            Layout.preferredHeight: root.width < 700 ? 286 : 124
            Layout.minimumHeight: root.width < 700 ? 270 : 112
            columns: root.width < 700 ? 1 : 3
            rowSpacing: 8
            columnSpacing: 8

            Repeater {
                model: 3

                delegate: Rectangle {
                    id: card
                    required property int index

                    readonly property bool processor: index === 0
                    readonly property bool memory: index === 1
                    readonly property string metricName: processor ? "Processor"
                        : memory ? "Memory" : "Root storage"
                    readonly property string metricIcon: processor ? "󰍛"
                        : memory ? "󰘚" : "󰋊"
                    readonly property var percent: processor ? root.cpuPct
                        : memory ? root.ramPct : root.diskPct
                    readonly property color valueColor: percent === null ? Tokens.text_secondary
                        : percent >= (processor ? 85 : 90) ? Tokens.danger : Tokens.accent
                    readonly property string amountText: {
                        if (processor) return "1 min load · " + root.displayText(root.sample.load_1m);
                        const used = memory ? root.sample.ram_used : root.sample.disk_used;
                        const total = memory ? root.sample.ram_total : root.sample.disk_total;
                        const compactUsed = used ? String(used).split(" ")[0] : "—";
                        return compactUsed + " / " + root.displayText(total);
                    }
                    readonly property string detailLeft: {
                        if (processor) return root.displayText(root.sample.cpu_threads) + " threads";
                        const value = memory ? root.sample.ram_available : root.sample.disk_free;
                        return (memory ? "Available · " : "Free · ") + root.displayText(value);
                    }
                    readonly property string detailRight: processor ? "CPU"
                        : memory ? "RAM" : root.displayText(root.sample.filesystem) + " · /"

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumWidth: 0
                    Layout.minimumHeight: root.width < 700 ? 84 : 112
                    radius: 12
                    color: root.cardColor
                    border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.35)
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: root.width < 700 ? 10 : 12
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 7
                            Text {
                                text: card.metricIcon
                                font.pixelSize: 15
                                color: Tokens.accent
                            }
                            Text {
                                text: card.metricName
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                color: Tokens.text_primary
                            }
                            Item { Layout.fillWidth: true }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 5

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                RowLayout {
                                    spacing: 2
                                    Text {
                                        text: card.percent === null ? "—" : Math.round(card.percent)
                                        font.pixelSize: root.width < 700 ? 28 : 31
                                        font.weight: Font.DemiBold
                                        font.features: { "tnum": 1 }
                                        color: card.valueColor
                                    }
                                    Text {
                                        text: card.percent === null ? "" : "%"
                                        font.pixelSize: 15
                                        color: Tokens.text_secondary
                                        Layout.alignment: Qt.AlignBottom
                                        Layout.bottomMargin: 4
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: card.amountText
                                    font.pixelSize: 9
                                    color: Tokens.text_secondary
                                    elide: Text.ElideRight
                                }
                            }

                            Canvas {
                                id: metricGauge
                                Layout.preferredWidth: 40
                                Layout.preferredHeight: 40
                                property real metricValue: card.percent === null ? -1 : card.percent
                                property color activeColor: card.valueColor
                                property color trackColor: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.55)

                                onMetricValueChanged: requestPaint()
                                onActiveColorChanged: requestPaint()
                                onTrackColorChanged: requestPaint()
                                onWidthChanged: requestPaint()
                                onHeightChanged: requestPaint()

                                onPaint: {
                                    const ctx = getContext("2d");
                                    ctx.clearRect(0, 0, width, height);
                                    const center = Math.min(width, height) / 2;
                                    const radius = center - 3;
                                    const start = -Math.PI * 0.75;
                                    const sweep = Math.PI * 1.5;
                                    ctx.lineWidth = 3;
                                    ctx.lineCap = "round";
                                    ctx.beginPath();
                                    ctx.strokeStyle = trackColor;
                                    ctx.arc(center, center, radius, start, start + sweep);
                                    ctx.stroke();
                                    if (metricValue < 0) return;
                                    ctx.beginPath();
                                    ctx.strokeStyle = activeColor;
                                    ctx.arc(center, center, radius, start,
                                            start + sweep * Math.max(0, Math.min(100, metricValue)) / 100);
                                    ctx.stroke();
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Text {
                                Layout.fillWidth: true
                                text: card.detailLeft
                                font.pixelSize: 9
                                color: Tokens.text_secondary
                                elide: Text.ElideRight
                            }
                            Text {
                                text: card.detailRight
                                font.pixelSize: 9
                                color: Tokens.text_secondary
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: root.width < 700 ? 145 : 112
            Layout.minimumHeight: 100
            radius: 12
            color: root.cardColor
            border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.35)
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 11
                spacing: 5

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "CPU history"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: Tokens.text_primary
                    }
                    Text {
                        text: "0–100%"
                        font.pixelSize: 9
                        color: Tokens.text_secondary
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: root.cpuHistory.length === 0 ? "Waiting for samples"
                            : root.cpuHistory.length === 1 ? "1 sample · collecting history"
                            : root.cpuHistory.length < 30
                                ? root.cpuHistory.length + "/30 · 5s target"
                                : "30 samples · " + "Last 2.5m"
                        font.pixelSize: 9
                        color: Tokens.text_secondary
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 7

                    Canvas {
                        id: historyGraph
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        property color graphColor: root.cpuColor
                        property color gridColor: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.5)
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
                            const yAt = value => pad + h * (1 - value / 100);
                            ctx.strokeStyle = graphColor;
                            ctx.lineWidth = 1.6;
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
                                ctx.arc(pad + w, yAt(latest), 2.5, 0, Math.PI * 2);
                                ctx.fill();
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillHeight: true
                        spacing: 0
                        Text { text: "100"; font.pixelSize: 8; color: Tokens.text_secondary }
                        Item { Layout.fillHeight: true }
                        Text { text: "50"; font.pixelSize: 8; color: Tokens.text_secondary }
                        Item { Layout.fillHeight: true }
                        Text { text: "0"; font.pixelSize: 8; color: Tokens.text_secondary }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: root.width < 700 ? 68 : 48
            radius: 12
            color: root.cardColor
            border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.35)
            border.width: 1

            GridLayout {
                anchors.fill: parent
                anchors.margins: 9
                columns: root.width < 700 ? 2 : 3
                rowSpacing: 2
                columnSpacing: 10

                Repeater {
                    model: [
                        { label: "Uptime", value: root.displayText(root.sample.uptime) },
                        { label: "Kernel", value: root.displayText(root.sample.kernel) },
                        { label: "Desktop", value: root.displayText(root.sample.desktop) }
                    ]

                    delegate: ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 1

                        Text {
                            text: modelData.label
                            font.pixelSize: 9
                            color: Tokens.text_secondary
                        }
                        Text {
                            Layout.fillWidth: true
                            text: modelData.value
                            font.pixelSize: 10
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
