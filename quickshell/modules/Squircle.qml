import QtQuick
import QtQuick.Shapes

// Rectangle with continuous ("squircle", iOS/Figma-style) corners instead of
// circular arcs -- Qt Quick's Rectangle can only do the latter. Drop-in for
// a Rectangle card: same color/radius meaning, border is drawn inside the
// bounds like Rectangle's.
//
// The path is figma-squircle's corner construction (cubic -> circular arc ->
// cubic): `smoothing` 0 is a plain rounded rect, 0.6 is Apple's, and the
// corner then extends (1 + smoothing) * radius along each edge. When the
// shape is too small for that, smoothing is reduced first, then radius --
// same budget rule as figma-squircle (half the shorter side).
Item {
    id: root

    property color color: "transparent"
    property real radius: 0
    property real smoothing: Theme.cornerSmoothing
    property color borderColor: "transparent"
    property real borderWidth: 0

    Shape {
        anchors.fill: parent
        // Analytic antialiasing; the default geometry renderer only gets
        // smooth edges with multisampling.
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: root.color
            strokeColor: root.borderWidth > 0 ? root.borderColor : "transparent"
            strokeWidth: root.borderWidth > 0 ? root.borderWidth : -1
            joinStyle: ShapePath.RoundJoin

            PathSvg { path: root._path(root.width, root.height, root.radius, root.smoothing, root.borderWidth) }
        }
    }

    function _path(w, h, r, s, bw) {
        // Shape strokes are centered on the path; inset it by half the
        // stroke so the border lands inside the item like Rectangle's.
        const i = bw > 0 ? bw / 2 : 0
        w -= 2 * i
        h -= 2 * i
        if (w <= 0 || h <= 0) return ""
        const budget = Math.min(w, h) / 2
        r = Math.max(0, Math.min(r - i, budget))
        if (r <= 0)
            return `M ${i} ${i} h ${w} v ${h} h ${-w} Z`

        s = Math.max(0, Math.min(s, budget / r - 1))
        const p = Math.min((1 + s) * r, budget)
        const rad = Math.PI / 180
        const arcMeasure = 90 * (1 - s)
        const arc = Math.sin(arcMeasure / 2 * rad) * r * Math.SQRT2
        const alpha = (90 - arcMeasure) / 2
        const p3p4 = r * Math.tan(alpha / 2 * rad)
        const beta = 45 * s
        const c = p3p4 * Math.cos(beta * rad)
        const d = c * Math.tan(beta * rad)
        const b = (p - arc - c - d) / 3
        const a = 2 * b
        const ab = a + b, abc = a + b + c, bc = b + c

        return `M ${i + w - p} ${i}`
            + ` c ${a} 0 ${ab} 0 ${abc} ${d} a ${r} ${r} 0 0 1 ${arc} ${arc} c ${d} ${c} ${d} ${bc} ${d} ${abc}`
            + ` L ${i + w} ${i + h - p}`
            + ` c 0 ${a} 0 ${ab} ${-d} ${abc} a ${r} ${r} 0 0 1 ${-arc} ${arc} c ${-c} ${d} ${-bc} ${d} ${-abc} ${d}`
            + ` L ${i + p} ${i + h}`
            + ` c ${-a} 0 ${-ab} 0 ${-abc} ${-d} a ${r} ${r} 0 0 1 ${-arc} ${-arc} c ${-d} ${-c} ${-d} ${-bc} ${-d} ${-abc}`
            + ` L ${i} ${i + p}`
            + ` c 0 ${-a} 0 ${-ab} ${d} ${-abc} a ${r} ${r} 0 0 1 ${arc} ${-arc} c ${c} ${-d} ${bc} ${-d} ${abc} ${-d}`
            + " Z"
    }
}
