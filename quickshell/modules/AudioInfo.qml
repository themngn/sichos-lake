pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Audio devices and the apps using them, for the Control Center's Sound card.
// Everything that costs something -- binding every node's properties, the
// mic's peak monitor -- only runs while `active` (the card is open); the
// rest of the time this is a few filtered lists over Pipewire.nodes.
QtObject {
    id: root

    // Bound by the Control Center to "Sound card open".
    property bool active: false
    // The mic level meter: its own toggle on top of `active`, since the peak
    // monitor opens a capture stream (see _peak below).
    property bool meterEnabled: false

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource

    // Same split as QuickSettings' root.sinks/sources: hardware nodes only.
    readonly property var audioNodes: Pipewire.nodes.values.filter(n => n.audio && !n.isStream)
    readonly property var sinks: root.audioNodes.filter(n => n.isSink)
    readonly property var sources: root.audioNodes.filter(n => !n.isSink)

    readonly property var _streams: Pipewire.nodes.values.filter(n => n.audio && n.isStream)

    // Node properties (device.bus, application.name, ...) stay empty until a
    // tracker binds the node, and an untracked link group's state reads
    // Unlinked forever -- so bind every device, stream and link while open.
    property PwObjectTracker _tracker: PwObjectTracker {
        objects: root.active ? root.audioNodes.concat(root._streams, Pipewire.linkGroups.values) : []
    }

    // Apps playing to any sink, one entry per app: [{name, node}], `node`
    // being its first active stream (Firefox opens one per tab). Both lists
    // read empty while !active: untracked links never report Active.
    readonly property var outputStreams: root._group(root._streams.filter(n =>
        (n.type & PwNodeType.AudioOutStream) === PwNodeType.AudioOutStream
        && !root._isSpeechDispatcher(n) && root._isLive(n)))

    // Apps capturing from any source, minus our own peak monitor's stream.
    readonly property var inputStreams: root._group(root._streams.filter(n =>
        (n.type & PwNodeType.AudioInStream) === PwNodeType.AudioInStream
        && !root._isOwn(n) && root._isLive(n)))

    // speech-dispatcher keeps an always-running (silent) dummy stream open.
    function _isSpeechDispatcher(n) {
        const p = n.properties || {}
        return (p["application.name"] || n.name || "").startsWith("speech-dispatcher")
    }

    // The peak monitor's stream has no application.process.id; it shows up
    // as node.name "quickshell", application.name "Quickshell Peak Detect".
    function _isOwn(n) {
        const p = n.properties || {}
        return Number(p["application.process.id"]) === Quickshell.processId
            || (n.name || "").toLowerCase() === "quickshell"
            || (p["application.name"] || "").toLowerCase().startsWith("quickshell")
    }

    // A paused (corked) stream keeps its node and links: Firefox's paused
    // tabs sit at Init/Paused, speech-dispatcher's idle dummy at Init. Only an
    // Active link means audio is flowing. A stream with no links yet counts
    // as live so a just-started app isn't hidden.
    function _isLive(n) {
        let linked = false
        for (const g of Pipewire.linkGroups.values) {
            if (g.source !== n && g.target !== n) continue
            if (g.state === PwLinkState.Active) return true
            linked = true
        }
        return !linked
    }

    function _appName(n) {
        const p = n.properties || {}
        return p["application.name"] || n.description || n.name || "Unknown"
    }

    function _group(nodes) {
        const out = []
        const seen = {}
        for (const n of nodes) {
            const name = root._appName(n)
            if (seen[name]) continue
            seen[name] = true
            out.push({ name: name, node: n })
        }
        return out
    }

    // A label short enough for a device chip (~14 chars). Node descriptions
    // run to 50+ chars ("HyperX Cloud Stinger Core Wireless DTS Analog
    // Stereo") and node.nick is cut mid-word, so build one per bus.
    function shortName(n) {
        if (!n) return ""
        const p = n.properties || {}
        const desc = n.description || n.nickname || n.name || ""
        const profile = p["device.profile.description"] || ""
        const fit = s => s.length <= 14 ? s : s.slice(0, 13).trim() + "…"

        // HDMI/DP: the nick is the monitor's name ("P27h-20").
        if (/hdmi|displayport|iec958/i.test(n.name + " " + profile))
            return fit(n.nickname || p["node.nick"] || "Display")
        if (p["device.api"] === "bluez5" || (n.name || "").startsWith("bluez"))
            return fit(p["device.alias"] || p["device.description"] || desc)
        if (p["device.bus"] === "usb") {
            // Strip the profile suffix ("Analog Stereo", "Mono") then keep the
            // first two words -- vendor + model is enough to tell devices apart.
            const base = profile && desc.endsWith(profile) ? desc.slice(0, -profile.length) : desc
            return fit(base.trim().split(/\s+/).slice(0, 2).join(" "))
        }
        // Anything else on PCI is the built-in codec.
        if (p["device.bus"] === "pci")
            return n.isSink ? "Speakers" : "Microphone"
        return fit(desc)
    }

    // A Nerd Font MD glyph for the device's kind.
    function typeGlyph(n) {
        if (!n) return ""
        const p = n.properties || {}
        const hay = [n.name, n.description, p["device.form_factor"], p["device.icon-name"]].join(" ").toLowerCase()
        if (/hdmi|displayport/.test(hay)) return "\u{f0379}"                  // nf-md-monitor
        if (/headset/.test(hay) || root._isUsbHeadset(n)) return "\u{f02ce}"  // nf-md-headset
        if (/headphone/.test(hay)) return "\u{f02cb}"                         // nf-md-headphones
        if (p["device.api"] === "bluez5" || hay.startsWith("bluez")) return "\u{f00af}" // nf-md-bluetooth
        return n.isSink ? "\u{f04c3}" : "\u{f036c}"                           // nf-md-speaker / microphone
    }

    // USB audio rarely says "headset" (the HyperX's icon is a generic
    // audio-card-analog), but a USB card that is both a sink and a source is
    // one -- a USB DAC or speaker has no mic. Both nodes share device.id.
    function _isUsbHeadset(n) {
        const p = n.properties || {}
        const id = p["device.id"] || ""
        if (p["device.bus"] !== "usb" || !id) return false
        const other = n.isSink ? root.sources : root.sinks
        return other.some(o => (o.properties || {})["device.id"] === id)
    }

    function setDefaultSink(n) { if (n) Pipewire.preferredDefaultAudioSink = n }
    function setDefaultSource(n) { if (n) Pipewire.preferredDefaultAudioSource = n }

    // The peak monitor opens its own capture stream, which wakes the device
    // and would force a Bluetooth headset from A2DP into HFP -- so never on
    // bluez, and only while the meter is actually on screen.
    readonly property bool _meterOn: root.active && root.meterEnabled && !!root.source
        && !(root.source.name || "").startsWith("bluez")
    property PwNodePeakMonitor _peak: PwNodePeakMonitor {
        node: root._meterOn ? root.source : null
        enabled: root._meterOn
    }
    // Peak is linear amplitude, which leaves speech in the bottom third of the
    // bar; sqrt spreads it out.
    readonly property real micLevel: root._meterOn ? Math.sqrt(Math.max(0, Math.min(1, root._peak.peak))) : 0
}
