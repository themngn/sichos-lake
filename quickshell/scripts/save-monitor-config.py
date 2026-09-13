#!/usr/bin/env python3
"""
Persists a live hl.monitor() change (mode and/or scale) into
~/.config/hypr/monitors.lua so it survives the next Hyprland restart --
DisplaySettings.qml's own hl.monitor() calls (resolution/refresh-rate/scale
pickers) only ever apply live, the same fire-and-forget behavior already
documented for VRR in that file's header comment.

Usage: save-monitor-config.py <output> [--mode WxH@Hz] [--scale N]

Finds the hl.monitor({ ... output = "<output>" ... }) block for that output
and updates its mode/scale fields in place (adding a field that isn't
already there), leaving every other monitor's block, and the rest of the
file, untouched. Refuses to touch the file if <output> isn't found rather
than guessing where to insert a new block -- monitors.lua's layout/ordering
is genuinely per-machine (see CLAUDE.md's own note on this file), not
something a script should invent an entry for.
"""
import argparse
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


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("output")
    parser.add_argument("--mode")
    parser.add_argument("--scale")
    args = parser.parse_args()

    text = MONITORS_LUA.read_text()

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

    text = text[:match.start()] + block + text[match.end():]
    MONITORS_LUA.write_text(text)


if __name__ == "__main__":
    main()
