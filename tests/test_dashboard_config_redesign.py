import unittest
from pathlib import Path


CONFIG_QML = (
    Path(__file__).resolve().parents[1]
    / "config/quickshell/rice-shell/dashboard/Config.qml"
).read_text(encoding="utf-8")


def assert_qml_contains(test_case, snippet):
    test_case.assertTrue(snippet in CONFIG_QML, f"Config.qml is missing {snippet!r}")


class DashboardConfigRedesignTests(unittest.TestCase):
    def test_categories_select_their_pages_in_compact_and_wide_layouts(self):
        assert_qml_contains(self, 'title: "Appearance"')
        assert_qml_contains(self, 'title: "Runtime"')
        assert_qml_contains(self, "root.selectedCategory = categoryItem.modelData.index")
        assert_qml_contains(self, "root.selectedCategory === modelData.index")
        assert_qml_contains(self, "columns: root.compactLayout ? 1 : 2")
        assert_qml_contains(self, "columns: root.compactLayout ? 2 : 1")

    def test_appearance_uses_live_tokens_and_reports_queue_state(self):
        assert_qml_contains(self, "Tokens.mode")
        assert_qml_contains(self, "Tokens.isValid")
        assert_qml_contains(self, "ThemeCommandQueue.running")
        assert_qml_contains(self, "ThemeCommandQueue.pendingCount")
        assert_qml_contains(self, "ThemeCommandQueue.result")
        assert_qml_contains(self, "ThemeCommandQueue.queueCommand(command)")
        assert_qml_contains(self, "ThemeCommandQueue.switchTheme(mode)")
        assert_qml_contains(self, "ThemeCommandQueue.regenerateTheme()")
        assert_qml_contains(self, "visible: root.themeStatusVisible")
        assert_qml_contains(self, "root.themeCommandFailed ? Tokens.danger : Tokens.text_secondary")
        assert_qml_contains(self, "onClicked: root.switchTheme(modeItem.modelData.mode)")
        assert_qml_contains(self, "onClicked: root.regenerateTheme()")

    def test_runtime_actions_keep_their_existing_owners(self):
        assert_qml_contains(self, "ThemeCommandQueue.requestShellReload()")
        assert_qml_contains(self, "ThemeCommandQueue.reloadHyprland()")
        assert_qml_contains(self, "Tokens.reloadTheme()")
        assert_qml_contains(self, "onClicked: root.runRuntimeAction(actionRow.modelData.id)")


if __name__ == "__main__":
    unittest.main()
