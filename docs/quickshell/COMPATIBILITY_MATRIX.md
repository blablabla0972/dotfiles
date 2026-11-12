# Compatibility Matrix: Noctalia v5.4.1 → Quickshell Shell

**Branch**: `quickshell`  
**Compositor**: Hyprland 0.57.0 (Lua Config)  
**Shell Engine**: Quickshell 0.3.2

---

## 1. Feature Parity & Ownership Mapping

| Noctalia Subsystem | Current Noctalia Feature | New Quickshell / System Owner | Implementation Mechanism | Milestone |
| :--- | :--- | :--- | :--- | :---: |
| **Top Bar** | Workspaces, clock, tray, status, media pill | `rice-shell/bar/Bar.qml` | `Quickshell.Hyprland`, `PanelWindow` (exclusiveZone: 40), `SystemTray` | M2 / M3 |
| **Dynamic Island** | *None (New Feature)* | `rice-shell/island/Island.qml` | Shape with cubic anti-corners, 5 states: `idle`, `media`, `volume/brightness`, `notification`, `expanded` | M3 |
| **App Launcher** | `noctalia msg panel-toggle launcher` | `rice-shell/launcher/Launcher.qml` | `DesktopEntry.execute()` or `uwsm app --`, Esc/click-away dismiss | M5 |
| **Control Center** | `noctalia msg panel-toggle control-center` | `rice-shell/dashboard/Dashboard.qml` | Responsive 3-col Home (Profile+Calendar, Clock+Media, Brightness+Quick Toggles) + Tabs | M5 |
| **Audio Volume OSD**| `noctalia msg volume-*` | `rice-shell/island/` or `overlays/Osd.qml` | Native `Quickshell.Services.Pipewire` reactive observation | M3 / M4 |
| **Brightness OSD** | `noctalia msg brightness-*` | `rice-shell/island/` or `overlays/Osd.qml` | `brightnessctl` bounded subprocess / IPC | M3 / M4 |
| **Media Player** | `noctalia msg media *` | `rice-shell/services/Media.qml` | Native `Quickshell.Services.Mpris` | M4 |
| **Notifications** | Native daemon (`org.freedesktop.Notifications`) | `rice-shell/overlays/Notifications.qml` | `Quickshell.Services.Notifications` (tested isolated via `dbus-run-session`) | M6 |
| **Screen Lock** | `noctalia msg session lock` | `hyprlock` (direct) | Wayland `ext-session-lock-v1` via `hyprlock.conf` | M7 |
| **Idle Management**| Noctalia native idle manager | `hypridle` daemon | Timings: 180s dim (20%), 300s lock, 360s DPMS (Lua syntax), 1800s suspend; `unlock_cmd = brightnessctl -r` | M7 |
| **Session Actions**| `noctalia msg panel-toggle session` | `rice-shell/dashboard/SessionMenu.qml` | `loginctl lock-session`, `systemctl poweroff`, `systemctl reboot` | M7 |
| **Wallpaper Picker**| Quickshell carousel (`SUPER + W`) | `config/quickshell/wallpaper-switcher/` | **Retained 100% untouched** (ApplyState.js + apply-wallpaper.sh) | All |
| **Wallpaper Render**| `swww-daemon` | `swww-daemon` | **Retained 100% untouched** (`swww-daemon.service`) | All |
| **Theme Tokens** | `derive_tokens.py` + Matugen | `generate-theme.py` (decoupled) | Decoupled mode runs Matugen + `derive_tokens.py` without Noctalia binary/IPC | M8 |

---

## 2. Keybinds Migration (`config/hypr/config/binds.lua`)

| Key Combination | Current Command | New Command / Quickshell IPC |
| :--- | :--- | :--- |
| `SUPER + Space` | `noctalia msg panel-toggle launcher` | `qs ipc -p ~/.config/quickshell/rice-shell call rice toggleLauncher` |
| `SUPER + .` | `noctalia msg panel-toggle launcher /emo` | `qs ipc -p ~/.config/quickshell/rice-shell call rice toggleEmoji` |
| `SUPER + X` | `noctalia msg panel-toggle control-center` | `qs ipc -p ~/.config/quickshell/rice-shell call rice toggleDashboard` |
| `SUPER + Z` | `noctalia msg settings-toggle` | `qs ipc -p ~/.config/quickshell/rice-shell call rice toggleDashboard quick` |
| `SUPER + L` | `noctalia msg session lock` | `pidof hyprlock \|\| hyprlock` (robust direct lock invocation) |
| `SUPER + ALT + C` | `noctalia msg panel-toggle session` | `qs ipc -p ~/.config/quickshell/rice-shell call rice toggleSession` |
| `SUPER + A` | `noctalia msg panel-toggle control-center notifications` | `qs ipc -p ~/.config/quickshell/rice-shell call rice toggleNotifications` |
| `SUPER + V` | `noctalia msg panel-toggle clipboard` | `qs ipc -p ~/.config/quickshell/rice-shell call rice toggleClipboard` |
| `SUPER + Tab` | `noctalia msg window-switcher` | `qs ipc -p ~/.config/quickshell/rice-shell call rice toggleWindowSwitcher` |
| `XF86AudioRaiseVolume` | `noctalia msg volume-up` | `wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+` (zero-overhead repeating, reactive OSD) |
| `XF86AudioLowerVolume` | `noctalia msg volume-down` | `wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%-` (zero-overhead repeating, reactive OSD) |
| `XF86AudioMute` | `noctalia msg volume-mute` | `wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle` |
| `XF86AudioMicMute` | `noctalia msg mic-mute` | `wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle` |
| `XF86AudioPlay` / `Pause` | `noctalia msg media toggle` | `playerctl play-pause` |
| `XF86AudioNext` | `noctalia msg media next` | `playerctl next` |
| `XF86AudioPrev` | `noctalia msg media previous` | `playerctl previous` |
| `XF86MonBrightnessUp` | `noctalia msg brightness-up` | `brightnessctl set +5% && qs ipc -p ~/.config/quickshell/rice-shell call rice brightnessChanged` |
| `XF86MonBrightnessDown` | `noctalia msg brightness-down` | `brightnessctl set 5%- && qs ipc -p ~/.config/quickshell/rice-shell call rice brightnessChanged` |
| `Print` | `noctalia msg screenshot-region` | `grim -g "$(slurp)" - \| wl-copy` (or native portal) |
| `SUPER + Print` | `noctalia msg screenshot-fullscreen` | `grim - \| wl-copy` |
| `SUPER + W` | `quickshell -p ~/.config/quickshell/wallpaper-switcher` | *Retained completely unchanged* |
| `SUPER + M` | `~/.local/bin/toggle-desktop` | *Retained completely unchanged* |
