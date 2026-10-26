pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import qs.core
import qs.components
import qs.services

// The fanned-out apps of a dock folder (DockFolder's surface content; a plain Item so it can be
// rendered on its own). The bounding box of the arc: name pills left of the tile, the lean to the
// right; x is set here from fan.ctl.cx, the caller sets y.
// File stacks: entries with a `kind` ("file" | "dir" | "open") show a thumbnail or a file-type
// icon instead of an app icon. Thumbnails come from the freedesktop cache
// (~/.cache/thumbnails/{normal,large}/<md5 of the file URI>.png, written by file managers), else
// for a raster image the file itself (decoded at <= 128 px, off the GUI thread); anything else
// (or a failed load) gets its mime-type icon. Images only load while the fan is up.
Item {
    id: fan
    required property var ctl                    // the DockFolder (apps, geometry, pick, sel...)
    property real t: 1                           // 0 = all icons in the tile, 1 = fanned out
    property real total: 400                     // ms the whole open takes (stagger included)
    property real availableWidth: 1920
    readonly property alias hovered: fanHover.hovered
    // ctl: iconSize, cx (tile centre x), apps, open, keyboardNow, sel, popupId, pick(app),
    //      isStack, dragBegan(), dragEnded()

    // ---- arc geometry (i = 0 is the bottom app) ----
    readonly property real step: ctl.iconSize + 12
    // the lean flattens for tall fans so a long stack doesn't run off to the right
    readonly property real bend: Math.min(2.4, 150 / Math.pow(Math.max(1, ctl.apps.length - 1), 2))
    function lean(i) { return bend * i * i; }                        // x offset from the tile centre
    function tilt(i) { return Math.atan(2 * bend * i / step) * 180 / Math.PI * 0.35; }
    readonly property real fanH: ctl.apps.length * step + 8
    readonly property real fanRight: lean(Math.max(0, ctl.apps.length - 1)) + ctl.iconSize / 2 + 16
    readonly property real pillMax: ctl.isStack ? 210 : 160
    readonly property real labelRoom: pillMax + 38 + fan.ctl.iconSize / 2
    x: Math.max(4, fan.ctl.cx - labelRoom)
    width: Math.min(fan.availableWidth - x - 4, fan.ctl.cx - x + fan.fanRight)
    height: fan.fanH + 12
    HoverHandler { id: fanHover; onHoveredChanged: if (hovered && fan.ctl.open) fan.ctl.keyboardNow = true }

    // file-type icon (icon theme mime names, generic fallback)
    function extOf(n) { const m = /\.([A-Za-z0-9]+)$/.exec(n); return m ? m[1].toLowerCase() : ""; }
    readonly property var rasterExts: ["png", "jpg", "jpeg", "webp", "gif", "bmp", "avif", "tif", "tiff", "ico"]
    function mimeIcon(e) {
        if (e.kind === "dir") return Quickshell.iconPath("folder", "inode-directory");
        const x = extOf(e.name);
        const n = (name, gen) => Quickshell.iconPath(name, gen);
        const map = {
            pdf: "application-pdf", zip: "application-zip", gz: "application-gzip", tgz: "application-x-compressed-tar",
            xz: "application-x-xz", zst: "application-zstd", bz2: "application-x-bzip", "7z": "application-x-7z-compressed",
            rar: "application-vnd.rar", tar: "application-x-tar", iso: "application-x-cd-image", img: "application-x-raw-disk-image",
            deb: "application-vnd.debian.binary-package", rpm: "application-x-rpm", appimage: "application-x-executable",
            exe: "application-x-ms-dos-executable", msi: "application-x-msi", dmg: "application-x-apple-diskimage",
            json: "application-json", xml: "application-xml", html: "text-html", htm: "text-html", md: "text-markdown",
            txt: "text-plain", csv: "text-csv", log: "text-x-log", sh: "application-x-shellscript", py: "text-x-python",
            js: "application-javascript", ts: "text-x-typescript", doc: "application-msword", docx: "application-vnd.openxmlformats-officedocument.wordprocessingml.document",
            xls: "application-vnd.ms-excel", xlsx: "application-vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            ppt: "application-vnd.ms-powerpoint", pptx: "application-vnd.openxmlformats-officedocument.presentationml.presentation",
            odt: "application-vnd.oasis.opendocument.text", ods: "application-vnd.oasis.opendocument.spreadsheet",
            epub: "application-epub+zip", torrent: "application-x-bittorrent", ttf: "font-ttf", otf: "font-otf",
            svg: "image-svg+xml", png: "image-png", jpg: "image-jpeg", jpeg: "image-jpeg", webp: "image-webp", gif: "image-gif",
            mp4: "video-mp4", mkv: "video-x-matroska", webm: "video-webm", mov: "video-quicktime",
            mp3: "audio-mpeg", flac: "audio-flac", ogg: "audio-x-vorbis+ogg", wav: "audio-x-wav", m4a: "audio-mp4"
        };
        const gen = /^(png|jpe?g|webp|gif|bmp|avif|tiff?|svg|heic)$/.test(x) ? "image-x-generic"
            : /^(mp4|mkv|webm|mov|avi)$/.test(x) ? "video-x-generic"
            : /^(mp3|flac|ogg|wav|m4a|opus)$/.test(x) ? "audio-x-generic"
            : /^(zip|gz|tgz|xz|zst|bz2|7z|rar|tar)$/.test(x) ? "package-x-generic"
            : /^(txt|md|log|csv|json|xml)$/.test(x) ? "text-x-generic"
            : "application-octet-stream";
        return n(map[x] ?? gen, map[x] ? gen : "application-octet-stream");
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: Panels.close(fan.ctl.popupId)
        Keys.onUpPressed: fan.ctl.sel = Math.min(fan.ctl.apps.length - 1, fan.ctl.sel + 1)
        Keys.onDownPressed: fan.ctl.sel = Math.max(0, fan.ctl.sel - 1)
        Keys.onReturnPressed: if (fan.ctl.sel >= 0) fan.ctl.pick(fan.ctl.apps[fan.ctl.sel])
        Keys.onEnterPressed: if (fan.ctl.sel >= 0) fan.ctl.pick(fan.ctl.apps[fan.ctl.sel])
    }

    Repeater {
        model: fan.ctl.apps
        Item {
            id: row
            required property var modelData
            required property int index
            readonly property string kind: modelData.kind ?? ""          // "" = an app
            readonly property bool isFile: kind === "file" || kind === "dir"
            // this icon's own progress: staggered from the bottom up, eased
            readonly property real k: {
                const ms = fan.t * fan.total - index * 18;
                const p = Math.max(0, Math.min(1, ms / 220));
                return 1 - Math.pow(1 - p, 3);
            }
            readonly property bool hot: mouse.containsMouse || fan.ctl.sel === index
            readonly property bool running: (modelData.toplevels?.length ?? 0) > 0
            // resting place (centre of the icon) in fan coordinates
            readonly property real ix: fan.ctl.cx - fan.x + fan.lean(index)
            readonly property real iy: fan.height - 6 - fan.ctl.iconSize / 2 - index * fan.step
            // start: the tile, just under the fan's bottom edge
            readonly property real sx: fan.ctl.cx - fan.x
            readonly property real sy: fan.height + fan.ctl.iconSize * 0.3
            x: sx + (ix - sx) * k - width + fan.ctl.iconSize / 2
            y: sy + (iy - sy) * k - height / 2
            width: pill.width + 10 + fan.ctl.iconSize
            height: fan.ctl.iconSize
            opacity: Math.min(1, k * 1.6)
            rotation: -fan.tilt(index) * k
            transformOrigin: Item.Right
            scale: 0.5 + 0.5 * k

            // name pill (mock .docktip look)
            Rectangle {
                id: pill
                anchors.verticalCenter: parent.verticalCenter
                x: 0
                width: Math.min(name.implicitWidth, fan.pillMax) + 20
                height: 24
                radius: Theme.square ? 3 : 12
                color: row.hot ? Theme.rgba(Theme.accent, Theme.square ? 0.9 : 0.85)
                    : (Theme.square ? Theme.rgba("#0A0A0A", 0.94) : Theme.rgba("#28282A", 0.86))
                border.width: Theme.rimWidth; border.color: Theme.white(0.14)
                Behavior on color { ColorAnimation { duration: Theme.durHover } }
                GText {
                    id: name
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, fan.pillMax)
                    elide: row.isFile ? Text.ElideMiddle : Text.ElideRight
                    text: row.kind ? row.modelData.name : (row.modelData.entry?.name || row.modelData.appId)
                    color: row.hot ? "white" : Theme.label
                    font.family: Theme.square ? Theme.fontLabel : Theme.fontUi
                    font.pixelSize: Theme.square ? 11 : 12.5
                    font.capitalization: Theme.square ? Font.AllUppercase : Font.MixedCase
                    font.letterSpacing: Theme.square ? 0.66 : 0
                }
            }
            // the icon cell: app icon, file thumbnail / type icon, or the "Open in Files" button
            Item {
                id: cell
                x: parent.width - fan.ctl.iconSize
                width: fan.ctl.iconSize; height: fan.ctl.iconSize
                scale: row.hot ? (row.kind ? 1.12 : 1.08) : 1
                Behavior on scale { NumberAnimation { duration: Theme.durHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }

                IconImage {
                    id: icon
                    visible: row.kind === "" || (row.isFile && !thumb.shows)
                    anchors.fill: parent
                    implicitSize: 96
                    source: row.kind === "" ? Apps.iconFor(row.modelData) : row.isFile ? fan.mimeIcon(row.modelData) : ""
                    mipmap: true
                }

                // thumbnail: freedesktop cache (ctl.thumbs) -> the image itself -> (icon)
                Item {
                    id: thumb
                    readonly property bool shows: img.status === Image.Ready
                    anchors.fill: parent
                    visible: shows
                    property int stage: 0
                    readonly property bool raster: row.kind === "file" && fan.rasterExts.indexOf(fan.extOf(row.modelData.name)) >= 0
                        && row.modelData.size < 60e6
                    // "" while the cache lookup is still out (undefined)
                    readonly property var cached: row.isFile ? fan.ctl.thumbs?.[row.modelData.md5] : ""
                    readonly property var sources: !row.isFile || cached === undefined ? []
                        : (cached ? [cached] : []).concat(raster ? [Apps.fileUrl(row.modelData.path)] : [])
                    RectangularShadow {
                        anchors.fill: frame
                        radius: frame.radius
                        offset.y: 5; blur: 14; spread: -2
                        color: Theme.rgba("#000000", 0.55)
                    }
                    // pictures and videos: a 4:3 crop (mock .df-ic .th); documents: the whole page
                    readonly property bool crop: /^(png|jpe?g|webp|gif|bmp|avif|tiff?|ico|heic|mp4|mkv|webm|mov|avi)$/.test(fan.extOf(row.modelData.name ?? ""))
                    // white mat around the picture
                    Rectangle {
                        id: frame
                        anchors.centerIn: parent
                        width: (thumb.crop ? img.width : img.paintedWidth) + 4; height: (thumb.crop ? img.height : img.paintedHeight) + 4
                        radius: Theme.square ? 2 : 5
                        color: "#F2F2F4"
                        border.width: 0.5; border.color: Theme.rgba("#000000", 0.4)
                    }
                    Image {
                        id: img
                        anchors.centerIn: parent
                        width: parent.width - 4; height: thumb.crop ? Math.round(width * 0.75) : parent.height - 4
                        fillMode: thumb.crop ? Image.PreserveAspectCrop : Image.PreserveAspectFit
                        clip: true
                        asynchronous: true
                        cache: false
                        smooth: true
                        mipmap: true
                        sourceSize.width: 128; sourceSize.height: 128
                        source: thumb.stage < thumb.sources.length ? thumb.sources[thumb.stage] : ""
                        onStatusChanged: if (status === Image.Error) thumb.stage++
                    }
                }

                // "Open in Files" (mock .df-it.top): a glass disc with an up-right arrow
                Rectangle {
                    visible: row.kind === "open"
                    anchors.centerIn: parent
                    width: 38; height: 38
                    radius: Theme.square ? 3 : 19
                    color: Theme.square ? "#060606" : Theme.rgba(Theme.t.color.glass, 0.94)
                    border.width: Theme.rimWidth; border.color: row.hot ? Theme.accent : Theme.rim
                    Glyph { anchors.centerIn: parent; name: "arrowR"; size: 16; rotation: -45; color: Theme.label }
                }
            }
            // running dot, right of the icon (the dock's dot sits under it)
            Rectangle {
                readonly property bool bar: Theme.square
                visible: row.running
                x: parent.width + 4
                anchors.verticalCenter: parent.verticalCenter
                width: bar ? 2 : 4; height: bar ? 8 : 4; radius: bar ? 0 : 2
                color: bar ? Theme.accent : Theme.workspaceCurrent
                opacity: bar ? 1 : 0.8
            }

            // drag a file out: a real Wayland drag carrying its URI (like the shelf)
            Item {
                id: proxy
                width: 1; height: 1
                Drag.dragType: Drag.Automatic
                Drag.supportedActions: Qt.CopyAction
                Drag.proposedAction: Qt.CopyAction
                Drag.active: mouse.drag.active
                Drag.mimeData: row.isFile ? ({ "text/uri-list": row.modelData.url + "\r\n" }) : ({})
                Drag.onDragStarted: fan.ctl.dragBegan()
                Drag.onDragFinished: { proxy.x = 0; proxy.y = 0; fan.ctl.dragEnded(); }
            }
            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                drag.target: row.isFile ? proxy : null
                drag.threshold: 6
                onContainsMouseChanged: if (containsMouse) fan.ctl.sel = -1
                onPressed: ev => {
                    if (!row.isFile) return;
                    const at = mouse.mapToItem(cell, ev.x, ev.y);
                    proxy.Drag.hotSpot.x = Math.max(0, Math.min(cell.width, at.x));
                    proxy.Drag.hotSpot.y = Math.max(0, Math.min(cell.height, at.y));
                    cell.grabToImage(r => { proxy.Drag.imageSource = r.url; });
                }
                onReleased: { proxy.x = 0; proxy.y = 0; }
                onClicked: m => {
                    if (m.button === Qt.MiddleButton) {
                        if (row.kind) return;
                        Panels.close(fan.ctl.popupId); Panels.overviewOpen = false; Apps.launch(row.modelData);
                    } else fan.ctl.pick(row.modelData);
                }
            }
        }
    }
}
