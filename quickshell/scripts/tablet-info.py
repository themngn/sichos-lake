#!/usr/bin/env python3
"""Pen tablets' names and physical sizes, for TabletSettings.qml.

Prints one JSON object: {"<hyprland device name>": {"name": ..., "bus": ...,
"width": mm, "height": mm}}. Keep proportions and the area size need the
tablet's size in mm (Hyprland's input.tablet.active_area_* are in mm), and
neither Hyprland nor anything readable without root reports it: libinput
knows it (from evdev's ABS resolution), but /dev/input/event* is root:input.
Every HID report descriptor is world-readable in sysfs though, and a
digitizer states its X/Y physical extent there -- the One by Wacom
(CTC-6110WL) over Bluetooth says 21600 x 13500 at 10^-3 cm, its 216 x 135 mm.

The key is Hyprland's device name: HID_NAME lowercased, spaces as dashes
(checked against `hyprctl devices -j`: "Wacom One pen tablet medium" ->
"wacom-one-pen-tablet-medium").
"""
import glob
import json
import os

BUSES = {"0003": "USB", "0005": "Bluetooth", "0018": "I2C"}


def extent(desc):
    """(width_mm, height_mm) of the first X/Y pair in a Digitizer
    collection, or None."""
    gpage = unit = exp = 0
    phys_max = log_max = 0
    usages = []
    in_digitizer = 0
    found = {}
    i = 0
    while i < len(desc):
        b = desc[i]
        if b == 0xFE:  # long item
            i += 3 + desc[i + 1]
            continue
        size = (0, 1, 2, 4)[b & 3]
        kind = (b >> 2) & 3
        tag = b >> 4
        raw = desc[i + 1:i + 1 + size]
        val = int.from_bytes(raw, "little")
        sval = int.from_bytes(raw, "little", signed=True) if size else 0
        i += 1 + size
        if kind == 1:  # global
            if tag == 0: gpage = val
            elif tag == 2: log_max = sval
            elif tag == 4: phys_max = sval
            elif tag == 5: exp = val - 16 if val > 7 else val
            elif tag == 6: unit = val
        elif kind == 2:  # local
            if tag == 0:
                usages.append(val if size == 4 else (gpage << 16) | val)
        elif kind == 0:  # main
            if tag == 10:  # collection
                # Digitizer (0x01) or Pen (0x02) -- not a touchpad (0x05) or
                # touch screen (0x04), which describe X/Y the same way.
                if in_digitizer or (usages and usages[0] in (0xD0001, 0xD0002)):
                    in_digitizer += 1
            elif tag == 12:  # end collection
                in_digitizer = max(0, in_digitizer - 1)
            elif tag == 8 and in_digitizer:  # input
                for u in usages:
                    if u in (0x10030, 0x10031) and u not in found:
                        top = phys_max or log_max
                        system = unit & 0xF
                        mm = 10.0 if system == 1 else 25.4 if system == 3 else 0
                        if top > 0 and mm:
                            found[u] = top * (10 ** exp) * mm
            usages = []
        if 0x10030 in found and 0x10031 in found:
            return round(found[0x10030], 1), round(found[0x10031], 1)
    return None


def main():
    out = {}
    for dev in glob.glob("/sys/bus/hid/devices/*"):
        try:
            with open(os.path.join(dev, "report_descriptor"), "rb") as f:
                size = extent(f.read())
            if not size:
                continue
            props = dict(line.strip().split("=", 1) for line in open(os.path.join(dev, "uevent")) if "=" in line)
        except (OSError, ValueError):
            continue
        name = props.get("HID_NAME", "")
        bus = props.get("HID_ID", "").split(":")[0][-4:]
        out[name.lower().replace(" ", "-")] = {
            "name": name, "bus": BUSES.get(bus, ""), "width": size[0], "height": size[1]}
    print(json.dumps(out))


if __name__ == "__main__":
    main()
