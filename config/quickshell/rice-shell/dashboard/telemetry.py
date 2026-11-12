#!/usr/bin/env python3
import json
import os
import shutil

def get_telemetry():
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
    total_kb = mem.get("MemTotal", 1)
    avail_kb = mem.get("MemAvailable", 0)
    used_kb = max(0, total_kb - avail_kb)
    ram_pct = max(0, min(100, round((used_kb / total_kb) * 100)))

    # 3. Disk Usage (Root filesystem /)
    try:
        du = shutil.disk_usage("/")
        disk_pct = max(0, min(100, round((du.used / du.total) * 100)))
        disk_used_gb = f"{du.used / (1024**3):.1f} GB"
        disk_total_gb = f"{du.total / (1024**3):.1f} GB"
    except Exception:
        disk_pct = 0
        disk_used_gb = "0 GB"
        disk_total_gb = "0 GB"

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

    # 5. CPU Load & Estimated Usage %
    load_str = "0.00"
    cpu_pct = 0
    try:
        with open("/proc/loadavg") as f:
            loads = f.read().split()
            load_str = f"{loads[0]}, {loads[1]}, {loads[2]}"
            cores = os.cpu_count() or 4
            cpu_pct = max(0, min(100, round((float(loads[0]) / cores) * 100)))
    except Exception:
        pass

    return {
        "cpu_pct": cpu_pct,
        "cpu_load": load_str,
        "cpu_model": cpu_model,
        "ram_used": f"{used_kb / (1024*1024):.1f} GB",
        "ram_total": f"{total_kb / (1024*1024):.1f} GB",
        "ram_pct": ram_pct,
        "disk_used": disk_used_gb,
        "disk_total": disk_total_gb,
        "disk_pct": disk_pct,
        "uptime": uptime_str
    }

if __name__ == "__main__":
    print(json.dumps(get_telemetry()))
