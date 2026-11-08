"""Isolated alias lookup and native Qt pointer/key regressions; no desktop IPC."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'config/quickshell/wallpaper-switcher/shell.qml'


def environment(base):
    return dict(os.environ, HOME=str(base), XDG_CONFIG_HOME=str(base / '.config'),
                XDG_CACHE_HOME=str(base / 'cache'), XDG_STATE_HOME=str(base / 'state'),
                XDG_RUNTIME_DIR=str(base), QT_QPA_PLATFORM='offscreen',
                QT_QUICK_BACKEND='software', QT_QPA_PLATFORMTHEME='generic',
                QT_STYLE_OVERRIDE='Fusion', QML_DISABLE_DISK_CACHE='1', WAYLAND_DISPLAY='', DISPLAY='')


class QmlInputTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('node') and shutil.which('find'), 'node and find required')
    def test_initial_alias_for_linked_root_and_external_image(self):
        source = SOURCE.read_text()
        command = re.search(r'id: currentWallpaperQuery\s+command: (\[.*?\])', source, re.S).group(1)
        for linked_root in (True, False):
            with self.subTest(linked_root=linked_root), tempfile.TemporaryDirectory() as temp:
                base = Path(temp)
                library = base / 'Ảnh/Wallpaper'
                library.parent.mkdir()
                external = base / 'external'
                external.mkdir()
                if linked_root:
                    library.symlink_to(external, target_is_directory=True)
                else:
                    library.mkdir()
                target = external / 'zzz whitespace\n %.png'
                target.write_bytes(b'fixture')
                alias = library / target.name
                if not linked_root:
                    alias.symlink_to(target)
                (library / 'aaa.png').write_bytes(b'other')
                config = base / '.config/hypr'
                config.mkdir(parents=True)
                (config / 'current_wallpaper').symlink_to(target)
                js = 'const root={configHome:process.env.XDG_CONFIG_HOME}; const Quickshell={env:k=>process.env[k]}; console.log(JSON.stringify(' + command + '));'
                argv = json.loads(subprocess.check_output(['node', '-e', js], env=environment(base), text=True))
                result = subprocess.run(argv, capture_output=True, timeout=3)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, os.fsencode(alias) + b'\0')

    @unittest.skipUnless(shutil.which('c++') and shutil.which('pkg-config'), 'Qt development tools required')
    def test_native_blank_card_drag_and_escape(self):
        flags = subprocess.run(['pkg-config', '--cflags', '--libs', 'Qt6Quick', 'Qt6Qml', 'Qt6Test'], capture_output=True, text=True)
        if flags.returncode:
            self.skipTest('Qt6 Quick/Qml/Test development packages unavailable')
        source = SOURCE.read_text()
        # Use the actual input handlers, card hit testing, geometry and delegates.
        content = source[source.index('    // Bấm ra ngoài'):source.index('    // Hoạt ảnh xuất hiện')] if '    // Bấm ra ngoài' in source else source[source.index('    // Khung chứa nội dung'):source.index('    // Hoạt ảnh xuất hiện')]
        props = source[source.index('    readonly property real rowWidth:'):source.index('    function transition(')]
        qml = '''import QtQuick
import QtQuick.Window
import QtQuick.Effects
import QtQuick.Shapes
Window { id: root; width: 800; height: 600; visible: true
property bool closing: false
property int closed: 0
property int applied: 0
property int selected: carousel.currentIndex
property var palette: ({})
property real panelOpacity: 1
property var previewSwatches: []
property var applyState: ({phase: "idle"})
function closeShell() {closed++;}
function applyCurrent() {applied++;}
function syncSelection() {}
function statusText() {return "";}
function thumbnailSource() {return "";}
function resetInput() {closed=0; applied=0; carousel.currentIndex=0; contentContainer.forceActiveFocus();}
QtObject {id: enterAnimation; function start() {contentContainer.opacity=1; contentContainer.scale=1;}}
ListModel {id: displayModel; Component.onCompleted: {for(var i=0;i<8;i++) append({thumbKey:String(i),thumbUrl:"",fileUrl:""});}}
''' + props + content + '\n}'
        cpp = r'''
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QTest>
#include <QTimer>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <cstdio>
int main(int argc,char **argv) {
 QGuiApplication app(argc,argv); QQmlApplicationEngine engine;
 engine.load(QUrl::fromLocalFile(argv[1])); if(engine.rootObjects().isEmpty()) return 2;
 auto w=qobject_cast<QQuickWindow*>(engine.rootObjects().first());
 QTimer::singleShot(300,[&](){
  w->requestActivate(); QJsonArray results;
  auto reset=[&](){QMetaObject::invokeMethod(w,"resetInput");QTest::qWait(350);};
  auto save=[&](){QJsonObject r;for(auto k:{"closed","applied","selected"})r[k]=w->property(k).toInt();results.append(r);};
  reset();QTest::mouseClick(w,Qt::LeftButton,Qt::NoModifier,QPoint(10,10));save();
  reset();QTest::mouseClick(w,Qt::LeftButton,Qt::NoModifier,QPoint(136,300));save();
  reset();QTest::mouseClick(w,Qt::LeftButton,Qt::NoModifier,QPoint(400,300));save();
  reset();QTest::mousePress(w,Qt::LeftButton,Qt::NoModifier,QPoint(400,300));
  for(int x=420;x<=600;x+=20)QTest::mouseMove(w,QPoint(x,300),20);
  QTest::mouseRelease(w,Qt::LeftButton,Qt::NoModifier,QPoint(600,300));QTest::qWait(200);save();
  reset();QTest::keyClick(w,Qt::Key_Escape);save();
  fprintf(stdout,"%s\n",QJsonDocument(results).toJson(QJsonDocument::Compact).constData());app.quit();
 });return app.exec();
}'''
        with tempfile.TemporaryDirectory(prefix='qml-input-test-') as temp:
            base = Path(temp)
            (base / 'main.qml').write_text(qml)
            (base / 'main.cpp').write_text(cpp)
            built = subprocess.run(['c++', '-fPIC', str(base / 'main.cpp'), '-o', str(base / 'check')] + flags.stdout.split(), capture_output=True, text=True, timeout=30)
            self.assertEqual(built.returncode, 0, built.stderr)
            result = subprocess.run([str(base / 'check'), str(base / 'main.qml')], env=environment(base), capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn('ReferenceError', result.stderr)
            rows = json.loads(result.stdout)
            self.assertEqual(rows[0]['closed'], 1, (rows, result.stderr))
            self.assertEqual((rows[1]['closed'], rows[1]['applied']), (0, 0), rows)
            self.assertNotEqual(rows[1]['selected'], 0, rows)
            self.assertEqual((rows[2]['closed'], rows[2]['applied']), (0, 1), rows)
            self.assertEqual((rows[3]['closed'], rows[3]['applied']), (0, 0), rows)
            self.assertEqual(rows[4]['closed'], 1, rows)
