#!/usr/bin/env python3
"""
Persists a live hl.monitor() change (mode, scale, position and/or vrr) into
~/.config/hypr/monitors.lua so it survives the next Hyprland restart --
DisplaySettings.qml's own hl.monitor() calls (resolution/refresh-rate/scale
pickers, VRR checkbox) only ever apply live.

Usage: save-monitor-config.py <output> [--mode WxH@Hz] [--scale N] [--position XxY] [--vrr 0-3]
       save-monitor-config.py --list-vrr

--list-vrr prints {"<output>": <vrr int>, ...} for every block in the file
(0 when a block has no vrr field -- Hyprland's own default). This is the
only way to read the *configured* VRR mode back: `hyprctl monitors -j`'s
"vrr" field is whether VRR is currently engaged, not what was requested
(see DisplaySettings.qml's header), so the VRR checkbox initializes from
here instead.

Finds the hl.monitor({ ... output = "<output>" ... }) block for that output
and updates its mode/scale/position fields in place (adding a field that isn't
already there), leaving every other monitor's block, and the rest of the
file, untouched. An output with no block of its own (one only the catch-all
`output = ""` rule covers, e.g. a monitor plugged in after monitors.lua was
written) used to be refused, so every Display page change to it was lost on
the next Hyprland start; it now gets a block of its own, seeded from its live
`hyprctl monitors` state (so the fields not being changed keep their current
values) and placed before the catch-all. Virtual outputs (sichlink's
SICHLINK-1, other HEADLESS-*) are still refused: they're created on demand
and a fixed rule for them would only apply to whatever reuses the name.
"""
import fcntl
import subprocess
import argparse
import json
import re
import sys
from pathlib import Path

MONITORS_LUA = Path.home() / ".config/hypr/monitors.lua"


def set_field(block, field, value):
    field_re = re.compile(r'(' + re.escape(field) + r'\s*=\s*)"[^"]*"')
    if field_re.search(block):
        return field_re.sub(lambda m: m.group(1) + '"' + value + '"', block)
    # No existing field to preserve alignment on -- insert right after the
    # opening brace, plain 4-space indent matching this file's own style.
    return re.sub(r'(hl\.monitor\(\{)', r'\1\n    ' + field + ' = "' + value + '",', block, count=1)


# vrr is an unquoted integer (hl.monitor's `vrr? integer|boolean`), unlike
# mode/scale. Any trailing `-- comment` on that line is dropped when the
# value changes -- it explained the *old* value (e.g. why VRR was turned off
# for a flickering panel) and would be actively misleading next to a new one.
VRR_RE = re.compile(r'(vrr\s*=\s*)(\d+|true|false)(,?)[ \t]*(--[^\n]*)?')


def set_vrr(block, value):
    if VRR_RE.search(block):
        return VRR_RE.sub(lambda m: m.group(1) + str(value) + m.group(3), block, count=1)
    return re.sub(r'(hl\.monitor\(\{)', r'\1\n    vrr = ' + str(value) + ',', block, count=1)


def list_vrr(text):
    result = {}
    for block in re.findall(r'hl\.monitor\(\{.*?\}\)', text, re.DOTALL):
        out = re.search(r'output\s*=\s*"([^"]*)"', block)
        if not out:
            continue
        v = VRR_RE.search(block)
        raw = v.group(2) if v else "0"
        result[out.group(1)] = {"true": 1, "false": 0}.get(raw) if raw in ("true", "false") else int(raw)
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("output", nargs="?")
    parser.add_argument("--mode")
    parser.add_argument("--scale")
    parser.add_argument("--position")
    parser.add_argument("--vrr", type=int, choices=range(4))
    parser.add_argument("--list-vrr", action="store_true")
    args = parser.parse_args()

    if args.list_vrr:
        print(json.dumps(list_vrr(MONITORS_LUA.read_text())))
        return
    if not args.output:
        parser.error("output is required unless --list-vrr is given")

    # DisplaySettings.qml fires one of these per change, detached -- a
    # resolution pick right after a scale pick (or a drag that moves two
    # monitors) runs two at once, and the later read-modify-write would
    # drop the earlier one's change.
    with open(MONITORS_LUA, "r+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        update(args)


def live_block(output):
    """A new hl.monitor block for `output` from its current live state, or None."""
    if re.match(r"(HEADLESS|SICHLINK)-", output):
        return None
    try:
        mons = json.loads(subprocess.run(["hyprctl", "monitors", "all", "-j"],
                                         capture_output=True, text=True, timeout=5).stdout)
    except (OSError, ValueError, subprocess.SubprocessError):
        return None
    m = next((m for m in mons if m.get("name") == output), None)
    if not m:
        return None
    rate = f"{m['refreshRate']:.2f}".rstrip("0").rstrip(".")
    scale = f"{m['scale']:.2f}".rstrip("0").rstrip(".")
    return ("hl.monitor({\n"
            f'    output   = "{output}",\n'
            f'    mode     = "{m["width"]}x{m["height"]}@{rate}",\n'
            f'    position = "{m["x"]}x{m["y"]}",\n'
            f'    scale    = "{scale}",\n'
            "})")


def update(args):
    text = MONITORS_LUA.read_text()

    # Non-greedy up to the first "})" after this output's own field --
    # these blocks don't nest, so that's always the block's real close.
    block_re = re.compile(
        r'hl\.monitor\(\{(?:(?!\}\)).)*?output\s*=\s*"' + re.escape(args.output) + r'".*?\}\)',
        re.DOTALL,
    )
    match = block_re.search(text)
    if not match:
        block = live_block(args.output)
        if not block:
            print(f"no hl.monitor block found for output {args.output!r} in {MONITORS_LUA}", file=sys.stderr)
            sys.exit(1)
        # Before the catch-all (and the comment line right above it, if
        # any), else at the end.
        fallback = re.search(r'(?:^--[^\n]*\n)?hl\.monitor\(\{(?:(?!\}\)).)*?output\s*=\s*""', text,
                             re.DOTALL | re.MULTILINE)
        at = fallback.start() if fallback else len(text.rstrip("\n")) + 1
        text = text[:at] + block + "\n\n" + text[at:]
        match = block_re.search(text)

    block = match.group(0)
    if args.mode:
        block = set_field(block, "mode", args.mode)
    if args.scale:
        block = set_field(block, "scale", args.scale)
    if args.position:
        block = set_field(block, "position", args.position)
    if args.vrr is not None:
        block = set_vrr(block, args.vrr)

    text = text[:match.start()] + block + text[match.end():]
    MONITORS_LUA.write_text(text)


if __name__ == "__main__":
    main()
