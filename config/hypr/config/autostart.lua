-- Auto-start config
-- if you dont use UWSM add your auto start programs here, otherwise use XDG autostart https://wiki.archlinux.org/title/XDG_Autostart

hl.on("hyprland.start", function ()
    hl.exec_cmd("dbus-update-activation-environment --systemd --all")
    hl.exec_cmd("pgrep -x noctalia >/dev/null || noctalia -d")
    hl.exec_cmd("pgrep -x fcitx5 >/dev/null || fcitx5 -d")
    -- hl.exec_cmd("pgrep -x hyprlock >/dev/null || hyprlock")
end)
