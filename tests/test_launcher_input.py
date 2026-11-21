"""Exercise the real launcher tap routing and keyboard handlers under native Qt."""
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

from test_qml_input import environment

ROOT = Path(__file__).resolve().parents[1]
LAUNCHER = ROOT / 'config/quickshell/rice-shell/launcher'


@unittest.skipUnless(shutil.which('c++') and shutil.which('pkg-config'), 'Qt development tools required')
class LauncherInputTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        flags = subprocess.run(['pkg-config', '--cflags', '--libs', 'Qt6Quick', 'Qt6Qml', 'Qt6Test'],
                               capture_output=True, text=True)
        if flags.returncode:
            raise unittest.SkipTest('Qt development packages unavailable')
        cls.temp = tempfile.TemporaryDirectory(prefix='launcher-input-')
        cls.addClassCleanup(cls.temp.cleanup)
        base = Path(cls.temp.name)
        (base / 'launcher').mkdir()
        (base / 'theme').mkdir()
        for script in LAUNCHER.glob('*.js'):
            shutil.copy2(script, base / 'launcher')
        (base / 'launcher/LauncherCalculator.qml').write_text('''
            import QtQuick
            import "QuickActions.js" as QuickActions
            Item {
                property bool active
                property string expression
                readonly property var result: QuickActions.calculate(expression)
            }
        ''')
        (base / 'theme/qmldir').write_text('singleton Tokens 1.0 Tokens.qml\n')
        roles = ('background', 'surface', 'surface_high', 'outline', 'accent', 'on_accent',
                 'text_primary', 'text_secondary')
        (base / 'theme/Tokens.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject {\n'
            + '\n'.join('property color ' + role + ': "#888888"' for role in roles)
            + '\nproperty real panelOpacity: 1\n}')
        source = (LAUNCHER / 'Launcher.qml').read_text()
        source = source.replace('import Quickshell\n', 'import QtQuick.Window\n')
        source = source.replace('import Quickshell.Wayland\n', '')
        source = source.replace('PanelWindow {', 'Window {', 1)
        source = re.sub(r'^    (?:required property ShellScreen targetScreen|screen: targetScreen|'
                        r'exclusiveZone:.*|WlrLayershell\..*)\n', '', source, flags=re.M)
        source = re.sub(r'    anchors \{.*?\n    \}\n', '', source, count=1, flags=re.S)
        source = re.sub(r'    mask: Region \{.*?\n    \}\n', '', source, count=1, flags=re.S)
        source = re.sub(r'    readonly property var allApps:.*\n',
                        '    readonly property var allApps: testEntries\n', source)
        source = source.replace('Quickshell.', 'fakeShell.')
        source = source.replace('id: launcherWindow', '''id: launcherWindow
    width: 900; height: 760
    property int launches: 0
    property int resultCount: filteredApps.length
    property int copies: 0
    property string copied: ""
    property int actions: 0
    property string firedAction: ""
    onCopyResultRequested: (result) => { copies++; copied = result; }
    onQuickActionRequested: (action) => { actions++; firedAction = action; }
    property var testEntries: [
        {id:"Alacritty", name:"Alacritty", command:["alacritty"], execute:function(){}},
        {id:"kitty", name:"kitty", command:["kitty"], execute:function(){}}
    ]
    QtObject { id: fakeShell
        function env(name) { return name === "HOME" ? "/tmp" : "kitty"; }
        function execDetached(context) { launcherWindow.launches++; }
        function iconPath(name) { return ""; }
    }
''', 1)
        source = source.replace('id: searchInput', 'id: searchInput\nobjectName: "launcherSearch"', 1)
        source = source.replace('id: appDelegate', 'id: appDelegate\nobjectName: "appRow" + index', 1)
        (base / 'launcher/main.qml').write_text(source)
        cpp = r'''
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QQuickItem>
#include <QTest>
#include <QJsonObject>
#include <QJsonDocument>
#include <functional>
#include <cstdio>
int main(int argc, char **argv) {
 QGuiApplication app(argc, argv); QQmlApplicationEngine engine;
 engine.load(QUrl::fromLocalFile(argv[1])); if(engine.rootObjects().isEmpty()) return 2;
 auto w=qobject_cast<QQuickWindow*>(engine.rootObjects().first());
 std::function<QQuickItem*(QQuickItem*,QString)> findItem = [&](QQuickItem* item, QString name)->QQuickItem* {
   if(item->objectName()==name) return item;
   for(auto child:item->childItems()) if(auto found=findItem(child,name)) return found;
   return nullptr;
 };
 auto open=[&](){QMetaObject::invokeMethod(w,"toggle"); QTest::qWait(220);};
 QJsonObject rows;
 open(); auto row=findItem(w->contentItem(),"appRow0"); if(!row) return 3;
 auto center=row->mapToScene(QPointF(row->width()/2, row->height()/2));
 QTest::mouseClick(w,Qt::LeftButton,Qt::NoModifier,center.toPoint()); QTest::qWait(140);
 rows["mouseLaunches"]=w->property("launches").toInt(); rows["closedAfterLaunch"]=!w->isVisible();
 if(w->isVisible()) {QMetaObject::invokeMethod(w,"dismiss");QTest::qWait(140);}
 open(); auto search=findItem(w->contentItem(),"launcherSearch"); if(!search) return 4;
 center=search->mapToScene(QPointF(search->width()/2,search->height()/2));
 QTest::mouseClick(w,Qt::LeftButton,Qt::NoModifier,center.toPoint());QTest::qWait(140);
 rows["searchClickStaysOpen"]=w->isVisible();
 if(!w->isVisible()) open();
 for(auto key : {Qt::Key_K,Qt::Key_I,Qt::Key_T,Qt::Key_T,Qt::Key_Y}) QTest::keyClick(w,key);
 rows["searchResults"]=w->property("resultCount").toInt();
 QTest::keyClick(w,Qt::Key_Return);QTest::keyClick(w,Qt::Key_Return);QTest::qWait(140);
 rows["totalLaunches"]=w->property("launches").toInt();
 open();QTest::mouseClick(w,Qt::LeftButton,Qt::NoModifier,QPoint(4,4));QTest::qWait(140);
 rows["outsideCloses"]=!w->isVisible();
 open();QTest::keyClick(w,Qt::Key_Escape);QTest::qWait(140);
 rows["escapeCloses"]=!w->isVisible();
 open();
 search->setProperty("text", "= 1/0");
 QTest::keyClick(w,Qt::Key_Return);
 rows["invalidCopies"]=w->property("copies").toInt();
 search->setProperty("text", "= (1+2)*-3");
 rows["copiesBeforeEnter"]=w->property("copies").toInt();
 QTest::keyClick(w,Qt::Key_Enter);QTest::keyClick(w,Qt::Key_Return);
 rows["copies"]=w->property("copies").toInt();
 rows["copied"]=w->property("copied").toString();
 QTest::qWait(525);
 search->setProperty("text", ":volume");
 rows["actionsBeforeEnter"]=w->property("actions").toInt();
 QTest::keyClick(w,Qt::Key_Down);
 QTest::keyClick(w,Qt::Key_Return);QTest::keyClick(w,Qt::Key_Return);
 rows["actions"]=w->property("actions").toInt();
 rows["action"]=w->property("firedAction").toString();
 QTest::keyClick(w,Qt::Key_Escape);QTest::qWait(140);
 rows["quickEscapeCloses"]=!w->isVisible();
 puts(QJsonDocument(rows).toJson(QJsonDocument::Compact).constData());
}
'''
        (base / 'probe.cpp').write_text(cpp)
        build = subprocess.run(['c++', '-std=c++17', '-fPIC', str(base / 'probe.cpp'),
                                '-o', str(base / 'probe'), *flags.stdout.split()],
                               capture_output=True, text=True)
        if build.returncode:
            raise AssertionError(build.stderr[-1800:])
        result = subprocess.run([str(base / 'probe'), str(base / 'launcher/main.qml')],
                                capture_output=True, text=True, env=environment(base), timeout=12)
        if result.returncode:
            raise AssertionError(f'exit={result.returncode}: {result.stderr[-1800:]}')
        cls.rows = json.loads(result.stdout)
        cls.stderr = result.stderr

    def test_mouse_launch_is_not_swallowed_by_the_scrim(self):
        self.assertEqual(self.rows['mouseLaunches'], 1, self.rows)
        self.assertTrue(self.rows['closedAfterLaunch'])

    def test_clicking_search_keeps_it_open_and_keyboard_launch_is_once(self):
        self.assertTrue(self.rows['searchClickStaysOpen'], self.rows)
        self.assertEqual(self.rows['searchResults'], 1)
        self.assertEqual(self.rows['totalLaunches'], 2)

    def test_outside_click_and_escape_dismiss(self):
        self.assertTrue(self.rows['outsideCloses'])
        self.assertTrue(self.rows['escapeCloses'])
        for error in ('ReferenceError', 'TypeError', 'Binding loop'):
            self.assertNotIn(error, self.stderr)

    def test_quick_modes_require_explicit_activation(self):
        self.assertEqual(self.rows['invalidCopies'], 0)
        self.assertEqual(self.rows['copiesBeforeEnter'], 0)
        self.assertEqual(self.rows['copies'], 1)
        self.assertEqual(self.rows['copied'], '-9')
        self.assertEqual(self.rows['actionsBeforeEnter'], 0)
        self.assertEqual(self.rows['actions'], 1)
        self.assertEqual(self.rows['action'], 'volume-down')
        self.assertTrue(self.rows['quickEscapeCloses'])
