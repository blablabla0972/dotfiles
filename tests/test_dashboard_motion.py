"""Actual Dashboard motion/timers under native Qt, without desktop or hardware IPC."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

from test_qml_input import environment

ROOT = Path(__file__).resolve().parents[1]
SHELL = ROOT / 'config/quickshell/rice-shell'


@unittest.skipUnless(shutil.which('c++') and shutil.which('pkg-config'),
                     'Qt development tools required')
class DashboardMotionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        flags = subprocess.run(['pkg-config', '--cflags', '--libs', 'Qt6Quick',
                                'Qt6Qml', 'Qt6Test'], capture_output=True, text=True)
        if flags.returncode:
            raise unittest.SkipTest('Qt6 Quick/Qml/Test development packages unavailable')
        cls.temp = tempfile.TemporaryDirectory(prefix='dashboard-motion-')
        cls.addClassCleanup(cls.temp.cleanup)
        base = Path(cls.temp.name)
        for name in ('dashboard', 'island', 'theme', 'services'):
            (base / name).mkdir()
        for name in ('IslandShape.qml', 'IslandState.js'):
            shutil.copy2(SHELL / 'island' / name, base / 'island' / name)
        # Only hardware-backed bodies and palette loading are replaced.
        for name in ('System', 'Config', 'NotificationCenter', 'WifiDrawer', 'BluetoothDrawer'):
            body = ('import QtQuick\nItem { signal requestSideDrawer(string type); '
                    'signal closeRequested(); '
                    + ('TextInput { objectName: "wifiPassword"; text: "password" }'
                       if name == 'WifiDrawer' else '') + ' }\n')
            (base / f'dashboard/{name}.qml').write_text(body)
        shutil.copy2(SHELL / 'dashboard/Home.qml', base / 'dashboard/Home.qml')
        for name, width, height in (
                ('ProfileCard', 200, 95), ('CalendarCard', 200, 210),
                ('ClockCard', 280, 95), ('PlayerCard', 280, 220)):
            (base / f'dashboard/{name}.qml').write_text(
                f'import QtQuick\nRectangle {{ implicitWidth: {width}; implicitHeight: {height} }}\n')
        (base / 'dashboard/QuickSettings.qml').write_text(
            'import QtQuick\nRectangle { implicitWidth: 220; implicitHeight: 310; '
            'signal requestSideDrawer(string type) }\n')
        (base / 'theme/qmldir').write_text('singleton Tokens 1.0 Tokens.qml\n')
        colors = ('surface', 'surface_high', 'outline', 'accent', 'on_accent',
                  'text_primary', 'text_secondary', 'danger')
        (base / 'theme/Tokens.qml').write_text('pragma Singleton\nimport QtQuick\n'
            'QtObject { property real panelOpacity: 0.92; property string mode: "dark"\n' + ''.join(
                f'property color {name}: "#8899aa"\n' for name in colors) + '}\n')
        # Test the real shared Island geometry and Dashboard content in one Qt window.
        (base / 'services/qmldir').write_text(
            'singleton Media 1.0 Media.qml\nsingleton Audio 1.0 Audio.qml\n')
        (base / 'services/Media.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
    property bool hasPlayer: false
    property bool isPlaying: false
    property QtObject activePlayer: QtObject {
        property string trackTitle: ""
        property bool canSeek: false
        property bool positionSupported: true
        property int tickCount: 0
        signal positionChanged()
        onPositionChanged: tickCount += 1
    }
    property string trackTitle: ""
    property string trackArtist: ""
    property string trackArtUrl: ""
    property bool canToggle: false
    property bool canPrev: false
    property bool canNext: false
    property real position: 0
    property real length: 0
    property real progress: 0
    function formatTime(seconds) { return "0:00"; }
    function setPosition(seconds) {}
    function togglePlaying() {}
    function previous() {}
    function next() {}
}
''')
        (base / 'services/Audio.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
    property real volume: 0.5
    property bool available: true
    property bool muted: false
    signal osdRequested(string icon, real progress)
}
''')
        dashboard_source = (SHELL / 'dashboard/Dashboard.qml').read_text()
        dashboard_observations = '''
    property bool dashboardActiveFocus: dashboardWindow.activeFocus
    property real contentWidth: cardContent.width
    property real contentHeight: cardContent.height
    property real contentY: cardContent.y
    property real contentOpacity: cardContent.opacity
    property bool viewportClips: cardContent.parent.clip
    property real drawerWidth: sideDrawerContainer.width
    property real drawerX: sideDrawerContainer.x
    property real morphX: morphContainer.x
    property bool homeLoaded: homeLoader.item !== null
    property real homeContentHeight: homeLoader.item ? homeLoader.item.implicitHeight : 0
    property int homeLayoutColumns: homeLoader.item ? homeLoader.item.layoutColumns : 0
    property real tabContentHeight: tabScroll.contentHeight
    property real tabViewportHeight: tabScroll.height
    property real tabContentWidth: tabScroll.contentWidth
    property bool tabScrollInteractive: tabScroll.interactive
    property real tabOpacity: tabStage.opacity
    property real tabOffset: dashboardWindow.tabEntranceOffset
    property bool tabInputEnabled: tabStage.enabled
    property bool drawerHitTest: dashboardWindow.containsDrawer(
        sideDrawerContainer.x + 5, sideDrawerContainer.y + 50)
'''
        dashboard_source = dashboard_source.replace('id: dashboardWindow',
            'id: dashboardWindow\n' + dashboard_observations, 1)
        (base / 'dashboard/Dashboard.qml').write_text(dashboard_source)
        source = (SHELL / 'island/Island.qml').read_text()
        source = source.replace('import Quickshell\n', 'import QtQuick.Window\n')
        source = source.replace('import Quickshell.Wayland\n', '')
        source = source.replace('PanelWindow {', 'Window {', 1)
        source = re.sub(r'^    (?:required property ShellScreen targetScreen|'
                        r'screen: targetScreen|implicitHeight:.*|exclusionMode:.*|WlrLayershell\..*)'
                        r'(?:\n        : .*?)?\n',
                        '', source, flags=re.M)
        source = re.sub(r'    anchors \{.*?\n    \}\n', '', source, count=1, flags=re.S)
        source = re.sub(r'    mask: Region \{.*?\n    \}\n', '', source, count=1, flags=re.S)
        observations = '''
    width: 1920; height: 1080
    property var targetScreen: QtObject {
        property int width: islandWindow.width
        property int height: islandWindow.height
    }
    property real contentWidth: dashboard.contentWidth
    property real contentHeight: dashboard.contentHeight
    property real contentY: dashboard.contentY
    property real contentOpacity: dashboard.contentOpacity
    property real panelWidth: islandShape.pillWidth
    property real panelHeight: islandShape.pillHeight
    property real panelY: islandContainer.y
    property int widthDuration: islandShape.animDurationWidth
    property int heightDuration: islandShape.animDurationHeight
    property bool viewportClips: dashboard.viewportClips
    property real drawerWidth: dashboard.drawerWidth
    property real drawerX: dashboard.drawerX
    property real dashboardCardWidth: dashboard.cardDimensions.width
    property real dashboardCardHeight: dashboard.cardDimensions.height
    property bool drawerOverlay: dashboard.drawerOverlay
    property real morphX: dashboard.morphX
    property bool wifiLoaded: dashboard.wifiLoaded
    property bool bluetoothLoaded: dashboard.bluetoothLoaded
    property bool homeLoaded: dashboard.homeLoaded
    property real homeContentHeight: dashboard.homeContentHeight
    property int homeLayoutColumns: dashboard.homeLayoutColumns
    property real tabContentHeight: dashboard.tabContentHeight
    property real tabViewportHeight: dashboard.tabViewportHeight
    property real tabContentWidth: dashboard.tabContentWidth
    property bool tabScrollInteractive: dashboard.tabScrollInteractive
    property real tabOpacity: dashboard.tabOpacity
    property real tabOffset: dashboard.tabOffset
    property bool tabInputEnabled: dashboard.tabInputEnabled
    property bool drawerHitTest: dashboard.drawerHitTest
    property string tabName: dashboard.currentTab
    property bool dashboardVisible: dashboard.visible
    property bool expanded: dashboard.expanded
    property bool dashboardActiveFocus: dashboard.activeFocus
    property bool sideDrawerOpen: dashboard.sideDrawerOpen
    property bool scrimInteractive: islandWindow.modalOpen
    property string alertType: activeAlert ? activeAlert.type : ""
    property string alertSummary: activeAlert ? (activeAlert.summary || "") : ""
    property string mode: activeMode
    property bool pinned: isPinned
    property bool hoverActive: hoverPreview
    property bool hoverPointer: hoverHandler.hovered
    property bool alertTimerRunning: dismissTimer.running
    property int alertTimeout: dismissTimer.interval
    property int positionTickCount: Media.activePlayer.tickCount
    property real osdValue: osdProgress
    property real osdFillValue: osdFill
    property string osdType: osdKind
    function toggle(tab) { toggleDashboard(tab); }
    function dismiss() { dismissDashboard(); }
    function notify(summary) { triggerNotification(summary, "Body", "Test", ""); }
    function osd() { triggerOsd("vol", 0.5); }
    function osdVolume125() { triggerOsd("vol", 1.25); }
    function osdVolume150() { triggerOsd("vol", 1.5); }
    function osdBrightnessOverflow() { triggerOsd("brightness", 1.25, "brightness"); }
    function osdInvalid() { triggerOsd("vol", NaN); }
    function pin() { isPinned = true; }
    function unpin() { collapse(); }
    function simulateMedia() {
        Media.activePlayer.trackTitle = "Track";
        Media.trackTitle = "Track";
        Media.hasPlayer = true;
        Media.isPlaying = true;
    }
    function simulatePausedUntitledMedia() {
        Media.activePlayer.trackTitle = "";
        Media.trackTitle = "Unknown Track";
        Media.isPlaying = false;
    }
    function clearAlert() {
        dismissTimer.stop();
        activeAlert = null;
    }
'''
        source = source.replace('id: islandWindow', 'id: islandWindow\n' + observations, 1)
        (base / 'island/main.qml').write_text(source)
        cpp = r'''
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlError>
#include <QQuickWindow>
#include <QQuickItem>
#include <QTest>
#include <QJsonDocument>
#include <QJsonObject>
#include <QVariant>
#include <cstdio>
int main(int argc, char **argv) {
    QGuiApplication app(argc, argv);
    QQmlApplicationEngine engine;
    QObject::connect(&engine, &QQmlApplicationEngine::warnings,
                     [](const QList<QQmlError> &warnings) {
        for (const auto &warning : warnings)
            fprintf(stderr, "%s\n", qPrintable(warning.toString()));
    });
    engine.load(QUrl::fromLocalFile(argv[1]));
    if (engine.rootObjects().isEmpty()) return 2;
    auto w = qobject_cast<QQuickWindow*>(engine.rootObjects().first());
    QJsonObject results;
    auto snapshot = [&](const char *name) {
        QJsonObject row;
        for (auto key : {"contentWidth", "contentHeight", "contentY", "contentOpacity",
                         "panelWidth", "panelHeight", "panelY", "drawerWidth", "drawerX", "morphX", "widthDuration", "heightDuration",
                         "tabOpacity", "tabOffset", "dashboardCardWidth", "dashboardCardHeight",
                         "homeContentHeight", "homeLayoutColumns", "tabContentHeight",
                         "tabViewportHeight", "tabContentWidth"})
            row[key] = w->property(key).toDouble();
        for (auto key : {"dashboardVisible", "expanded", "viewportClips", "sideDrawerOpen",
                         "dashboardActiveFocus", "scrimInteractive", "pinned", "hoverActive", "hoverPointer",
                         "wifiLoaded", "bluetoothLoaded", "homeLoaded",
                         "alertTimerRunning", "tabInputEnabled", "drawerHitTest", "drawerOverlay",
                         "tabScrollInteractive"})
            row[key] = w->property(key).toBool();
        for (auto key : {"alertType", "alertSummary", "mode", "tabName"})
            row[key] = w->property(key).toString();
        row["alertTimeout"] = w->property("alertTimeout").toInt();
        row["positionTickCount"] = w->property("positionTickCount").toInt();
        row["osdValue"] = w->property("osdValue").toDouble();
        row["osdFillValue"] = w->property("osdFillValue").toDouble();
        row["osdType"] = w->property("osdType").toString();
        results[name] = row;
    };
    auto toggle = [&]() {
        return QMetaObject::invokeMethod(w, "toggle", Q_ARG(QVariant, QVariant("Home")));
    };
    auto dismiss = [&]() { return QMetaObject::invokeMethod(w, "dismiss"); };
    if (!toggle()) return 3;
    QTest::qWait(45); snapshot("opening45");
    QTest::qWait(55); snapshot("opening100");
    QTest::qWait(100); snapshot("opening200");
    QTest::qWait(170); snapshot("opened");
    dismiss(); QTest::qWait(45); snapshot("closing45");
    QTest::qWait(185); snapshot("closed230");
    QTest::qWait(170); snapshot("closed400");
    toggle(); QTest::qWait(100); dismiss(); QTest::qWait(45);
    snapshot("beforeReopen"); toggle(); snapshot("afterReopen");
    QTest::qWait(370); snapshot("reopened");
    if (!w->property("dashboardVisible").toBool()) { toggle(); QTest::qWait(370); }
    if (!QMetaObject::invokeMethod(w, "toggleSideDrawer", Q_ARG(QString, QString("wifi")))) return 4;
    QTest::qWait(280); snapshot("drawerOpened");
    QMetaObject::invokeMethod(w, "toggleSideDrawer", Q_ARG(QString, QString("bluetooth")));
    QTest::qWait(210); snapshot("bluetoothDrawerOpened");
    QMetaObject::invokeMethod(w, "toggleSideDrawer", Q_ARG(QString, QString("wifi")));
    QTest::qWait(210); snapshot("wifiDrawerRestored");
    w->setWidth(1280); QTest::qWait(360); snapshot("drawer1280Viewport");
    w->setWidth(1080); QTest::qWait(360); snapshot("drawer1080Viewport");
    w->setWidth(960); QTest::qWait(360); snapshot("drawer960Viewport");
    w->setWidth(768); QTest::qWait(360); snapshot("drawer768Viewport");
    w->setWidth(640); QTest::qWait(360); snapshot("drawer640Viewport");
    w->setHeight(360); QTest::qWait(360); snapshot("drawer640x360Viewport");
    w->setWidth(1920); w->setHeight(1080); QTest::qWait(360);
    QMetaObject::invokeMethod(w, "toggle", Q_ARG(QVariant, QVariant("System")));
    QTest::qWait(30); snapshot("systemTabEntering");
    QTest::qWait(240); snapshot("systemTabSettled");
    QMetaObject::invokeMethod(w, "toggleSideDrawer", Q_ARG(QString, QString("unknown")));
    QTest::qWait(30); snapshot("unknownDrawerIgnored");
    QMetaObject::invokeMethod(w, "toggleSideDrawer", Q_ARG(QString, QString("wifi")));
    QTest::qWait(240); snapshot("systemDrawerRoutesHome");
    QMetaObject::invokeMethod(w, "toggleSideDrawer", Q_ARG(QString, QString("wifi")));
    QTest::qWait(210);
    QMetaObject::invokeMethod(w, "toggle", Q_ARG(QVariant, QVariant("System")));
    QTest::qWait(240);
    QMetaObject::invokeMethod(w, "toggle", Q_ARG(QVariant, QVariant("Home")));
    QTest::qWait(240); snapshot("homeTabRestored");
    QMetaObject::invokeMethod(w, "toggleSideDrawer", Q_ARG(QString, QString("wifi")));
    QTest::qWait(210);
    auto password = w->findChild<QQuickItem*>("wifiPassword");
    if (!password) return 5;
    password->forceActiveFocus();
    QTest::keyClick(w, Qt::Key_Escape);
    QTest::qWait(30); snapshot("drawerEscape");
    QTest::keyClick(w, Qt::Key_Escape);
    QTest::qWait(30); snapshot("dashboardEscape");
    QTest::qWait(230); snapshot("drawerUnloadedAfterClose");
    dismiss(); QTest::qWait(370);
    toggle(); dismiss(); QTest::qWait(50); snapshot("earlyDismiss");
    dismiss(); QTest::qWait(370);
    toggle(); toggle(); QTest::qWait(370); snapshot("doubleToggle");
    QMetaObject::invokeMethod(w, "simulateMedia");
    QTest::qWait(400); snapshot("mediaRest");
    toggle(); QTest::qWait(400); snapshot("mediaDashboard");
    dismiss(); QTest::qWait(400); snapshot("mediaReturn");
    QMetaObject::invokeMethod(w, "osd"); snapshot("osdFromMedia");
    QMetaObject::invokeMethod(w, "osdVolume125"); snapshot("osdVolume125");
    QMetaObject::invokeMethod(w, "osdVolume150"); snapshot("osdVolume150");
    QMetaObject::invokeMethod(w, "osdBrightnessOverflow"); snapshot("osdBrightnessOverflow");
    QMetaObject::invokeMethod(w, "osdInvalid"); snapshot("osdInvalid");
    QMetaObject::invokeMethod(w, "notify", Q_ARG(QVariant, QVariant("Before dashboard")));
    snapshot("notificationReplacesOsd");
    QMetaObject::invokeMethod(w, "osd"); snapshot("notificationWinsOverOsd");
    toggle(); snapshot("dashboardClearsAlert");
    QMetaObject::invokeMethod(w, "notify", Q_ARG(QVariant, QVariant("During dashboard")));
    snapshot("notificationWhileDashboard");
    QTest::qWait(120);
    dismiss(); QTest::qWait(30); snapshot("dashboardClosingInput");
    QMetaObject::invokeMethod(w, "notify", Q_ARG(QVariant, QVariant("During closing")));
    snapshot("notificationWhileClosing");
    QTest::qWait(370); snapshot("dashboardClosedWithoutStaleAlert");
    QMetaObject::invokeMethod(w, "pin");
    QMetaObject::invokeMethod(w, "notify", Q_ARG(QVariant, QVariant("During pin")));
    QMetaObject::invokeMethod(w, "osd"); snapshot("pinnedSuppressesAlerts");
    QMetaObject::invokeMethod(w, "unpin"); snapshot("unpinnedRestoresMedia");
    QTest::qWait(370);
    QTest::mouseMove(w, QPoint(100, 500));
    QTest::mouseMove(w, QPoint(960, 16));
    QTest::qWait(70); snapshot("hoverBeforeDwell");
    QTest::qWait(170); snapshot("hoverAfterDwell");
    QTest::mouseMove(w, QPoint(100, 500));
    QTest::qWait(100); snapshot("hoverDuringGrace");
    QTest::mouseMove(w, QPoint(960, 16));
    QTest::qWait(40); snapshot("hoverReentered");
    QTest::mouseMove(w, QPoint(100, 500));
    QTest::qWait(270); snapshot("hoverAfterGrace");
    QTest::mouseMove(w, QPoint(960, 16));
    QTest::qWait(550);
    snapshot("hoverSettledBeforePin");
    auto pinButton = w->findChild<QQuickItem*>("mediaPinButton");
    if (!pinButton) return 6;
    auto pinCenter = pinButton->mapToScene(QPointF(pinButton->width() / 2, pinButton->height() / 2));
    QTest::mouseClick(w, Qt::LeftButton, Qt::NoModifier, pinCenter.toPoint());
    snapshot("hoverPinnedByClick");
    QTest::qWait(1130); snapshot("pinnedMediaProgressTick");
    QTest::mouseClick(w, Qt::LeftButton, Qt::NoModifier, QPoint(100, 500));
    QTest::qWait(300); snapshot("hoverDismissedInPlace");
    QTest::qWait(1130); snapshot("unpinnedMediaNoTicks");
    QTest::mouseMove(w, QPoint(960, 16));
    QTest::qWait(240); snapshot("hoverReopenedAfterExit");
    QMetaObject::invokeMethod(w, "pin");
    QMetaObject::invokeMethod(w, "unpin");
    QTest::qWait(310); snapshot("hoverDismissedUnderPointer");
    QTest::mouseMove(w, QPoint(100, 500));
    QTest::mouseMove(w, QPoint(960, 16));
    QTest::qWait(240); snapshot("hoverRearmedAfterExplicitDismiss");
    QTest::mouseMove(w, QPoint(100, 500));
    QTest::qWait(300);
    QMetaObject::invokeMethod(w, "notify", Q_ARG(QVariant, QVariant("First notification")));
    QTest::qWait(900);
    QMetaObject::invokeMethod(w, "notify", Q_ARG(QVariant, QVariant("Refreshed notification")));
    snapshot("notificationRefreshed");
    QTest::qWait(3300); snapshot("notificationBeforeExpiry");
    QTest::qWait(1000); snapshot("notificationAfterExpiry");
    QMetaObject::invokeMethod(w, "osd"); snapshot("osdClockStart");
    QTest::qWait(2500); snapshot("osdAfterExpiry");
    QTest::mouseMove(w, QPoint(100, 500));
    QMetaObject::invokeMethod(w, "osd");
    QTest::mouseMove(w, QPoint(960, 16));
    QTest::qWait(250); snapshot("hoverDuringAlert");
    QTest::qWait(2200);
    QTest::qWait(240); snapshot("hoverAfterAlert");
    QMetaObject::invokeMethod(w, "osd"); snapshot("hoverInterruptedByAlert");
    QMetaObject::invokeMethod(w, "clearAlert");
    QTest::qWait(90); snapshot("hoverAfterInterruptionBeforeDwell");
    QTest::qWait(180); snapshot("hoverAfterInterruptionDwell");
    QTest::mouseMove(w, QPoint(100, 500));
    QTest::qWait(320);
    QMetaObject::invokeMethod(w, "simulatePausedUntitledMedia");
    QTest::qWait(320); snapshot("pausedUntitledMedia");
    fprintf(stdout, "%s\n", QJsonDocument(results).toJson(QJsonDocument::Compact).constData());
    return 0;
}'''
        (base / 'main.cpp').write_text(cpp)
        built = subprocess.run(['c++', '-fPIC', str(base / 'main.cpp'), '-o',
                                str(base / 'check')] + flags.stdout.split(),
                               capture_output=True, text=True, timeout=30)
        if built.returncode:
            raise AssertionError(built.stderr)
        result = subprocess.run([str(base / 'check'), str(base / 'island/main.qml')],
                                env=environment(base), capture_output=True, text=True, timeout=40)
        if result.returncode:
            raise AssertionError(f'Qt harness exit {result.returncode}: {result.stdout}{result.stderr}')
        cls.rows = json.loads(result.stdout)
        cls.stderr = result.stderr
        # Optional artifact for reviewing the observed geometry, not a test dependency.
        if os.environ.get('DASHBOARD_MOTION_EVIDENCE'):
            Path(os.environ['DASHBOARD_MOTION_EVIDENCE']).write_text(
                json.dumps(cls.rows, indent=2) + '\n')

    def test_content_size_stays_fixed_during_motion(self):
        for name in ('opening45', 'opening100', 'opening200', 'closing45'):
            with self.subTest(frame=name):
                self.assertEqual((self.rows[name]['contentWidth'], self.rows[name]['contentHeight']),
                                 (760, 440), self.rows[name])
                self.assertTrue(self.rows[name]['viewportClips'], self.rows[name])

    def test_reveal_moves_and_fades_before_final_geometry(self):
        first, middle, opened = (self.rows[name] for name in ('opening45', 'opening100', 'opened'))
        self.assertLess(first['panelHeight'], middle['panelHeight'])
        self.assertLess(middle['panelHeight'], 440)
        self.assertLess(first['contentY'], 0, first)
        self.assertLess(first['contentY'], middle['contentY'])
        self.assertLess(first['contentOpacity'], middle['contentOpacity'])
        self.assertEqual((opened['panelWidth'], opened['panelHeight'], opened['panelY']),
                         (760, 440, 0))
        self.assertEqual((opened['contentY'], opened['contentOpacity']), (0, 1))
        self.assertNotIn('ReferenceError', self.stderr)
        self.assertNotIn('TypeError', self.stderr)
        self.assertNotIn('Binding loop', self.stderr)

    def test_close_finishes_faster_than_open(self):
        self.assertTrue(self.rows['closing45']['dashboardVisible'])
        self.assertLess(self.rows['closing45']['heightDuration'],
                        self.rows['opening45']['heightDuration'])
        self.assertLess(self.rows['closed230']['panelHeight'],
                        self.rows['closing45']['panelHeight'])
        # Software-rendered Qt tests can miss frames under CPU load.
        # Check the nominal close duration above, and the settled state with slack.
        self.assertFalse(self.rows['closed400']['dashboardVisible'], self.rows['closed400'])
        self.assertEqual(self.rows['closed400']['panelHeight'], 32)
        self.assertEqual(self.rows['closed400']['panelWidth'], 138)

    def test_reopening_during_close_reverses_without_reset(self):
        self.assertAlmostEqual(self.rows['beforeReopen']['panelHeight'],
                               self.rows['afterReopen']['panelHeight'], delta=1)
        self.assertTrue(self.rows['reopened']['dashboardVisible'], self.rows['reopened'])
        self.assertTrue(self.rows['reopened']['expanded'], self.rows['reopened'])
        self.assertEqual(self.rows['reopened']['panelHeight'], 440)

    def test_dismiss_cancels_pending_open(self):
        self.assertFalse(self.rows['earlyDismiss']['expanded'], self.rows['earlyDismiss'])
        self.assertFalse(self.rows['doubleToggle']['dashboardVisible'], self.rows['doubleToggle'])
        self.assertFalse(self.rows['doubleToggle']['expanded'], self.rows['doubleToggle'])

    def test_media_restored_after_dashboard(self):
        self.assertEqual(self.rows['mediaRest']['panelWidth'], 232)
        self.assertEqual(self.rows['mediaDashboard']['panelWidth'], 760)
        self.assertEqual(self.rows['mediaReturn']['panelWidth'], 232)
        self.assertEqual(self.rows['mediaReturn']['panelHeight'], 32)
        self.assertFalse(self.rows['mediaReturn']['dashboardVisible'])

    def test_sidecar_preserves_content_size(self):
        row = self.rows['drawerOpened']
        self.assertTrue(row['sideDrawerOpen'], row)
        self.assertEqual(row['drawerWidth'], 300)
        self.assertEqual((row['contentWidth'], row['contentHeight']), (760, 440))

    def test_unknown_drawer_is_ignored_and_non_home_drawer_returns_home(self):
        unknown = self.rows['unknownDrawerIgnored']
        self.assertEqual(unknown['tabName'], 'System')
        self.assertFalse(unknown['sideDrawerOpen'], unknown)
        routed = self.rows['systemDrawerRoutesHome']
        self.assertEqual(routed['tabName'], 'Home')
        self.assertTrue(routed['sideDrawerOpen'], routed)

    def test_dashboard_takes_focus_on_open_and_releases_it_on_close(self):
        self.assertTrue(self.rows['opened']['dashboardActiveFocus'], self.rows['opened'])
        self.assertFalse(self.rows['closing45']['dashboardActiveFocus'], self.rows['closing45'])

    def test_tab_switch_enters_smoothly_and_restores_interaction(self):
        entering = self.rows['systemTabEntering']
        settled = self.rows['systemTabSettled']
        self.assertEqual(entering['tabName'], 'System')
        self.assertGreater(entering['tabOffset'], 0.5, entering)
        self.assertGreater(entering['tabOpacity'], 0, entering)
        self.assertLess(entering['tabOpacity'], 0.9, entering)
        self.assertFalse(entering['tabInputEnabled'], entering)
        self.assertEqual((settled['tabOffset'], settled['tabOpacity']), (0, 1))
        self.assertTrue(settled['tabInputEnabled'], settled)
        self.assertEqual((settled['contentWidth'], settled['contentHeight']), (760, 440))
        self.assertEqual(self.rows['homeTabRestored']['tabName'], 'Home')
        self.assertEqual(self.rows['homeTabRestored']['tabOpacity'], 1)

    def test_tab_switch_dismisses_stale_drawer_and_releases_input(self):
        entering = self.rows['systemTabEntering']
        settled = self.rows['systemTabSettled']
        self.assertFalse(entering['sideDrawerOpen'], entering)
        self.assertGreater(entering['drawerWidth'], 0, entering)
        self.assertFalse(entering['drawerHitTest'], entering)
        self.assertEqual(settled['drawerWidth'], 0)
        self.assertFalse(settled['wifiLoaded'])
        self.assertFalse(self.rows['homeTabRestored']['sideDrawerOpen'])

    def test_escape_from_focused_drawer_field_closes_drawer_then_dashboard(self):
        self.assertTrue(self.rows['drawerOpened']['sideDrawerOpen'])
        self.assertFalse(self.rows['drawerEscape']['sideDrawerOpen'])
        self.assertTrue(self.rows['drawerEscape']['expanded'])
        self.assertFalse(self.rows['dashboardEscape']['expanded'])

    def test_hover_starts_when_alert_expires_under_stationary_pointer(self):
        self.assertTrue(self.rows['hoverDuringAlert']['hoverPointer'])
        self.assertFalse(self.rows['hoverDuringAlert']['hoverActive'])
        self.assertEqual(self.rows['hoverAfterAlert']['mode'], 'expanded')
        self.assertTrue(self.rows['hoverAfterAlert']['hoverActive'])

    def test_alert_interrupts_media_hover_and_requires_fresh_dwell(self):
        self.assertEqual(self.rows['hoverInterruptedByAlert']['mode'], 'volume')
        self.assertFalse(self.rows['hoverInterruptedByAlert']['hoverActive'])
        self.assertEqual(self.rows['hoverAfterInterruptionBeforeDwell']['mode'], 'media')
        self.assertFalse(self.rows['hoverAfterInterruptionBeforeDwell']['hoverActive'])
        self.assertEqual(self.rows['hoverAfterInterruptionDwell']['mode'], 'expanded')
        self.assertTrue(self.rows['hoverAfterInterruptionDwell']['hoverActive'])

    def test_paused_player_without_title_remains_accessible(self):
        self.assertEqual(self.rows['pausedUntitledMedia']['mode'], 'media')
        self.assertEqual(self.rows['pausedUntitledMedia']['panelWidth'], 232)

    def test_media_position_updates_only_while_expanded(self):
        self.assertGreater(self.rows['pinnedMediaProgressTick']['positionTickCount'],
                           self.rows['hoverPinnedByClick']['positionTickCount'])
        self.assertEqual(self.rows['unpinnedMediaNoTicks']['positionTickCount'],
                         self.rows['hoverDismissedInPlace']['positionTickCount'])

    def test_drawer_uses_overlay_at_1080px(self):
        row = self.rows['drawer1080Viewport']
        self.assertEqual(row['contentWidth'], 760)
        self.assertTrue(row['drawerOverlay'])
        self.assertEqual(row['drawerWidth'], row['dashboardCardWidth'])
        self.assertGreaterEqual(row['drawerX'], 0)
        self.assertLessEqual(row['drawerX'] + row['drawerWidth'], 1080)

    def test_responsive_dashboard_geometry_at_narrow_viewports(self):
        for name, screen_width, width, height, overlay in (
                ('drawer1280Viewport', 1280, 760, 440, False),
                ('drawer960Viewport', 960, 760, 440, True),
                ('drawer768Viewport', 768, 730, 440, True),
                ('drawer640Viewport', 640, 602, 440, True),
                ('drawer640x360Viewport', 640, 602, 344, True)):
            row = self.rows[name]
            self.assertEqual((row['dashboardCardWidth'], row['dashboardCardHeight']), (width, height), row)
            self.assertEqual(row['drawerOverlay'], overlay, row)
            self.assertGreaterEqual(row['drawerX'], 0, row)
            self.assertLessEqual(row['drawerX'] + row['drawerWidth'], screen_width, row)

        normal = self.rows['drawer1280Viewport']
        self.assertEqual(normal['homeLayoutColumns'], 3, normal)
        self.assertEqual(normal['homeContentHeight'], 370, normal)
        narrow = self.rows['drawer768Viewport']
        self.assertEqual(narrow['homeLayoutColumns'], 2, narrow)
        self.assertEqual(narrow['homeContentHeight'], 650, narrow)
        self.assertLessEqual(narrow['tabContentWidth'], narrow['contentWidth'], narrow)
        self.assertGreater(narrow['tabContentHeight'], narrow['tabViewportHeight'], narrow)
        self.assertTrue(narrow['tabScrollInteractive'], narrow)

    def test_home_content_unloads_when_dashboard_closes(self):
        self.assertTrue(self.rows['opening45']['homeLoaded'])
        self.assertTrue(self.rows['closing45']['homeLoaded'])
        self.assertFalse(self.rows['closed400']['homeLoaded'])
        self.assertTrue(self.rows['reopened']['homeLoaded'])
        self.assertFalse(self.rows['mediaReturn']['homeLoaded'])

    def test_inactive_side_drawers_are_unloaded_after_close_animation(self):
        self.assertFalse(self.rows['opened']['wifiLoaded'])
        self.assertFalse(self.rows['opened']['bluetoothLoaded'])
        self.assertTrue(self.rows['drawerOpened']['wifiLoaded'])
        self.assertFalse(self.rows['drawerOpened']['bluetoothLoaded'])
        self.assertFalse(self.rows['bluetoothDrawerOpened']['wifiLoaded'])
        self.assertTrue(self.rows['bluetoothDrawerOpened']['bluetoothLoaded'])
        self.assertTrue(self.rows['wifiDrawerRestored']['wifiLoaded'])
        self.assertFalse(self.rows['wifiDrawerRestored']['bluetoothLoaded'])
        self.assertTrue(self.rows['drawerEscape']['wifiLoaded'])
        self.assertFalse(self.rows['dashboardEscape']['sideDrawerOpen'])
        self.assertFalse(self.rows['drawerUnloadedAfterClose']['wifiLoaded'])

    def test_osd_amplification_retains_value_but_clamps_visual_fill(self):
        amplified = self.rows['osdVolume125']
        self.assertEqual(amplified['osdType'], 'volume')
        self.assertEqual(amplified['osdValue'], 1.25)
        self.assertEqual(amplified['osdFillValue'], 1)
        self.assertEqual(self.rows['osdVolume150']['osdValue'], 1.5)
        self.assertEqual(self.rows['osdVolume150']['osdFillValue'], 1)
        self.assertEqual(self.rows['osdBrightnessOverflow']['osdType'], 'brightness')
        self.assertEqual(self.rows['osdBrightnessOverflow']['osdValue'], 1)
        self.assertEqual(self.rows['osdBrightnessOverflow']['osdFillValue'], 1)
        self.assertEqual(self.rows['osdInvalid']['osdValue'], 0)
        self.assertEqual(self.rows['osdInvalid']['osdFillValue'], 0)

    def test_transient_priority_and_lifetimes(self):
        self.assertEqual(self.rows['osdFromMedia']['alertType'], 'volume')
        self.assertEqual(self.rows['osdFromMedia']['alertTimeout'], 2200)
        self.assertEqual(self.rows['notificationReplacesOsd']['alertType'], 'notification')
        self.assertEqual(self.rows['notificationReplacesOsd']['alertTimeout'], 4000)
        self.assertEqual(self.rows['notificationWinsOverOsd']['alertSummary'], 'Before dashboard')

    def test_transient_timers_expire_and_new_notification_restarts_clock(self):
        self.assertEqual(self.rows['notificationRefreshed']['alertSummary'], 'Refreshed notification')
        self.assertEqual(self.rows['notificationRefreshed']['alertTimeout'], 4000)
        self.assertTrue(self.rows['notificationBeforeExpiry']['alertTimerRunning'])
        self.assertEqual(self.rows['notificationBeforeExpiry']['alertType'], 'notification')
        self.assertFalse(self.rows['notificationAfterExpiry']['alertTimerRunning'])
        self.assertEqual(self.rows['notificationAfterExpiry']['alertType'], '')
        self.assertEqual(self.rows['osdClockStart']['alertTimeout'], 2200)
        self.assertTrue(self.rows['osdClockStart']['alertTimerRunning'])
        self.assertFalse(self.rows['osdAfterExpiry']['alertTimerRunning'])
        self.assertEqual(self.rows['osdAfterExpiry']['mode'], 'media')

    def test_notifications_do_not_resurface_after_modal_close(self):
        for name in ('dashboardClearsAlert', 'notificationWhileDashboard',
                     'notificationWhileClosing', 'dashboardClosedWithoutStaleAlert',
                     'pinnedSuppressesAlerts', 'unpinnedRestoresMedia'):
            with self.subTest(frame=name):
                self.assertEqual(self.rows[name]['alertType'], '', self.rows[name])
                self.assertFalse(self.rows[name]['alertTimerRunning'], self.rows[name])
        self.assertEqual(self.rows['dashboardClosedWithoutStaleAlert']['mode'], 'media')
        self.assertEqual(self.rows['unpinnedRestoresMedia']['mode'], 'media')

    def test_fullscreen_input_releases_when_dashboard_begins_closing(self):
        self.assertTrue(self.rows['dashboardClearsAlert']['scrimInteractive'])
        self.assertTrue(self.rows['dashboardClosingInput']['dashboardVisible'])
        self.assertFalse(self.rows['dashboardClosingInput']['scrimInteractive'])
        self.assertTrue(self.rows['pinnedSuppressesAlerts']['scrimInteractive'])
        self.assertFalse(self.rows['unpinnedRestoresMedia']['scrimInteractive'])

    def test_media_hover_dwell_grace_and_reentry(self):
        expected = {
            'hoverBeforeDwell': (True, False),
            'hoverAfterDwell': (True, True),
            'hoverDuringGrace': (False, True),
            'hoverReentered': (True, True),
            'hoverAfterGrace': (False, False),
        }
        for name, (pointer, preview) in expected.items():
            with self.subTest(frame=name):
                self.assertEqual(self.rows[name]['hoverPointer'], pointer, self.rows[name])
                self.assertEqual(self.rows[name]['hoverActive'], preview, self.rows[name])

    def test_media_pin_outside_dismiss_and_hover_rearms_after_exit(self):
        self.assertEqual(self.rows['hoverSettledBeforePin']['panelHeight'], 156)
        self.assertTrue(self.rows['hoverPinnedByClick']['pinned'], self.rows['hoverSettledBeforePin'])
        self.assertTrue(self.rows['hoverPinnedByClick']['scrimInteractive'])
        self.assertFalse(self.rows['hoverDismissedInPlace']['pinned'])
        self.assertFalse(self.rows['hoverDismissedInPlace']['hoverActive'])
        self.assertFalse(self.rows['hoverDismissedInPlace']['scrimInteractive'])
        self.assertTrue(self.rows['hoverReopenedAfterExit']['hoverActive'])
        self.assertTrue(self.rows['hoverDismissedUnderPointer']['hoverPointer'])
        self.assertFalse(self.rows['hoverDismissedUnderPointer']['hoverActive'])
        self.assertEqual(self.rows['hoverDismissedUnderPointer']['mode'], 'media')
        self.assertTrue(self.rows['hoverRearmedAfterExplicitDismiss']['hoverActive'])


if __name__ == '__main__':
    unittest.main()
