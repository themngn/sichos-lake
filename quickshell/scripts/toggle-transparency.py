#!/usr/bin/env python3
"""Switch kitty between semi-transparent and fully opaque.

Persistence and "what's the current mode" both live in kitty.conf's own
background_opacity line (same trick ShellState.qml uses for hyprsunset.conf's
temperature) rather than a separate state file — one source of truth, and it
survives a quickshell restart for free. Already-open kitty windows don't
re-read their config on their own, so each one's live opacity is pushed
separately over its remote-control socket (see kitty.conf's
allow_remote_control/listen_on comment) — windows launched before that config
change existed won't have a socket to reach, so they need one restart to pick
up the toggle at all; every later toggle updates them live.

Called from Bar.qml's TransparencyToggle with the target mode ("opaque" or
"semi") — the bar owns and flips its own ShellState.transparencyOpaque
immediately for a snappy icon, so this script only needs to make the rest of
the system agree with that, not report back.
"""
import glob
import re
import subprocess
import sys
from pathlib import Path

KITTY_CONF = Path.home() / ".config/kitty/kitty.conf"
OPACITY = {"semi": "0.8", "opaque": "1.0"}


def main() -> None:
    mode = sys.argv[1] if len(sys.argv) > 1 else "semi"
    opacity = OPACITY.get(mode, OPACITY["semi"])

    text = KITTY_CONF.read_text()
    text = re.sub(r"^background_opacity\s+[\d.]+", f"background_opacity {opacity}",
                  text, count=1, flags=re.MULTILINE)
    KITTY_CONF.write_text(text)

    for sock in glob.glob("/tmp/kitty-sichos-*"):
        subprocess.run(
            ["kitty", "@", "--to", f"unix:{sock}", "set-background-opacity", opacity],
            capture_output=True,
        )


if __name__ == "__main__":
    main()
