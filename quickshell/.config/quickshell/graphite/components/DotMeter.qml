import QtQuick
import qs.core

// Dot-matrix meter (tokens ui.meter = "dot-matrix", Telemetry):
// style "dots" = mock .sld: round dots on a 7px pitch, rows fill the height, lit = white;
// style "bars" = mock .ob/.prog: 4px bars with 2px gaps, one row.
// Drawn on a Canvas: one item, repainted only when value/size change.
Canvas {
    id: root
    property real value: 0
    property string style: "dots"
    property real pitch: style === "dots" ? 7 : 6
    property color fillColor: Theme.label
    property color emptyColor: style === "dots" ? Theme.white(0.15) : Theme.white(0.16)
    implicitHeight: style === "dots" ? 21 : 8
    onValueChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onFillColorChanged: requestPaint()
    renderStrategy: Canvas.Cooperative
    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        const v = Math.max(0, Math.min(1, value));
        if (style === "dots") {
            const cols = Math.floor(width / pitch), rows = Math.max(1, Math.floor(height / pitch));
            const lit = Math.round(v * cols);
            for (let c = 0; c < cols; c++) for (let r = 0; r < rows; r++) {
                const on = c < lit;
                ctx.fillStyle = on ? fillColor : emptyColor;
                ctx.beginPath();
                ctx.arc(c * pitch + 3.5, r * pitch + 3.5, on ? 1.7 : 1.5, 0, Math.PI * 2);
                ctx.fill();
            }
        } else {
            const cols = Math.floor((width + 2) / pitch);
            const lit = Math.round(v * cols);
            for (let c = 0; c < cols; c++) {
                ctx.fillStyle = c < lit ? fillColor : emptyColor;
                ctx.fillRect(c * pitch, 0, 4, height);
            }
        }
    }
}
