-- CachyOS Hyprland Configuration

-- Unload cached config modules on reload
for k, _ in pairs(package.loaded) do
    if k:sub(1, 7) == "config." or k == "noctalia" then
        package.loaded[k] = nil
    end
end

require("config.animations")
require("config.autostart")
require("config.colors")
require("config.decorations")
require("config.variables")
require("config.environment")
require("config.inputs")
require("config.binds")
require("config.misc")
require("config.monitors")
require("config.windowrules")
require("config.workspaces")

-- Apply Matugen-driven color scheme
require("config.colors").apply_theme()
