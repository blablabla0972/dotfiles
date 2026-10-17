-- Look and feel configuration
local colors = require("config.colors")

hl.config({
    general = {
        gaps_in = 5,
        gaps_out = 10,
        border_size = 2,
        extend_border_grab_area = 10,
        resize_on_border = true,
    },
    decoration = {
        dim_special = 0.3,
        rounding = 14,
        active_opacity = 1,
        inactive_opacity = 1,
        fullscreen_opacity = 1,
        blur = {
            size = 4,
            passes = 2,
            new_optimizations = true,
            xray = false,
            vibrancy = 0.05,
            special = false,
        },
        shadow = {
            enabled = true,
            range = 24,
            render_power = 3,
            color = colors.shadow:gsub("ff%)$", "33)"),
        },
    },
})
