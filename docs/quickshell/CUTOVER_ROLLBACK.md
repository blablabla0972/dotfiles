# Cutover & Rollback Protocol: Noctalia ↔ Quickshell

**Target Branch**: `quickshell`  
**Safety Status**: Cutover requires explicit user approval before touching live session services or symlinks.

---

## 1. Safety Invariants Prior to Cutover

1. **Main Branch Untouched**: `main` remains pristine; proposed changes stay in the reviewed isolated worktree until cutover is explicitly approved.
2. **Noctalia Patched Binaries Preserved**:
   - `$HOME/.local/bin/noctalia`
   - `$HOME/noctalia-dashboard-redesign/`
   - `state/noctalia/`
   *Never run `pacman -R noctalia` or delete patched sources.*
3. **Single Owner Rule**:
   - Exactly one notification server (`org.freedesktop.Notifications`).
   - Exactly one idle manager (`hypridle` OR Noctalia native idle, never both).
   - Exactly one session locker (`hyprlock` OR Noctalia native lock).
   - Exactly one wallpaper daemon (`swww-daemon`).
4. **No Blanket Kills**: The wallpaper switcher is a separate Quickshell config. Inspect only the rice-shell instance with `quickshell list -p ~/.config/quickshell/rice-shell --json`; terminate only a PID whose `config_path` is the rice-shell `shell.qml`.

---

## 2. Step-by-Step Cutover Procedure (Only After Explicit User Approval)

### Pre-Cutover Verification
```bash
RICE_WORKTREE=/path/to/reviewed/dotfiles-worktree
cd "$RICE_WORKTREE"

# 1. Run repository validation and the native offscreen Dashboard regression
python3 tests/validate.py
python3 -m unittest discover -s tests -p 'test_dashboard_motion.py' -q

# 2. Verify Hyprland Lua syntax and config integrity
hyprctl configerrors

# 3. Verify hypridle configuration syntax
hypridle -c "$RICE_WORKTREE/config/hypr/hypridle.conf" -v &
IDLE_PID=$!
sleep 2 && kill -TERM "$IDLE_PID"
```

### Execution Steps
1. **Quiesce Noctalia cleanly**:
   ```bash
   NOCT_PID=$(pgrep -u "$UID" -x noctalia)
   if [ -n "$NOCT_PID" ]; then
       kill -TERM "$NOCT_PID"
       sleep 1
   fi
   ```
2. **Assert D-Bus Names Released**:
   ```bash
   busctl --user get-name-owner org.freedesktop.Notifications || echo "Notifications bus clean"
   ```
3. **Deploy Rice-Shell Symlink & Launch** (reviewed worktree only):
   ```bash
   RICE_WORKTREE=/path/to/reviewed/dotfiles-worktree
   ln -sfn "$RICE_WORKTREE/config/quickshell/rice-shell" ~/.config/quickshell/rice-shell
   ENABLE_NOTIFICATIONS=1 quickshell --no-duplicate --daemonize --path ~/.config/quickshell/rice-shell
   ```
4. **Start hypridle**:
   ```bash
   hypridle -c ~/.config/hypr/hypridle.conf &
   ```
5. **Verify IPC Health**:
   ```bash
   quickshell ipc -p ~/.config/quickshell/rice-shell call rice health
   ```

---

## 3. Immediate 100% Rollback Procedure

If any issue occurs during testing or cutover:

1. **Stop only the verified rice-shell process and remove its preview symlink**:
   ```bash
   RICE_WORKTREE=/path/to/reviewed/dotfiles-worktree
   quickshell list -p ~/.config/quickshell/rice-shell --json
   # Set this only to the PID whose config_path is rice-shell/shell.qml.
   RICE_PID=<verified-rice-shell-pid>
   kill -TERM "$RICE_PID"
   # RICE_WORKTREE is the reviewed worktree selected in step 3.
   test "$(readlink ~/.config/quickshell/rice-shell)" = "$RICE_WORKTREE/config/quickshell/rice-shell" \
       && rm -- ~/.config/quickshell/rice-shell
   ```
2. **Stop hypridle (if started)**:
   ```bash
   pkill -x hypridle || true
   ```
3. **Restore Noctalia daemon**:
   ```bash
   "$HOME/.local/bin/noctalia" -d &
   ```
4. **Verify Noctalia Health & D-Bus Ownership**:
   ```bash
   sleep 1
   noctalia msg status
   busctl --user get-name-owner org.freedesktop.Notifications
   ```
5. **Compositor State Check**:
   ```bash
   hyprctl configerrors
   ```
