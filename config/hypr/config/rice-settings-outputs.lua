local root = os.getenv("XDG_CONFIG_HOME")
if not root or root == "" then
    local home = os.getenv("HOME")
    if not home then return end
    root = home .. "/.config"
end
if root:sub(1, 1) ~= "/" then return end

local file = io.open(root .. "/rice-settings/hypr-overrides.lua", "rb")
if not file then return end
local data = file:read(65537) or ""
file:close()
if #data > 65536 then return end

-- Read the generated literal rules without evaluating arbitrary Lua from a file.
local pattern = '^hl%.monitor%(%{output="([%w_-]+)",mode="(%d+x%d+@[%d.]+Hz)",'
    .. 'position="(%-?%d+x%-?%d+)",scale=([%d.]+),transform=([0-7])%}%)$'
local rules, used = {}, {}
for line in data:gmatch("[^\n]+") do
    local output, mode, position, scale, transform = line:match(pattern)
    scale = tonumber(scale)
    if not output or #output > 64 or used[output] or not scale or scale < 0.25 or scale > 5 then
        print("Ignoring invalid Rice Settings display overrides")
        return
    end
    used[output] = true
    rules[#rules + 1] = {
        output = output, mode = mode, position = position, scale = scale, transform = tonumber(transform),
    }
end
for _, rule in ipairs(rules) do
    hl.monitor(rule)
end
