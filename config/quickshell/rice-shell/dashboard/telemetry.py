#!/usr/bin/env python3
import json
import math
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


def gib(value):
    return f"{value / (1024**3):.1f} GiB" if value is not None else None


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
    uptime_str = None
    try:
        with open("/proc/uptime") as f:
            up_secs = float(f.read().split()[0])
        if not math.isfinite(up_secs) or up_secs < 0:
            raise ValueError("invalid uptime")
        days = int(up_secs // 86400)
        hours = int((up_secs % 86400) // 3600)
        mins = int((up_secs % 3600) // 60)
        if days > 0:
            uptime_str = f"{days}d {hours}h {mins}m"
        elif hours > 0:
            uptime_str = f"{hours}h {mins}m"
        else:
            uptime_str = f"{mins}m"
    except (OSError, ValueError, IndexError, TypeError):
        pass

    # 2. Memory (RAM)
    mem = {}
    try:
        with open("/proc/meminfo") as f:
            for line in f:
                parts = line.split(":")
                if len(parts) == 2:
                    try:
                        value = int(parts[1].split()[0])
                        if value >= 0:
                            mem[parts[0].strip()] = value
                    except (ValueError, IndexError):
                        continue
    except OSError:
        pass
    total_kb = mem.get("MemTotal")
    if not total_kb:
        total_kb = None
    avail_kb = mem.get("MemAvailable")
    if total_kb is not None and avail_kb is not None:
        avail_kb = min(total_kb, avail_kb)
        used_kb = total_kb - avail_kb
        ram_pct = max(0, min(100, round((used_kb / total_kb) * 100)))
    else:
        avail_kb = None
        used_kb = None
        ram_pct = None

    # 3. Disk Usage (Root filesystem /)
    try:
        fs = os.statvfs("/")
        block_size = int(fs.f_frsize)
        disk_total = int(fs.f_blocks) * block_size
        if disk_total <= 0 or block_size <= 0 or fs.f_bfree < 0 or fs.f_bavail < 0:
            raise ValueError("invalid filesystem capacity")
        disk_used = min(disk_total, max(0, (int(fs.f_blocks) - int(fs.f_bfree)) * block_size))
        disk_free = min(disk_total, int(fs.f_bavail) * block_size)
        disk_pct = max(0, min(100, round((disk_used / disk_total) * 100)))
        disk_used_gb = gib(disk_used)
        disk_free_gb = gib(disk_free)
        disk_total_gb = gib(disk_total)
    except (OSError, ValueError, TypeError, OverflowError):
        disk_pct = None
        disk_used_gb = None
        disk_free_gb = None
        disk_total_gb = None

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
        if len(loads) != 3 or not all(math.isfinite(v) and v >= 0 for v in loads):
            raise ValueError("invalid load averages")
        load_str = ", ".join(f"{v:.2f}" for v in loads)
        load_1m = f"{loads[0]:.2f}"
    except (OSError, ValueError, TypeError):
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
        "ram_used": gib(used_kb * 1024) if used_kb is not None else None,
        "ram_total": gib(total_kb * 1024) if total_kb is not None else None,
        "ram_pct": ram_pct,
        "ram_available": gib(avail_kb * 1024) if avail_kb is not None else None,
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
        print(json.dumps(get_telemetry(), allow_nan=False), flush=True)
        time.sleep(max(0, period - (time.monotonic() - started)))


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "--watch":
        watch_telemetry(float(sys.argv[2]) if len(sys.argv) > 2 else 5.0)
    else:
        print(json.dumps(get_telemetry(), allow_nan=False))
