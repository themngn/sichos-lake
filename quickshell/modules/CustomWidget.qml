import QtQuick
import Quickshell

// Loads a user-local bar widget from ~/.config/quickshell/custom/<name>/main.qml
// — a directory install.sh creates (mkdir -p, see its "quickshell custom
// widgets" step) but never deploys files into, since it only ever walks this
// repo's own quickshell/ tree. Anything dropped there is a sibling of this
// repo's config, the same trick HyprQuickFrame's clone already relies on, so
// a widget nobody wants in sichos-lake proper (too personal, not ready to
// publish, machine-specific) still survives `install.sh` re-runs and full
// reinstalls untouched. Enabling one is just dropping/symlinking its
// directory into place; removing it disables it — no separate config file.
// Confirmed live: this Loader only resolves its source once — it doesn't
// watch that file the way quickshell watches this repo's own tree, so
// installing/removing a widget needs a full quickshell restart (`pkill
// quickshell`, relaunch) to take effect, not just a save-triggered
// hot-reload. Adding a *new* CustomWidget-using name to this repo's own
// modules/ needs the same full restart, for the same class of reason: an
// implicit-directory-import's type list is built once at startup too.
Loader {
    id: root

    required property string name

    source: "file://" + Quickshell.env("HOME") + "/.config/quickshell/custom/" + name + "/main.qml"
    active: true
    // Hides cleanly (zero width/height, so it doesn't leave a gap in
    // whatever Row it's placed in) when the widget isn't installed on this
    // machine at all — the common case for every machine except the one(s)
    // it was actually written for.
    visible: status === Loader.Ready

    onStatusChanged: {
        if (status === Loader.Error) {
            console.warn("CustomWidget '" + name + "': failed to load (not installed at " + source + "?)")
        }
    }
}
