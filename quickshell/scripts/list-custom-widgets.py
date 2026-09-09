#!/usr/bin/env python3
"""Enumerates installed user-local bar widgets for the quickshell launcher
and Bar.qml (CustomWidgets.qml).

The directory itself is the source of truth (see CustomWidget.qml /
custom-widget.py's own comments) — no separate registry file to fall out of
sync with it. Emits a JSON array of {id, label}, sorted by id, for every
~/.config/quickshell/custom/<id>/main.qml found; a dir without a main.qml
(mid-clone, or just broken) is silently skipped, same as CustomWidget.qml
already does at load time.
"""
import glob
import json
import os

CUSTOM_DIR = os.path.expanduser("~/.config/quickshell/custom")


def display_name(id_):
    return id_.replace("-", " ").replace("_", " ").title()


widgets = []
for main_qml in sorted(glob.glob(os.path.join(CUSTOM_DIR, "*", "main.qml"))):
    id_ = os.path.basename(os.path.dirname(main_qml))
    # "label", not "name" -- QML's Repeater can expose a JS-array model
    # item's own keys as context properties inside the delegate, which would
    # collide with CustomWidget.qml's own `required property string name`
    # (Bar.qml's delegate binds that from modelData.id). Sidesteps the
    # landmine rather than relying on modelData-qualified access alone.
    widgets.append({"id": id_, "label": display_name(id_)})

print(json.dumps(widgets))
