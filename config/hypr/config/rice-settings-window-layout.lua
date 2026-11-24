local result = {}
local root = os.getenv("XDG_CONFIG_HOME")
if not root or root == "" then
    local home = os.getenv("HOME")
    if not home then return result end
    root = home .. "/.config"
end
if root:sub(1, 1) ~= "/" then return result end

local file = io.open(root .. "/rice-settings/window-layout.conf", "rb")
if not file then return result end
local raw = file:read(260)
file:close()
if not raw or #raw == 0 then return result end

local sides = "(%d%d?) (%d%d?) (%d%d?) (%d%d?)"
local values = { raw:match("^gaps_in " .. sides .. "\ngaps_out " .. sides .. "\nborder_size (%d%d?)\n$") }
if #values ~= 9 then return result end
for i, value in ipairs(values) do
    values[i] = tonumber(value)
    if values[i] > (i == 9 and 12 or 40) then return result end
end
hl.config({
    general = {
        gaps_in = { top = values[1], right = values[2], bottom = values[3], left = values[4] },
        gaps_out = { top = values[5], right = values[6], bottom = values[7], left = values[8] },
        border_size = values[9],
    },
})
result.profile = raw
return result
