#!/usr/bin/env python3
"""Pen button bindings for the Control Center's Pen tablet page.

Hyprland can't remap a pen's buttons (its only tablet-tool button options,
input.tablettool.eraser_button_*, are for libinput's separate eraser
button), and OpenTabletDriver can't open a Bluetooth tablet at all. So this
sits below libinput instead: it grabs the pen's evdev node (EVIOCGRAB, so
libinput stops seeing it), forwards every event through a uinput copy of
the device -- same capabilities and axis resolutions, so Hyprland's tablet
settings, active area in mm included, apply to the copy unchanged -- and
swaps the two side buttons' events for whatever tablet.json's "buttons"
say. Run by TabletSettings.qml while any binding isn't "default"; needs
udev/71-sichos-tablet.rules for the evdev node and /dev/uinput.

The pens this was written for (One by Wacom CTC-6110WL over Bluetooth,
driven by hid-generic) have one real button and one "eraser" button: the
lower one is BTN_STYLUS, the upper one doesn't press a button at all but
switches the tool -- BTN_TOOL_PEN 0 + BTN_TOOL_RUBBER 1 while held (HID
Invert/Eraser, the Windows pen protocol). So "upper" means the rubber
switch, turned back into a plain pen plus the bound action.

Actions: default (what the pen does by itself: lower = BTN_STYLUS, which
apps treat as middle click; upper = eraser), right (BTN_STYLUS2, right
click), middle (BTN_STYLUS), eraser (the tool switch), undo / redo
(Ctrl+Z / Ctrl+Shift+Z), space / ctrl / shift / alt (held while the button
is: pan, colour picker... in drawing apps), off.

Waits for the tablet to appear (a Bluetooth one drops off the bus whenever
it sleeps) by watching /dev/input, and starts over when it disappears.
"""
import json
import os
import select
import sys
import time

import evdev
from evdev import UInput, ecodes as E

CONFIG = os.path.expanduser("~/.config/quickshell/tablet.json")
SUFFIX = " (SichOS bindings)"

KEYS = {
    "undo": [E.KEY_LEFTCTRL, E.KEY_Z],
    "redo": [E.KEY_LEFTCTRL, E.KEY_LEFTSHIFT, E.KEY_Z],
    "space": [E.KEY_SPACE],
    "ctrl": [E.KEY_LEFTCTRL],
    "shift": [E.KEY_LEFTSHIFT],
    "alt": [E.KEY_LEFTALT],
}
TAPS = {"undo", "redo"}  # pressed and released at once; the rest are held


def load_bindings():
    try:
        with open(CONFIG) as f:
            b = json.load(f).get("buttons") or {}
    except (OSError, ValueError):
        b = {}
    return {"lower": b.get("lower", "default"), "upper": b.get("upper", "default")}


def find_pen():
    for path in evdev.list_devices():
        try:
            dev = evdev.InputDevice(path)
        except OSError:
            continue
        caps = dev.capabilities()
        keys = caps.get(E.EV_KEY, [])
        abs_codes = [a[0] for a in caps.get(E.EV_ABS, [])]
        if (not dev.name.endswith(SUFFIX) and E.BTN_TOOL_PEN in keys
                and E.ABS_PRESSURE in abs_codes and E.BTN_STYLUS in keys):
            return dev
        dev.close()
    return None


