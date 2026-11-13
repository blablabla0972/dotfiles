#!/usr/bin/env python3
import json
import os
import platform
import sys
import time

def cpu_times():
    with open("/proc/stat") as f:
        fields = [int(v) for v in f.readline().split()[1:9]]
    return sum(fields), fields[3] + fields[4]


def cpu_usage(before, after):
    total = after[0] - before[0]
    idle = after[1] - before[1]
    if total <= 0 or idle < 0:
        return None
    return max(0, min(100, round(100 * (total - idle) / total)))


def root_filesystem():
    try:
        with open("/proc/self/mountinfo") as f:
            for line in f:
                before, after = line.split(" - ", 1)
                if before.split()[4] == "/":
                    return after.split()[0]
    except (OSError, ValueError, IndexError):
        pass
    return "unknown"


def get_telemetry():
    # Measure busy CPU time, not the number of runnable tasks.
    cpu_pct = None
    try:
        before = cpu_times()
        time.sleep(0.2)
        cpu_pct = cpu_usage(before, cpu_times())
    except (OSError, ValueError, IndexError):
        pass

    # 1. System Uptime
    up_secs = 0
    try:
        with open("/proc/uptime") as f:
            up_secs = float(f.read().split()[0])
    except Exception:
        pass
    days = int(up_secs // 86400)
    hours = int((up_secs % 86400) // 3600)
    mins = int((up_secs % 3600) // 60)
    if days > 0:
        uptime_str = f"{days}d {hours}h {mins}m"
    elif hours > 0:
        uptime_str = f"{hours}h {mins}m"
    else:
        uptime_str = f"{mins}m"

    # 2. Memory (RAM)
    mem = {}
    try:
        with open("/proc/meminfo") as f:
            for line in f:
                parts = line.split(":")
                if len(parts) == 2:
                    mem[parts[0].strip()] = int(parts[1].split()[0])
    except Exception:
        pass
    total_kb = max(1, mem.get("MemTotal", 1))
    avail_kb = min(total_kb, max(0, mem.get("MemAvailable", 0)))
    used_kb = max(0, total_kb - avail_kb)
    ram_pct = max(0, min(100, round((used_kb / total_kb) * 100)))

    # 3. Disk Usage (Root filesystem /)
    try:
        fs = os.statvfs("/")
        disk_total = fs.f_blocks * fs.f_frsize
        disk_used = (fs.f_blocks - fs.f_bfree) * fs.f_frsize
        disk_free = fs.f_bavail * fs.f_frsize
        disk_pct = max(0, min(100, round((disk_used / disk_total) * 100)))
        disk_used_gb = f"{disk_used / (1024**3):.1f} GiB"
        disk_free_gb = f"{disk_free / (1024**3):.1f} GiB"
        disk_total_gb = f"{disk_total / (1024**3):.1f} GiB"
    except Exception:
        disk_pct = 0
        disk_used_gb = "—"
        disk_free_gb = "—"
        disk_total_gb = "—"

    # 4. CPU Model
    cpu_model = "Linux Processor"
    try:
        with open("/proc/cpuinfo") as f:
            for line in f:
                if "model name" in line:
                    cpu_model = line.split(":", 1)[1].strip()
                    break
    except Exception:
        pass

    # Load average is a separate scheduling metric.
    load_str = "—"
    load_1m = "—"
    try:
        loads = os.getloadavg()
        load_str = ", ".join(f"{v:.2f}" for v in loads)
        load_1m = f"{loads[0]:.2f}"
    except OSError:
        pass

    try:
        os_name = platform.freedesktop_os_release().get("PRETTY_NAME", "Linux")
    except OSError:
        os_name = "Linux"

    return {
        "cpu_pct": cpu_pct,
        "cpu_load": load_str,
        "cpu_model": cpu_model,
        "cpu_threads": os.cpu_count() or 1,
        "load_1m": load_1m,
        "hostname": platform.node(),
        "os_name": os_name,
        "kernel": platform.release(),
        "desktop": os.environ.get("XDG_CURRENT_DESKTOP") or os.environ.get("XDG_SESSION_DESKTOP") or "Linux",
        "filesystem": root_filesystem(),
        "ram_used": f"{used_kb / (1024*1024):.1f} GiB",
        "ram_total": f"{total_kb / (1024*1024):.1f} GiB",
        "ram_pct": ram_pct,
        "ram_available": f"{avail_kb / (1024*1024):.1f} GiB",
        "disk_used": disk_used_gb,
        "disk_total": disk_total_gb,
        "disk_free": disk_free_gb,
        "disk_pct": disk_pct,
        "uptime": uptime_str
    }

def watch_telemetry(period=5.0):
    """Stream snapshots from one process while the System tab is visible."""
    period = max(0.25, period)
    while True:
        started = time.monotonic()
        print(json.dumps(get_telemetry()), flush=True)
        time.sleep(max(0, period - (time.monotonic() - started)))


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "--watch":
        watch_telemetry(float(sys.argv[2]) if len(sys.argv) > 2 else 5.0)
    else:
        print(json.dumps(get_telemetry()))
