.pragma library

// Best-effort window-class -> icon-theme-name mapping for common apps whose
// wm class doesn't already match a freedesktop icon name 1:1.
var classIconMap = {
    "org.mozilla.firefox": "firefox",
    "firefoxdeveloperedition": "firefox",
    "code": "visual-studio-code",
    "code - oss": "vscodium",
    "codium": "vscodium",
    "vesktop": "discord",
    "org.kde.dolphin": "system-file-manager",
    "google-chrome": "google-chrome",
    "chromium-browser": "chromium",
    "steam": "steam",
    "steamwebhelper": "steam",
}

function iconNameForClass(cls) {
    var key = (cls || "").toLowerCase()
    if (classIconMap[key]) return classIconMap[key]
    return key
}
