-- Read Matugen's active mode; generated files remain owned by the theme pipeline.
local config_home = os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")
local file = assert(io.open(config_home .. "/hypr/colors.conf", "r"))
local colors = {}
for line in file:lines() do
    local name, value = line:match("^%$([%w_]+)%s*=%s*(rgba%(%x+%))")
    if name == "primary" or name == "shadow" then colors[name] = value end
end
file:close()

assert(colors.primary, "Missing Matugen role: primary")
assert(colors.shadow, "Missing Matugen role: shadow")

return colors
