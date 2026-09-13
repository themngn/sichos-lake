#!/usr/bin/env python3
"""Enumerates DDC/CI-controllable external monitors and reads/writes their
brightness (VCP feature 0x10), for the bar's Display Settings widget
(DisplaySettings.qml). ddcutil calls are slow I2C round-trips (hundreds of
ms, sometimes with retries) -- this is invoked as a subprocess from QML
rather than polled, and the widget debounces `set` calls from slider drags
rather than firing one per pixel.

Subcommands:
  list          Emits one JSON line: [{"bus": int, "output": str,
                "brightness": int, "max": int}, ...]. "output" is read
                straight off `ddcutil detect --brief`'s own
                "DRM connector: cardN-<output>" line -- confirmed live this
                exactly matches `hyprctl monitors -j`'s "name" field (e.g.
                "DP-2"), so no separate EDID/serial cross-matching is
                needed. A display `ddcutil detect` finds but can't read VCP
                10 from (DDC communication failure) is omitted rather than
                reported with a bogus brightness.
  set BUS VALUE Sets VCP feature 10 (brightness, raw value not a percent --
                the caller scales against that monitor's own "max" from
                `list`) on the given I2C bus.

Real `ddcutil detect --brief` output this was written against (Fedora
ddcutil 2.2.1):
    Display 1
       I2C bus:          /dev/i2c-4
       DRM connector:    card1-DP-2
       drm_connector_id: 0
       Monitor:          LEN:P27h-20:V909G51W
and `ddcutil getvcp 10 --brief -b 4` -> "VCP 10 C 75 100" (current, max).

The laptop panel (eDP-1) still shows up in `detect --brief`'s output --
this AMD GPU exposes an I2C/DP-AUX bus for it same as any DP connector --
but it has no real DDC/CI bus behind it, and probing it doesn't just fail
fast: confirmed live (journalctl's "i2c_check_open_bus_alive" trace) that
querying VCP 10 on it always eats 2 retries at a full, unscaled 1s sleep
each (this retry path ignores both --sleep-multiplier and --maxtries --
tried and timed both, no difference) before giving up as "disconnected" --
~4.5s, on every single popup open, not just an occasional flaky-monitor
case. So getvcp is skipped entirely for a connector that looks like the
laptop panel, using the same eDP/LVDS/DSI prefix DisplaySettings.qml's own
isLaptopPanel() already keys off of, rather than paying that tax and
discarding the result anyway.
"""
import json
import re
import subprocess
import sys

BUS_RE = re.compile(r"I2C bus:\s*/dev/i2c-(\d+)")
CONNECTOR_RE = re.compile(r"DRM connector:\s*card\d+-(\S+)")
VCP_RE = re.compile(r"VCP 10 C (\d+) (\d+)")
LAPTOP_PANEL_RE = re.compile(r"^(eDP|LVDS|DSI)")


def list_monitors():
    try:
        detect = subprocess.run(["ddcutil", "detect", "--brief"],
                                 capture_output=True, text=True, timeout=15)
    except (OSError, subprocess.TimeoutExpired):
        print("[]")
        return

    monitors = []
    for block in detect.stdout.split("\n\n"):
        bus_match = BUS_RE.search(block)
        conn_match = CONNECTOR_RE.search(block)
        if not bus_match or not conn_match:
            continue
        output = conn_match.group(1)
        if LAPTOP_PANEL_RE.match(output):
            continue
        bus = int(bus_match.group(1))

        try:
            vcp = subprocess.run(["ddcutil", "getvcp", "10", "--brief", "-b", str(bus)],
                                  capture_output=True, text=True, timeout=10)
        except (OSError, subprocess.TimeoutExpired):
            continue
        vcp_match = VCP_RE.search(vcp.stdout)
        if not vcp_match:
            continue  # DDC communication failed for this display -- skip it
        monitors.append({
            "bus": bus,
            "output": output,
            "brightness": int(vcp_match.group(1)),
            "max": int(vcp_match.group(2)),
        })
    print(json.dumps(monitors))


def set_brightness(bus, value):
    subprocess.run(["ddcutil", "setvcp", "10", str(value), "-b", str(bus)],
                    capture_output=True, timeout=10)


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == "list":
        list_monitors()
    elif len(sys.argv) >= 4 and sys.argv[1] == "set":
        set_brightness(int(sys.argv[2]), int(sys.argv[3]))
    else:
        print("usage: ddc-brightness.py list | set BUS VALUE", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
