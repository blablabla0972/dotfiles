"""Exercise the real Qt Controls action-menu transitions without desktop IPC."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from test_qml_input import environment

ROOT = Path(__file__).resolve().parents[1]
SHELL = ROOT / 'config/quickshell/rice-shell'


@unittest.skipUnless(shutil.which('c++') and shutil.which('pkg-config'),
                     'Qt development tools required')
class ActionMenuMotionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        flags = subprocess.run(['pkg-config', '--cflags', '--libs', 'Qt6Quick',
                                'Qt6Qml', 'Qt6Test'], capture_output=True, text=True)
        if flags.returncode:
            raise unittest.SkipTest('Qt6 Quick/Qml/Test development packages unavailable')
        cls.temp = tempfile.TemporaryDirectory(prefix='action-menu-motion-')
        cls.addClassCleanup(cls.temp.cleanup)
        base = Path(cls.temp.name)
        for name in ('dashboard', 'theme'):
            (base / name).mkdir()
        for name in ('ActionMenu.qml', 'ActionMenuItem.qml'):
            shutil.copy2(SHELL / 'dashboard' / name, base / 'dashboard' / name)
        (base / 'theme/qmldir').write_text('singleton Tokens 1.0 Tokens.qml\n')
        (base / 'theme/Tokens.qml').write_text(
            'pragma Singleton\nimport QtQuick\nQtObject {\n' + ''.join(
                f'property color {name}: "#8899aa"\n'
                for name in ('surface', 'outline', 'accent', 'text_primary', 'text_secondary'))
            + '}\n')
        (base / 'main.qml').write_text('''import QtQuick
import QtQuick.Window
import "dashboard"
Window {
    width: 640; height: 480; visible: true
    property real menuScale: menu.scale
    property real menuOpacity: menu.opacity
    property bool menuVisible: menu.visible
    property bool menuOpened: menu.opened
    property bool menuFocus: menu.activeFocus
    property real contentWidth: menu.contentItem.width
    property real contentHeight: menu.contentItem.height
    property int triggeredCount: 0
    function openMenu() { menu.requestOpen(); }
    function closeMenu() { menu.close(); }
    ActionMenu {
        id: menu
        x: 180; y: 100
        ActionMenuItem { text: "Details"; onTriggered: triggeredCount++ }
        ActionMenuItem { text: "Forget saved profiles…" }
    }
}
''')
        (base / 'main.cpp').write_text(r'''
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QTest>
#include <QJsonDocument>
#include <QJsonObject>
#include <cstdio>
int main(int argc, char **argv) {
    QGuiApplication app(argc, argv);
    QQmlApplicationEngine engine;
    engine.load(QUrl::fromLocalFile(argv[1]));
    if (engine.rootObjects().isEmpty()) return 2;
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    QTest::qWait(50);
    QJsonObject result;
    auto snapshot = [&](const char *name) {
        QJsonObject row;
        for (auto key : {"menuScale", "menuOpacity", "contentWidth", "contentHeight"})
            row[key] = window->property(key).toDouble();
        for (auto key : {"menuVisible", "menuOpened", "menuFocus"})
            row[key] = window->property(key).toBool();
        result[name] = row;
    };
    auto open = [&] { QMetaObject::invokeMethod(window, "openMenu"); };
    auto close = [&] { QMetaObject::invokeMethod(window, "closeMenu"); };
    open();
    double peak = 0, minimumOpacity = 1, maximumOpacity = 0;
    QTest::qWait(30); snapshot("entering");
    for (int frame = 0; frame < 70; ++frame) {
        QTest::qWait(12);
        peak = qMax(peak, window->property("menuScale").toDouble());
        minimumOpacity = qMin(minimumOpacity, window->property("menuOpacity").toDouble());
        maximumOpacity = qMax(maximumOpacity, window->property("menuOpacity").toDouble());
    }
    snapshot("opened");
    result["peak"] = peak;
    result["minimumOpacity"] = minimumOpacity;
    result["maximumOpacity"] = maximumOpacity;
    close(); QTest::qWait(60); snapshot("exiting");
    const double before = window->property("menuScale").toDouble();
    open(); snapshot("reopening");
    result["reopenJump"] = qAbs(window->property("menuScale").toDouble() - before);
    QTest::qWaitFor([&] { return window->property("menuOpened").toBool(); }, 1500);
    snapshot("reopened");
    QTest::keyClick(window, Qt::Key_Escape);
    if (!QTest::qWaitFor([&] { return !window->property("menuVisible").toBool(); }, 1000))
        return 4;
    snapshot("closed");
    open(); QTest::qWait(30); close();
    if (!QTest::qWaitFor([&] { return !window->property("menuVisible").toBool(); }, 1000))
        return 5;
    snapshot("earlyDismiss");
    open();
    if (!QTest::qWaitFor([&] { return window->property("menuOpened").toBool(); }, 1500)) {
        snapshot("selectionOpenTimeout");
        fprintf(stderr, "%s\n", QJsonDocument(result).toJson(QJsonDocument::Compact).constData());
        return 6;
    }
    QTest::keyClick(window, Qt::Key_Down);
    QTest::keyClick(window, Qt::Key_Return);
    if (!QTest::qWaitFor([&] { return !window->property("menuVisible").toBool(); }, 1000))
        return 7;
    snapshot("selected");
    result["triggeredCount"] = window->property("triggeredCount").toInt();
    open(); close();
    if (!QTest::qWaitFor([&] { return !window->property("menuVisible").toBool(); }, 1000))
        return 8;
    snapshot("immediateDismiss");
    fprintf(stdout, "%s\n", QJsonDocument(result).toJson(QJsonDocument::Compact).constData());
}
''')
        built = subprocess.run(['c++', '-fPIC', str(base / 'main.cpp'), '-o',
                                str(base / 'check')] + flags.stdout.split(),
                               capture_output=True, text=True, timeout=30)
        if built.returncode:
            raise AssertionError(built.stderr)
        result = subprocess.run([str(base / 'check'), str(base / 'main.qml')],
                                env=environment(base), capture_output=True, text=True, timeout=12)
        if result.returncode:
            raise AssertionError(f'Qt harness exit {result.returncode}: {result.stdout}{result.stderr}')
        cls.rows = json.loads(result.stdout)
        cls.stderr = result.stderr

    def test_menu_has_a_restrained_spring_overshoot(self):
        self.assertGreater(self.rows['peak'], 1.001, self.rows)
        self.assertLess(self.rows['peak'], 1.02, self.rows)
        self.assertGreaterEqual(self.rows['minimumOpacity'], 0)
        self.assertLessEqual(self.rows['maximumOpacity'], 1)
        self.assertTrue(self.rows['opened']['menuOpened'])
        self.assertEqual(self.rows['opened']['menuScale'], 1)
        self.assertEqual(self.rows['opened']['menuOpacity'], 1)

    def test_exit_contracts_before_hiding_and_releases_focus(self):
        self.assertTrue(self.rows['exiting']['menuVisible'])
        self.assertLess(self.rows['exiting']['menuScale'], 0.999)
        self.assertLess(self.rows['exiting']['menuOpacity'], 1)
        for name in ('closed', 'earlyDismiss', 'immediateDismiss'):
            self.assertFalse(self.rows[name]['menuVisible'], self.rows[name])
            self.assertFalse(self.rows[name]['menuFocus'], self.rows[name])

    def test_reopen_during_exit_does_not_reset_scale(self):
        self.assertLess(self.rows['reopenJump'], 0.001, self.rows)
        self.assertTrue(self.rows['reopened']['menuOpened'])
        self.assertEqual(self.rows['reopened']['menuScale'], 1)

    def test_keyboard_selection_and_escape_keep_native_menu_behavior(self):
        self.assertEqual(self.rows['triggeredCount'], 1)
        for name in ('closed', 'selected'):
            self.assertFalse(self.rows[name]['menuVisible'], self.rows[name])
            self.assertFalse(self.rows[name]['menuFocus'], self.rows[name])

    def test_content_dimensions_do_not_reflow_during_motion(self):
        opened = self.rows['opened']
        for name in ('entering', 'exiting', 'reopening'):
            self.assertEqual(self.rows[name]['contentWidth'], opened['contentWidth'])
            self.assertEqual(self.rows[name]['contentHeight'], opened['contentHeight'])
        self.assertNotIn('ReferenceError', self.stderr)
        self.assertNotIn('TypeError', self.stderr)
        self.assertNotIn('Binding loop', self.stderr)
