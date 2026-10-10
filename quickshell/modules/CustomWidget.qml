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
// directory into place; removing it uninstalls it outright — toggling it
// off from the launcher (CustomWidgets.isEnabled/toggle) is the separate,
// non-destructive way to silence one without losing its files.
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
    // Forwarded to the loaded widget when it declares them (an older widget
    // that doesn't is left alone): the bar's screen, for ShellState's
    // per-screen popup tracking, and the bar's MorphPopup card, so a
    // widget's popup can be a MorphContent in the shared morphing card
    // like the built-in ones.
    property string screenName: ""
    property Item popupHost: null
    onLoaded: {
        if (item.screenName !== undefined) item.screenName = Qt.binding(() => root.screenName)
        if (item.popupHost !== undefined) item.popupHost = Qt.binding(() => root.popupHost)
    }

    source: "file://" + Quickshell.env("HOME") + "/.config/quickshell/custom/" + name + "/main.qml"
    // Toggling this off/on (rather than just hiding a loaded instance)
    // actually tears the widget's QML down — no background timers/processes
    // a merely-hidden Item would keep running.
    active: CustomWidgets.isEnabled(root.name)
    // Hides cleanly (zero width/height, so it doesn't leave a gap in
    // whatever Row it's placed in) when the widget isn't installed on this
    // machine at all, or is installed but toggled off.
    visible: status === Loader.Ready

    onStatusChanged: {
        if (status === Loader.Error) {
            console.warn("CustomWidget '" + name + "': failed to load (not installed at " + source + "?)")
        }
    }
}
