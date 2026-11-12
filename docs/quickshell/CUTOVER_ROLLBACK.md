# Cutover & Rollback Protocol: Noctalia ↔ Quickshell

**Target Branch**: `quickshell`  
**Safety Status**: Cutover requires explicit user approval before touching live session services or symlinks.

---

## 1. Safety Invariants Prior to Cutover

1. **Main Branch Untouched**: `main` remains pristine; all changes are isolated in branch `quickshell`.
2. **Noctalia Patched Binaries Preserved**:
   - `/home/admin/.local/bin/noctalia`
   - `/home/admin/noctalia-dashboard-redesign/`
   - `state/noctalia/`
   *Never run `pacman -R noctalia` or delete patched sources.*
3. **Single Owner Rule**:
   - Exactly one notification server (`org.freedesktop.Notifications`).
   - Exactly one idle manager (`hypridle` OR Noctalia native idle, never both).
   - Exactly one session locker (`hyprlock` OR Noctalia native lock).
   - Exactly one wallpaper daemon (`swww-daemon`).
4. **No Blanket Kills**: Never execute `pkill quickshell`, as the wallpaper switcher is also a Quickshell process. Always inspect process ownership and kill only verified PIDs using safe pattern `pkill -f "(quickshell|qs) -p .*rice-shell"`.

---

## 2. Step-by-Step Cutover Procedure (Only After Explicit User Approval)

### Pre-Cutover Verification
```bash
# 1. Verify Quickshell shell executes without errors in isolated test mode
qs -p /home/admin/Projects/dotfiles/.worktrees/quickshell/config/quickshell/rice-shell --dry-run

# 2. Verify Hyprland Lua syntax and config integrity
hyprctl configerrors

# 3. Verify hypridle configuration syntax
hypridle -c /home/admin/Projects/dotfiles/.worktrees/quickshell/config/hypr/hypridle.conf -v &
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
3. **Deploy Rice-Shell Symlink & Launch**:
   ```bash
   ln -sfn /home/admin/Projects/dotfiles/.worktrees/quickshell/config/quickshell/rice-shell ~/.config/quickshell/rice-shell
   quickshell -p ~/.config/quickshell/rice-shell &
   QS_PID=$!
   echo "Quickshell started with PID $QS_PID"
   ```
4. **Start hypridle**:
   ```bash
   hypridle -c ~/.config/hypr/hypridle.conf &
   ```
5. **Verify IPC Health**:
   ```bash
   qs ipc -p ~/.config/quickshell/rice-shell call rice health
   ```

---

## 3. Immediate 100% Rollback Procedure

If any issue occurs during testing or cutover:

1. **Stop Quickshell rice-shell process and remove preview symlink**:
   ```bash
   # Terminate only the rice-shell instance
   pkill -f "(quickshell|qs) -p .*rice-shell"
   rm -f ~/.config/quickshell/rice-shell
   ```
2. **Stop hypridle (if started)**:
   ```bash
   pkill -x hypridle || true
   ```
3. **Restore Noctalia daemon**:
   ```bash
   /home/admin/.local/bin/noctalia -d &
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
