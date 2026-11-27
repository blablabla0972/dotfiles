import os
import re
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class WorkspacePreviewTest(unittest.TestCase):
    def test_preview_geometry_is_scoped_to_native_capture(self):
        source = Path(__file__).resolve().parents[1] / "src/cod29/plugin_entry.cpp"
        code = source.read_text()
        body = code.split("static bool renderCard(", 1)[1].split("static void schedulePreview(", 1)[0]
        self.assertIn("Render::eSceneMode::WORKSPACE_WITH_SHELL", body)
        self.assertLess(body.index("draggedGeometry.emplace("), body.index("g_renderWorkspace("))
        self.assertLess(body.index("g_renderWorkspace("), body.index("renderer->endRender()"))

        match = re.search(r"static void updatePreview\w+\(.*?\nclass PreviewWindowGeometry \{.*?\n};", code, re.S)
        self.assertIsNotNone(match)
        compiler = shutil.which("c++")
        if compiler is None:
            self.skipTest("C++ compiler unavailable")
        with tempfile.TemporaryDirectory() as directory:
            program = Path(directory) / "preview.cpp"
            executable = Path(directory) / "preview"
            program.write_text("""
#include <array>
#include <cassert>
#include <memory>
struct Vec { int x, y; bool operator==(const Vec&) const = default; };
struct CBox {
    Vec p, s;
    Vec pos() const { return p; }
    Vec size() const { return s; }
};
struct Animation {
    Vec current, goal;
    Vec& value() { return current; }
};
constexpr int DECORATION_SHADOW = 1;
struct Decoration {
    int getDecorationType() const { return DECORATION_SHADOW; }
    void updateWindow(const std::shared_ptr<struct Window>&) {}
};
struct Presentation {
    auto decorations() const { return std::array<Decoration*, 0>{}; }
};
struct Window {
    Animation position{{5, 10}, {15, 20}}, size{{120, 130}, {140, 150}};
    Vec decorationSize{120, 130};
    auto positionAnimation() { return &position; }
    auto sizeAnimation() { return &size; }
    Presentation presentation() const { return {}; }
};
using PHLWINDOW = std::shared_ptr<Window>;
struct Positioner {
    void onWindowUpdate(const PHLWINDOW& window) {
        window->decorationSize = window->size.current;
    }
};
static Positioner positioner;
static auto* g_pDecorationPositioner = &positioner;
""" + match.group(0) + """
int main() {
    const auto window = std::make_shared<Window>();
    const auto validGoal = [&] {
        return window->position.goal == Vec{15, 20} && window->size.goal == Vec{140, 150};
    };
    {
        PreviewWindowGeometry preview(window, CBox{{200, 300}, {500, 600}});
        assert((window->position.current == Vec{200, 300}));
        assert((window->size.current == Vec{500, 600}));
        assert(validGoal());
        // Shadows can trigger repositioning while the preview geometry is installed.
        positioner.onWindowUpdate(window);
    }
    assert((window->position.current == Vec{5, 10}));
    assert((window->size.current == Vec{120, 130}));
    assert((window->decorationSize == Vec{120, 130}));
    assert(validGoal());
}
""")
            subprocess.run([compiler, "-std=c++20", str(program), "-o", str(executable)], check=True, capture_output=True)
            subprocess.run([str(executable)], check=True, capture_output=True)

    def test_scaled_and_rotated_output(self):
        runner = "/usr/lib/qt6/bin/qmltestrunner"
        if not Path(runner).is_file():
            self.skipTest("Qt QML test runner unavailable")
        source = Path(__file__).resolve().parents[1] / "config/quickshell/rice-shell/modules/cod29/WorkspacePreview.qml"
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "modules/cod29").mkdir(parents=True)
            (root / "theme").mkdir()
            shutil.copy2(source, root / "modules/cod29/WorkspacePreview.qml")
            (root / "theme/qmldir").write_text("singleton Tokens 1.0 Tokens.qml\n")
            (root / "theme/Tokens.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property color background: "black" }\n')
            (root / "tst_preview.qml").write_text('''import QtQuick
import QtTest
import "modules/cod29"
TestCase {
    id: testCase
    name: "WorkspacePreview"
    property var output: ({ width: 1920, height: 1080, scale: 1, transform: 0 })
    QtObject {
        id: model
        property var targetMonitor: ({ lastIpcObject: testCase.output })
        property var targetScreen: ({ width: 1920, height: 1080 })
    }
    WorkspacePreview { id: preview; width: 400; height: 200; workspace: null; strip: model }
    function test_output_data() {
        return [
            { tag: "normal", transform: 0, scale: 1, width: 1920, height: 1080 },
            { tag: "fractional", transform: 0, scale: 1.5, width: 1280, height: 720 },
            { tag: "portrait", transform: 1, scale: 1, width: 1080, height: 1920 },
            { tag: "flippedPortrait", transform: 5, scale: 2, width: 540, height: 960 }
        ];
    }
    function test_output(data) {
        output = { width: 1920, height: 1080, scale: data.scale, transform: data.transform };
        compare(preview.outputWidth, data.width);
        compare(preview.outputHeight, data.height);
        verify(preview.viewport.width <= preview.width && preview.viewport.height <= preview.height);
        fuzzyCompare(preview.viewport.width / preview.viewport.height, data.width / data.height, 0.0001);
    }
}
''')
            result = subprocess.run([runner, "-input", str(root), "-o", "-,txt"],
                                    env={**os.environ, "QT_QPA_PLATFORM": "offscreen"},
                                    capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
