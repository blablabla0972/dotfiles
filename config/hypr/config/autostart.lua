-- Auto-start config
-- if you dont use UWSM add your auto start programs here, otherwise use XDG autostart https://wiki.archlinux.org/title/XDG_Autostart

local config_home = os.getenv("XDG_CONFIG_HOME")
if not config_home or config_home == "" then
    config_home = (os.getenv("HOME") or "") .. "/.config"
end

local function shell_quote(value)
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

hl.on("hyprland.start", function ()
    hl.exec_cmd("dbus-update-activation-environment --systemd --all")
    hl.exec_cmd("bash " .. shell_quote(config_home .. "/hypr/scripts/start-rice-shell.sh"))
    hl.exec_cmd("pgrep -x hypridle >/dev/null || setsid hypridle -c ~/.config/hypr/hypridle.conf >/dev/null 2>&1 &")
    hl.exec_cmd("pgrep -x fcitx5 >/dev/null || fcitx5 -d")
end)
