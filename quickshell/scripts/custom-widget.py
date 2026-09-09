#!/usr/bin/env python3
"""Installs/removes a user-local bar widget under
~/.config/quickshell/custom/<id>/ — the mechanism CustomWidget.qml loads
from and Bar.qml's Repeater enumerates (via list-custom-widgets.py). Called
from the launcher's Settings > Custom Plugins folder (CustomWidgets.qml),
but also safe to run by hand.

    custom-widget.py install <source> [id]
    custom-widget.py remove <id>

<source> is either a local folder (symlinked into place, same as the
alert-widget precedent this mechanism was built for) or a git clone URL
(https://, http://, git://, ssh://, or a git@host:path scp-style URL,
`git clone --depth 1`'d into place). Anything else is rejected rather than
guessed at. <id> defaults to <source>'s basename (.git stripped) and, like
an explicit one, is sanitized to [A-Za-z0-9._-]+ before ever being joined
into a filesystem path — this runs on a pasted string, so treat it as
untrusted input, not a trusted filename.

Always prints one JSON object to stdout ({"ok": true, "id": ...} or
{"ok": false, "error": ...}) regardless of outcome, so the QML caller can
just parse stdout; the exit code additionally mirrors "ok" for anyone
running this by hand.
"""
import json
import os
import re
import shutil
import subprocess
import sys

CUSTOM_DIR = os.path.expanduser("~/.config/quickshell/custom")

ID_RE = re.compile(r"^[A-Za-z0-9._-]+$")
GIT_URL_RE = re.compile(r"^(https?|git|ssh)://|^git@[^:]+:")


def fail(error):
    print(json.dumps({"ok": False, "error": error}))
    sys.exit(1)


def ok(id_):
    print(json.dumps({"ok": True, "id": id_}))
    sys.exit(0)


def sanitize_id(id_):
    if not id_ or id_ in (".", "..") or id_.startswith("-") or not ID_RE.match(id_):
        fail(f"invalid widget id: {id_!r}")
    return id_


def derive_id(source):
    base = source.rstrip("/")
    base = base.split("/")[-1] if "/" in base else base.split(":")[-1]
    if base.endswith(".git"):
        base = base[: -len(".git")]
    return base


def cmd_install(args):
    if not args:
        fail("usage: custom-widget.py install <source> [id]")
    source = args[0]
    id_ = sanitize_id(args[1] if len(args) > 1 else derive_id(source))
    target = os.path.join(CUSTOM_DIR, id_)

    if os.path.lexists(target):
        fail(f"'{id_}' is already installed")

    os.makedirs(CUSTOM_DIR, exist_ok=True)

    if GIT_URL_RE.match(source):
        try:
            subprocess.run(
                ["git", "clone", "--depth", "1", source, target],
                check=True, capture_output=True, text=True,
            )
        except subprocess.CalledProcessError as e:
            fail(f"git clone failed: {e.stderr.strip() or e}")
        if not os.path.isfile(os.path.join(target, "main.qml")):
            shutil.rmtree(target, ignore_errors=True)
            fail("cloned repo has no main.qml at its root")
    else:
        src_path = os.path.abspath(os.path.expanduser(source))
        if not os.path.isdir(src_path):
            fail(f"not a git URL or an existing folder: {source!r}")
        if not os.path.isfile(os.path.join(src_path, "main.qml")):
            fail(f"'{src_path}' has no main.qml")
        os.symlink(src_path, target)

    ok(id_)


def cmd_remove(args):
    if not args:
        fail("usage: custom-widget.py remove <id>")
    id_ = sanitize_id(args[0])
    target = os.path.join(CUSTOM_DIR, id_)
    if not os.path.lexists(target):
        fail(f"'{id_}' is not installed")
    if os.path.islink(target):
        os.unlink(target)
    else:
        shutil.rmtree(target)
    ok(id_)


if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in ("install", "remove"):
        fail("usage: custom-widget.py install <source> [id] | remove <id>")
    (cmd_install if sys.argv[1] == "install" else cmd_remove)(sys.argv[2:])
