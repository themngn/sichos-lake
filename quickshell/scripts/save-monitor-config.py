#!/usr/bin/env python3
"""
Persists a live hl.monitor() change (mode, scale and/or vrr) into
~/.config/hypr/monitors.lua so it survives the next Hyprland restart --
DisplaySettings.qml's own hl.monitor() calls (resolution/refresh-rate/scale
pickers, VRR checkbox) only ever apply live.

Usage: save-monitor-config.py <output> [--mode WxH@Hz] [--scale N] [--vrr 0-3]
       save-monitor-config.py --list-vrr

--list-vrr prints {"<output>": <vrr int>, ...} for every block in the file
(0 when a block has no vrr field -- Hyprland's own default). This is the
only way to read the *configured* VRR mode back: `hyprctl monitors -j`'s
"vrr" field is whether VRR is currently engaged, not what was requested
(see DisplaySettings.qml's header), so the VRR checkbox initializes from
here instead.

Finds the hl.monitor({ ... output = "<output>" ... }) block for that output
and updates its mode/scale fields in place (adding a field that isn't
already there), leaving every other monitor's block, and the rest of the
file, untouched. Refuses to touch the file if <output> isn't found rather
than guessing where to insert a new block -- monitors.lua's layout/ordering
is genuinely per-machine (see CLAUDE.md's own note on this file), not
something a script should invent an entry for.
"""
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
    parser.add_argument("--vrr", type=int, choices=range(4))
    parser.add_argument("--list-vrr", action="store_true")
    args = parser.parse_args()

    text = MONITORS_LUA.read_text()

    if args.list_vrr:
        print(json.dumps(list_vrr(text)))
        return
    if not args.output:
        parser.error("output is required unless --list-vrr is given")

    # Non-greedy up to the first "})" after this output's own field --
    # these blocks don't nest, so that's always the block's real close.
    block_re = re.compile(
        r'hl\.monitor\(\{(?:(?!\}\)).)*?output\s*=\s*"' + re.escape(args.output) + r'".*?\}\)',
        re.DOTALL,
    )
    match = block_re.search(text)
    if not match:
        print(f"no hl.monitor block found for output {args.output!r} in {MONITORS_LUA}", file=sys.stderr)
        sys.exit(1)

    block = match.group(0)
    if args.mode:
        block = set_field(block, "mode", args.mode)
    if args.scale:
        block = set_field(block, "scale", args.scale)
    if args.vrr is not None:
        block = set_vrr(block, args.vrr)

    text = text[:match.start()] + block + text[match.end():]
    MONITORS_LUA.write_text(text)


if __name__ == "__main__":
    main()
