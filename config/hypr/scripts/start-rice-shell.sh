#!/usr/bin/env bash
set -uo pipefail

config_home=${XDG_CONFIG_HOME:-"${HOME:-}/.config"}
rice_config="${config_home%/}/quickshell/rice-shell"
rice_qml="${rice_config}/shell.qml"
notifications=${ENABLE_NOTIFICATIONS:-1}

has_rice_instance() {
    command -v quickshell >/dev/null 2>&1 || return 1
    quickshell list -p "$rice_config" --json 2>/dev/null \
        | python3 -c 'import json,sys; target=sys.argv[1]; items=json.load(sys.stdin); sys.exit(0 if any(item.get("config_path") == target for item in items) else 1)' "$rice_qml" 2>/dev/null
}

is_rice_healthy() {
    quickshell ipc -p "$rice_config" call rice health >/dev/null 2>&1
}

start_noctalia_fallback() {
    [[ "$notifications" == "0" ]] && return 1
    command -v noctalia >/dev/null 2>&1 || return 1
    if command -v pgrep >/dev/null 2>&1 && pgrep -x noctalia >/dev/null 2>&1; then
        return 0
    fi
    noctalia -d
}

if ! command -v quickshell >/dev/null 2>&1; then
    if start_noctalia_fallback; then exit 0; fi
    echo "Quickshell is unavailable; no shell fallback was started." >&2
    exit 1
fi

if has_rice_instance; then
    for _ in {1..20}; do
        if is_rice_healthy; then exit 0; fi
        sleep 0.25
    done
    echo "Rice Shell is running but did not become healthy; keeping it as the sole notification owner." >&2
    exit 1
fi

ENABLE_NOTIFICATIONS="$notifications" quickshell --no-duplicate --daemonize --path "$rice_config" \
    >/dev/null 2>&1 || true

for _ in {1..20}; do
    if is_rice_healthy; then exit 0; fi
    sleep 0.25
done

if has_rice_instance; then
    echo "Rice Shell started without IPC health; skipping Noctalia to avoid a second notification owner." >&2
    exit 1
fi

if start_noctalia_fallback; then exit 0; fi
echo "Rice Shell failed to start and no safe fallback is available." >&2
exit 1
