pragma Singleton
import QtQuick

// Shared state that needs to be visible from more than one top-level window
// (the per-screen Bar and the single Launcher instance), so it can't just
// live as a local property on either one.
QtObject {
    property bool idleActive: false
}
