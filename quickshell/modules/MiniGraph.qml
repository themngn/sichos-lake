import QtQuick

// History graph: area + line, newest sample at the right edge, spaced for
// SystemStats.historyLength samples (the hub's system strip, the Wi-Fi
// tile's traffic).
//
// It scrolls instead of jumping: when a sample arrives, the curve is drawn
// one step further right (the new point just past the edge, the previous
// newest exactly where it was) and `shift` eases that step back to 0 over
// one sample interval, so the line slides left continuously. The point that
// fell off the left end is kept for the slide, or the left edge would open
// a one-step gap each time.
Canvas {
    id: mg
    property var history: []
    property real maxValue: 1   // 0 = auto (largest sample)
    property color tint: Theme.accent

    property var _points: []
    property var _last: []
    property real shift: 0      // in steps, 1 -> 0 after each sample
    readonly property real step: width / (SystemStats.historyLength - 1)

    onHistoryChanged: {
        const h = mg.history || []
        const old = mg._last
        mg._last = h
        // A plain append (same series, one more sample, maybe one dropped):
        // slide it in. Anything else (first fill, a different series) just
        // draws in place.
        const appended = old.length > 0 && h.length > 0
            && (h.length === old.length + 1 || (h.length === old.length && h.length >= SystemStats.historyLength))
            && h[h.length - 2] === old[old.length - 1]
        if (appended && h.length === old.length) mg._points = [old[0]].concat(h)
        else mg._points = h
        slide.stop()
        if (appended) {
            mg.shift = 1
            slide.start()
        } else {
            mg.shift = 0
        }
        requestPaint()
    }
    onShiftChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    NumberAnimation {
        id: slide
        target: mg
        property: "shift"
        to: 0
        duration: SystemStats.sampleInterval
    }

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        const h = mg._points
        if (!h || h.length < 2) return
        const top = mg.maxValue > 0 ? mg.maxValue : Math.max(1, ...h)
        const xEnd = width + mg.shift * mg.step
        const x = i => xEnd - (h.length - 1 - i) * mg.step
        const y = v => height - Math.min(1, v / top) * height
        ctx.beginPath()
        ctx.moveTo(x(0), height)
        for (let i = 0; i < h.length; i++) ctx.lineTo(x(i), y(h[i]))
        ctx.lineTo(x(h.length - 1), height)
        ctx.closePath()
        ctx.fillStyle = Qt.rgba(mg.tint.r, mg.tint.g, mg.tint.b, 0.3)
        ctx.fill()
        ctx.beginPath()
        ctx.moveTo(x(0), y(h[0]))
        for (let i = 1; i < h.length; i++) ctx.lineTo(x(i), y(h[i]))
        ctx.strokeStyle = mg.tint
        ctx.lineWidth = 1.5
        ctx.stroke()

    }

    // Faint dotted line at the top of a fixed scale (100% for CPU/RAM/GPU);
    // an auto-scaled graph (network) has no meaningful top, so none. 1px
    // dots on whole pixels, so it stays crisp.
    Repeater {
        model: mg.maxValue > 0 ? Math.ceil(mg.width / 3) : 0
        delegate: Rectangle {
            required property int index
            x: index * 3
            width: 1
            height: 1
            color: Qt.rgba(mg.tint.r, mg.tint.g, mg.tint.b, 0.4)
        }
    }
}
