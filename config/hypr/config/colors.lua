-- Read Matugen's active mode; generated files remain owned by the theme pipeline.
local config_home = os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")
local file = assert(io.open(config_home .. "/hypr/colors.conf", "r"))
local colors = {}
for line in file:lines() do
    local name, value = line:match("^%$([%w_]+)%s*=%s*(rgba%(%x+%))")
    if name then colors[name] = value end
end
file:close()

for _, name in ipairs({ "primary", "on_primary", "secondary", "on_secondary",
                        "surface_container", "on_surface", "outline_variant", "shadow" }) do
    assert(colors[name], "Missing Matugen role: " .. name)
end

function colors.apply_theme()
    hl.config({
        general = { col = { active_border = colors.primary, inactive_border = colors.outline_variant } },
        group = {
            col = {
                border_active = colors.primary, border_inactive = colors.outline_variant,
                border_locked_active = colors.secondary, border_locked_inactive = colors.outline_variant,
            },
            groupbar = {
                col = {
                    active = colors.primary, inactive = colors.surface_container,
                    locked_active = colors.secondary, locked_inactive = colors.surface_container,
                },
                text_color = colors.on_primary, text_color_inactive = colors.on_surface,
                text_color_locked_active = colors.on_secondary, text_color_locked_inactive = colors.on_surface,
            },
        },
    })
end

return colors
