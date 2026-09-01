#!/usr/bin/env python3
import glob
import json
import os
import re
import socket
import subprocess
import sys
import threading
import time


def get_monitors():
    try:
        res = subprocess.run(
            ["hyprctl", "monitors", "all", "-j"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        if res.returncode == 0:
            return json.loads(res.stdout)
    except Exception:
        pass
    return []


def get_internal_monitor(monitors):
    for m in monitors:
        name = m.get("name", "")
        if re.match(r"^(eDP|LVDS|DSI)-", name):
            return name
    return None


def has_active_external_monitor(monitors):
    for m in monitors:
        name = m.get("name", "")
        if not re.match(r"^(eDP|LVDS|DSI)-", name) and not m.get(
            "disabled", False
        ):
            return True
    return False


def is_lid_closed():
    for state_file in glob.glob("/proc/acpi/button/lid/*/state"):
        try:
            with open(state_file, "r") as f:
                if "closed" in f.read().lower():
                    return True
        except Exception:
            pass
    return False


def is_laptop():
    return bool(
        glob.glob("/proc/acpi/button/lid/*")
        or glob.glob("/sys/class/power_supply/BAT*")
    )


def sync_clamshell():
    monitors = get_monitors()
    internal = get_internal_monitor(monitors)
    if not internal or not re.match(r"^[A-Za-z0-9._-]+$", internal):
        return

    ext_active = has_active_external_monitor(monitors)
    lid_closed = is_lid_closed()

    if is_laptop() and lid_closed and ext_active:
        subprocess.run(
            [
                "hyprctl",
                "eval",
                f'hl.monitor({{ output = "{internal}", disabled = true }})',
            ],
            capture_output=True,
        )
    else:
        subprocess.run(
            [
                "hyprctl",
                "eval",
                f'hl.monitor({{ output = "{internal}", mode = "preferred", position = "auto", scale = 1 }})',
            ],
            capture_output=True,
        )
        subprocess.run(
            [
                "hyprctl",
                "dispatch",
                f'hl.dsp.dpms({{ action = "enable", monitor = "{internal}" }})',
            ],
            capture_output=True,
        )


def recover_modeless():
    monitors = get_monitors()
    has_modeless = any(
        not m.get("disabled", False)
        and (m.get("width", 0) == 0 or m.get("height", 0) == 0)
        for m in monitors
    )
    if has_modeless:
        delay = 3
        for _ in range(5):
            subprocess.run(["hyprctl", "reload"], capture_output=True)
            time.sleep(delay)
            monitors = get_monitors()
            if not any(
                not m.get("disabled", False)
                and (m.get("width", 0) == 0 or m.get("height", 0) == 0)
                for m in monitors
            ):
                break
            delay = min(delay * 2, 60)


def update_wallpaper():
    wallpaper_path = os.path.expanduser("~/Pictures/wallpaper.jpg")
    if os.path.exists(wallpaper_path):
        subprocess.run(
            ["hyprctl", "hyprpaper", "wallpaper", f",{wallpaper_path}"],
            capture_output=True,
        )


def poll_loop():
    while True:
        time.sleep(2)
        monitors = get_monitors()
        if is_laptop() and has_active_external_monitor(monitors):
            sync_clamshell()


def listen_socket():
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    runtime = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    if not sig:
        return
    sock_path = f"{runtime}/hypr/{sig}/.socket2.sock"
    if not os.path.exists(sock_path):
        return

    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.connect(sock_path)
        f = s.makefile("r", encoding="utf-8", errors="ignore")
    except Exception:
        return

    for line in f:
        line = line.strip()
        if not line:
            continue

        if line.startswith("monitoradded") or line.startswith("monitoraddedv2"):
            sync_clamshell()
            update_wallpaper()
            threading.Thread(target=recover_modeless, daemon=True).start()

            def retry_clamshell():
                for d in [1, 3, 7]:
                    time.sleep(d)
                    sync_clamshell()

            threading.Thread(target=retry_clamshell, daemon=True).start()

        elif line.startswith("monitorremoved") or line.startswith(
            "monitorremovedv2"
        ):
            sync_clamshell()
            threading.Thread(target=recover_modeless, daemon=True).start()

            def retry_clamshell():
                for d in [1, 3, 7]:
                    time.sleep(d)
                    sync_clamshell()

            threading.Thread(target=retry_clamshell, daemon=True).start()

        elif line.startswith("configreloaded"):
            threading.Thread(target=recover_modeless, daemon=True).start()


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--sync-clamshell":
        sync_clamshell()
        return

    # Initial checks on startup
    sync_clamshell()
    threading.Thread(target=recover_modeless, daemon=True).start()
    threading.Thread(target=poll_loop, daemon=True).start()

    listen_socket()


if __name__ == "__main__":
    main()
