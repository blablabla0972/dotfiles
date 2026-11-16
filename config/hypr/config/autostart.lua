-- Auto-start config
-- if you dont use UWSM add your auto start programs here, otherwise use XDG autostart https://wiki.archlinux.org/title/XDG_Autostart

hl.on("hyprland.start", function ()
    hl.exec_cmd("dbus-update-activation-environment --systemd --all")
    hl.exec_cmd("bash ~/.config/hypr/scripts/start-rice-shell.sh")
    hl.exec_cmd("pgrep -x hypridle >/dev/null || setsid hypridle -c ~/.config/hypr/hypridle.conf >/dev/null 2>&1 &")
    hl.exec_cmd("pgrep -x fcitx5 >/dev/null || fcitx5 -d")
    hl.exec_cmd("pgrep -x wl-paste >/dev/null || wl-paste --watch cliphist store")
    hl.exec_cmd("hyprlock")
end)