class Remapper:
    def __init__(self, dev):
        self.dev = dev
        caps = dev.capabilities(absinfo=True)
        caps.pop(E.EV_SYN, None)
        keys = set(caps.get(E.EV_KEY, []))
        keys |= {E.BTN_TOOL_PEN, E.BTN_TOOL_RUBBER, E.BTN_STYLUS, E.BTN_STYLUS2}
        caps[E.EV_KEY] = sorted(keys)
        info = dev.info
        # input_props carries INPUT_PROP_POINTER/DIRECT: libinput reads it to
        # tell a screen tablet from an external one.
        self.pen = UInput(caps, name=dev.name + SUFFIX, vendor=info.vendor, product=info.product,
                          version=info.version, bustype=info.bustype, input_props=dev.input_props())
        all_keys = sorted({k for ks in KEYS.values() for k in ks})
        self.kbd = UInput({E.EV_KEY: all_keys}, name="SichOS pen shortcuts")
        self.bindings = load_bindings()
        self.mtime = self._mtime()
        self.rubber = False     # the hardware rubber switch is held
        self.held = {}          # button -> action currently pressed
        self.pending = []
        self.frame = []

    def _mtime(self):
        try:
            return os.stat(CONFIG).st_mtime
        except OSError:
            return 0

    def reload(self):
        m = self._mtime()
        if m != self.mtime:
            self.mtime = m
            self.bindings = load_bindings()

    def emit(self, type_, code, value):
        self.pending.append((type_, code, value))

    def press(self, which, down):
        action = self.held.pop(which, None) if not down else self.bindings[which]
        if down:
            self.held[which] = action
        if action is None or action == "off":
            return
        if action == "right":
            self.emit(E.EV_KEY, E.BTN_STYLUS2, int(down))
        elif action == "middle":
            self.emit(E.EV_KEY, E.BTN_STYLUS, int(down))
        elif action == "eraser":
            # A tool switch inside one frame, like the hardware's own.
            self.emit(E.EV_KEY, E.BTN_TOOL_PEN, int(not down))
            self.emit(E.EV_KEY, E.BTN_TOOL_RUBBER, int(down))
        elif action in KEYS:
            if action in TAPS:
                if down:
                    for k in KEYS[action]:
                        self.kbd.write(E.EV_KEY, k, 1)
                    for k in reversed(KEYS[action]):
                        self.kbd.write(E.EV_KEY, k, 0)
                    self.kbd.syn()
            else:
                for k in (KEYS[action] if down else reversed(KEYS[action])):
                    self.kbd.write(E.EV_KEY, k, int(down))
                self.kbd.syn()

    def handle(self, ev):
        """Collects a frame (up to SYN_REPORT), then translates it whole:
        the rubber switch comes as PEN 0 + RUBBER 1 in one frame, and
        deciding on PEN 0 before seeing RUBBER 1 would let the pen leave."""
        if not (ev.type == E.EV_SYN and ev.code == E.SYN_REPORT):
            self.frame.append((ev.type, ev.code, ev.value))
            return
        frame, self.frame = self.frame, []
        lower_bound = self.bindings["lower"] != "default"
        upper_bound = self.bindings["upper"] not in ("default", "eraser")
        rubber = [v for t, c, v in frame if t == E.EV_KEY and c == E.BTN_TOOL_RUBBER]
        pen = [v for t, c, v in frame if t == E.EV_KEY and c == E.BTN_TOOL_PEN]
        for t, c, v in frame:
            if t == E.EV_KEY and c == E.BTN_STYLUS and lower_bound:
                self.press("lower", v == 1)
            elif t == E.EV_KEY and c in (E.BTN_TOOL_RUBBER, E.BTN_TOOL_PEN) and upper_bound and (rubber or self.rubber):
                pass  # handled below
            else:
                self.emit(t, c, v)
        if upper_bound and rubber:
            down = rubber[-1] == 1
            if down and not self.rubber:
                if not pen:  # came into range with the button already held
                    self.emit(E.EV_KEY, E.BTN_TOOL_PEN, 1)
                self.press("upper", True)
            elif not down and self.rubber:
                self.press("upper", False)
                if not pen or pen[-1] == 0:  # let go out of range: the pen left too
                    self.emit(E.EV_KEY, E.BTN_TOOL_PEN, 0)
            self.rubber = down
        elif upper_bound and self.rubber and pen:
            pass  # PEN changes while the switch is held: the pen stays as it is
        for t, c, v in self.pending:
            self.pen.write(t, c, v)
        self.pen.syn()
        self.pending = []

    def run(self):
        self.dev.grab()
        try:
            while True:
                r, _, _ = select.select([self.dev.fd], [], [], 1.0)
                self.reload()
                if not r:
                    continue
                for ev in self.dev.read():
                    self.handle(ev)
        finally:
            for which in list(self.held):
                self.press(which, False)
            for dev in (self.pen, self.kbd):
                try:
                    dev.close()
                except OSError:
                    pass


def main():
    while True:
        dev = find_pen()
        if dev is None:
            time.sleep(2)
            continue
        print(f"remapping {dev.path} ({dev.name})", file=sys.stderr, flush=True)
        try:
            Remapper(dev).run()
        except OSError as e:  # the tablet went away (sleep, unplug)
            print(f"lost {dev.name}: {e}", file=sys.stderr, flush=True)
        try:
            dev.close()
        except OSError:
            pass
        time.sleep(1)


if __name__ == "__main__":
    main()
