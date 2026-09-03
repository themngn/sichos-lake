#!/usr/bin/env python3
"""
Reports which currently connected monitors' EDIDs advertise HDR support, for
HdrPopup.qml to grey out monitors that can never do HDR regardless of what
the user ticks.

hyprctl/wlr-randr expose no "supports HDR" field (checked live on this
machine, Hyprland 0.56.2) -- the only way Hyprland itself reveals whether a
monitor accepted an HDR request is `colorManagementPreset` staying "srgb"
after a live `hl.monitor({cm="hdr"})` call, which means actually requesting
it (a real, visible mode change) just to find out. Reading the EDID instead
is a pure, side-effect-free query: per CTA-861.3, a display that supports
HDR10 carries an "HDR Static Metadata Data Block" (extended tag 0x06) inside
its CTA-861 extension block. This only checks for that block's presence, not
which EOTFs/luminance ranges it advertises -- good enough to grey out a
"this monitor can't do HDR at all" case, which is the point.

Emits one JSON line: {"<monitor-name>": true|false|null, ...} -- null means
"couldn't tell" (EDID unreadable, or has no CTA-861 extension at all, e.g.
some older/basic panels or a Writeback pseudo-output) and should NOT be
treated as "unsupported" by the caller.
"""
import glob
import json


def hdr_capable(edid_path):
    try:
        with open(edid_path, "rb") as f:
            data = f.read()
    except OSError:
        return None
    if len(data) < 128:
        return None

    num_ext = data[126]
    found_cta = False
    for i in range(num_ext):
        start = 128 + i * 128
        block = data[start:start + 128]
        if len(block) < 128 or block[0] != 0x02:  # 0x02 == CTA-861 extension tag
            continue
        found_cta = True

        dtd_offset = block[2]  # start of detailed timing descriptors; 0 == none
        if dtd_offset == 0:
            continue

        pos = 4  # data block collection starts right after the 4-byte header
        while pos < dtd_offset and pos < 127:
            header = block[pos]
            tag = (header >> 5) & 0x07
            length = header & 0x1F
            if tag == 0x07 and length >= 1 and pos + 1 < 128:  # 0x07 == extended tag block
                ext_tag = block[pos + 1]
                if ext_tag == 0x06:  # HDR Static Metadata Data Block
                    return True
            pos += 1 + length
    return False if found_cta else None


def main():
    result = {}
    for path in glob.glob("/sys/class/drm/card*-*/edid"):
        name = path.split("/")[-2].split("-", 1)[1]
        capable = hdr_capable(path)
        # A connector can show up more than once across cards/renders in
        # theory -- first non-null answer wins rather than a later None
        # overwriting a real result.
        if name not in result or result[name] is None:
            result[name] = capable
    print(json.dumps(result))


if __name__ == "__main__":
    main()
