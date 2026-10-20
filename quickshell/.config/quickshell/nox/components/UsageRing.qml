import QtQuick
import qs.core

// Small progress ring for the bar (widget "usage"). Dot-matrix looks (Telemetry): 12 square dots
// on a circle, lit clockwise from 12 o'clock; other looks: a 2px arc over a faint track.
// `hollow` = no reading that applies (stale): only the track.
Canvas {
    id: root
    property real value: 0
    property color color: Theme.label
    property color trackColor: Theme.fill3
    property bool hollow: false
    property real size: 14
    implicitWidth: size
    implicitHeight: size
    renderStrategy: Canvas.Cooperative
    onValueChanged: requestPaint()
    onColorChanged: requestPaint()
    onTrackColorChanged: requestPaint()
    onHollowChanged: requestPaint()
    onWidthChanged: requestPaint()
    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        const v = hollow ? 0 : Math.max(0, Math.min(1, value));
        const cx = width / 2, cy = height / 2;
        if (Theme.dotMatrix) {
            const n = 12, r = Math.min(cx, cy) - 1.4, s = 2.2;
            const lit = Math.round(v * n);
            for (let i = 0; i < n; i++) {
                const a = -Math.PI / 2 + i * 2 * Math.PI / n;
                ctx.fillStyle = i < lit ? color : trackColor;
                ctx.fillRect(Math.round((cx + r * Math.cos(a) - s / 2) * 2) / 2, Math.round((cy + r * Math.sin(a) - s / 2) * 2) / 2, s, s);
            }
        } else {
            const r = Math.min(cx, cy) - 1.5;
            ctx.lineWidth = 2;
            ctx.strokeStyle = trackColor;
            ctx.beginPath(); ctx.arc(cx, cy, r, 0, 2 * Math.PI); ctx.stroke();
            if (v > 0) {
                ctx.strokeStyle = color;
                ctx.lineCap = Theme.square ? "butt" : "round";
                ctx.beginPath(); ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + v * 2 * Math.PI); ctx.stroke();
            }
        }
    }
}
