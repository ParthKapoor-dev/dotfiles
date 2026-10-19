pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core
import qs.components
import qs.services

// Post-screenshot card (namespace nox:shot): thumbnail + one row of actions at a corner of the
// focused monitor. Every `nox shot` capture (and the screenshot action) calls
// `qs -c nox ipc call shot open <file>` and falls back to a plain notification when it says false
// (card disabled) or the shell is down. The image is on the clipboard by then, but the file is a
// capture in $XDG_RUNTIME_DIR/nox-shot: nothing lands in ~/Pictures until Save.
// Actions (screenshot.card.actions, in order):
//   save      copy into ~/Pictures/Screenshots (nox shot save); the card then shows that file
//   folder    once saved: show the file in the file manager (FileManager1.ShowItems, else xdg-open)
//   annotate  screenshot.annotate argv ({file}), default `nox shot annotate` (satty, writes back
//             to the file and reopens this card with the result)
//   copy      image -> clipboard again
//   pin       floating always-on-top copy (ShotPin.qml); any number at once
//   phone     nox phone send <file>; only while the phone link is up and the phone reachable
//   upload    screenshot.upload (below); asks first, then copies the link. service "none" hides it
//   delete    unsaved: discard the capture; saved: move the file to the Trash (gio trash)
// Upload: service "0x0" (default; public, but with a secret URL that expires after `expires`
// hours) | "none" | anything else with `command` = argv where {file} and {expires} are replaced;
// the first http(s) URL on stdout is the link. `confirm: false` skips the "Upload publicly?" step.
// The card auto-dismisses after screenshot.card.timeout ms; hover or a pending upload holds it.
// shell.json screenshot.{card: {enabled, timeout, position, width, actions}, annotate, upload: {service, command, label, expires, confirm}}
Scope {
    id: root
    readonly property var opts: Config.opt.screenshot ?? ({})
    readonly property var cardOpts: opts.card ?? ({})
    readonly property string position: cardOpts.position ?? "bottom-right"   // bottom-right | bottom-left | top-right | top-left
    readonly property real cardWidth: cardOpts.width ?? 300
    readonly property real pad: 28        // shadow room around the card (outside the input mask)

    property string file: ""              // screenshot on the card
    property string screenName: ""
    property bool alive: false            // window exists (outlives `shown` for the slide-out)
    property bool shown: false
    property bool hovered: false
    property string phase: ""             // upload row: "" | confirm | uploading | done | error
    property string flash: ""             // status line ("Copied", "Link copied", errors)
    property string hint: ""              // hovered action's label
    property var pins: []                 // [{ id, path, screen, slot }]
    readonly property string saveDir: (Quickshell.env("XDG_PICTURES_DIR") || Quickshell.env("HOME") + "/Pictures") + "/Screenshots"
    // saved = the card's file lives outside the runtime capture dir
    readonly property bool saved: file !== "" && file.indexOf("/nox-shot/") === -1
    property int pinSeq: 0

    // ---- upload ----
    readonly property var up: opts.upload ?? ({})
    readonly property string upService: up.service ?? "0x0"
    readonly property var services: ({
        "0x0": { label: "0x0.st", command: ["curl", "-fsS", "-A", "nox-shot", "-F", "file=@{file}", "-F", "secret=", "-F", "expires={expires}", "https://0x0.st"] }
    })
    readonly property var upCommand: up.command ?? services[upService]?.command ?? null
    readonly property string upLabel: up.label ?? (up.command ? "your upload host" : services[upService]?.label ?? upService)
    readonly property bool canUpload: upService !== "none" && upCommand !== null

    readonly property var actionIds: cardOpts.actions ?? ["save", "folder", "annotate", "copy", "pin", "phone", "upload", "delete"]
    readonly property var actionDefs: ({
        save: { icon: "download", label: "Save to Screenshots", show: () => !root.saved },
        folder: { icon: "folder", label: "Show in folder", show: () => root.saved },
        annotate: { icon: "edit", label: "Annotate", show: () => true },
        copy: { icon: "clip", label: "Copy", show: () => true },
        pin: { icon: "push_pin", label: "Pin on screen", show: () => true },
        phone: { icon: "phone", label: "Send to " + (Phone.device?.name ?? "phone"), show: () => Phone.available && Phone.connected },
        upload: { icon: "cloud_upload", label: "Upload to " + root.upLabel, show: () => root.canUpload },
        delete: { icon: "trash", label: root.saved ? "Move to Trash" : "Discard", show: () => true }
    })
    readonly property var actions: actionIds.filter(id => actionDefs[id] && actionDefs[id].show())

    function show(path) {
        if (cardOpts.enabled === false || !path) return false;
        file = path;
        screenName = Hyprland.focusedMonitor?.name ?? "";
        phase = ""; flash = ""; hint = "";
        alive = true;
        shown = true;
        life.restart();
        return true;
    }
    function dismiss() {
        shown = false;
        killTimer.restart();
    }
    function pin(path) {
        if (!path) return false;
        pinSeq++;
        pins = pins.concat([{ id: pinSeq, path: path, screen: Hyprland.focusedMonitor?.name ?? "", slot: pins.length }]);
        return true;
    }
    function unpin(id) { pins = pins.filter(p => p.id !== id); }

    function sh(script, ...args) { Quickshell.execDetached(["sh", "-c", script, "sh"].concat(args)); }
    function fill(argv, path) { return argv.map(a => String(a).replace(/\{file\}/g, path).replace(/\{expires\}/g, String(up.expires ?? 24))); }

    function act(id) {
        const f = file;
        switch (id) {
        case "save":
            if (saver.running) return;
            saver.command = ["nox", "shot", "save", f];
            saver.running = true;
            break;
        case "copy":
            sh("wl-copy --type image/png < \"$1\"", f);
            flash = "Copied";
            break;
        case "annotate":
            if (opts.annotate) Quickshell.execDetached(fill(opts.annotate, f));
            else Quickshell.execDetached(["nox", "shot", "annotate", f]);
            dismiss();
            break;
        case "phone":
            Quickshell.execDetached(["nox", "phone", "--notify", "send", f]);
            dismiss();
            break;
        case "pin":
            pin(f);
            dismiss();
            break;
        case "upload":
            if (up.confirm === false) startUpload();
            else phase = "confirm";
            break;
        case "folder":
            sh("dbus-send --session --print-reply --dest=org.freedesktop.FileManager1 /org/freedesktop/FileManager1 " +
               "org.freedesktop.FileManager1.ShowItems array:string:\"$2\" string:'' >/dev/null 2>&1 || exec xdg-open \"${1%/*}\"",
               f, "file://" + encodeURI(f));
            dismiss();
            break;
        case "delete":
            if (saved) {
                sh("gio trash -- \"$1\" 2>/dev/null || rm -f -- \"$1\"", f);
                Panels.hud("Screenshot moved to Trash", "trash");
            } else if (!pins.some(p => p.path === f)) {
                sh("rm -f -- \"$1\"", f);   // a pinned capture keeps its file until the next login
            }
            dismiss();
            break;
        }
    }

    function startUpload() {
        if (uploader.running) return;
        phase = "uploading"; flash = "Uploading…";
        uploader.got = false;
        uploader.command = fill(upCommand, file);
        uploader.running = true;
    }
    function uploaded(text) {
        if (uploader.got) return;
        uploader.got = true;
        const m = (text ?? "").match(/https?:\/\/[^\s"'<>]+/);
        if (m) {
            Quickshell.execDetached(["wl-copy", "--", m[0]]);
            phase = "done"; flash = "Link copied · " + m[0].replace(/^https?:\/\//, "");
            if (!shown) Panels.hud("Upload link copied", "check");
        } else {
            phase = "error"; flash = "Upload failed";
            if (!shown) Panels.hud("Screenshot upload failed", "x");
        }
        life.restart();
    }
    Process {
        id: saver
        stdout: StdioCollector {
            onStreamFinished: {
                const out = text.trim();
                if (out) { root.file = out; root.flash = "Saved to Screenshots"; }
                else root.flash = "Save failed";
                life.restart();
            }
        }
    }
    Process {
        id: uploader
        property bool got: false
        stdout: StdioCollector { onStreamFinished: root.uploaded(text) }
        // no stdout at all (command missing / killed): give up after the exit
        onExited: Qt.callLater(() => root.uploaded(""))
    }

    Timer {
        id: life
        interval: root.cardOpts.timeout ?? 6000
        running: root.shown && !root.hovered && root.phase !== "confirm" && root.phase !== "uploading"
        onTriggered: root.dismiss()
    }
    Timer { id: killTimer; interval: Theme.durSheet + 60; onTriggered: if (!root.shown) { root.alive = false; root.file = ""; } }

    // qs -c nox ipc call shot open <file> | pin <file> | unpinAll | dismiss | act <action> | confirmUpload | status
    IpcHandler {
        target: "shot"
        function open(path: string): bool { return root.show(path); }   // ("show" is reserved by the qs ipc CLI)
        function pin(path: string): bool { return root.pin(path); }
        function unpinAll(): void { root.pins = []; }
        function dismiss(): void { root.dismiss(); }
        // run a card action on the shown screenshot (upload: asks first unless upload.confirm is false)
        function act(id: string): bool { if (!root.shown || root.actions.indexOf(id) === -1) return false; root.act(id); return true; }
        function confirmUpload(): bool { if (root.phase !== "confirm") return false; root.startUpload(); return true; }
        function status(): string { return "card=" + (root.shown ? root.file : "none") + " pins=" + root.pins.length; }
    }

    Variants {
        model: root.pins
        ShotPin { onCloseRequested: root.unpin(modelData.id) }
    }

    // icon button in the action row (glyph from the mock set, else a Material Symbols name)
    component ActBtn: Rectangle {
        id: btn
        required property string actId
        readonly property var def: root.actionDefs[actId]
        width: 30; height: 30
        radius: Theme.square ? 4 : 9
        color: mouse.containsMouse ? Theme.fill3 : Theme.fill2
        Behavior on color { ColorAnimation { duration: Theme.durHover } }
        scale: mouse.pressed ? 0.94 : 1
        Behavior on scale { NumberAnimation { duration: Theme.durHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
        Glyph {
            anchors.centerIn: parent
            name: btn.def.icon
            size: 16
            color: btn.actId === "delete" && mouse.containsMouse ? Theme.accent : Theme.label
        }
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            onContainsMouseChanged: root.hint = containsMouse ? btn.def.label : (root.hint === btn.def.label ? "" : root.hint)
            onClicked: root.act(btn.actId)
        }
    }

    LazyLoader {
        active: root.alive

        PanelWindow {
            id: win
            screen: Quickshell.screens.find(s => s.name === root.screenName) ?? Quickshell.screens[0] ?? null
            color: "transparent"
            WlrLayershell.namespace: "nox:shot"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            readonly property bool atTop: root.position.startsWith("top")
            readonly property bool atLeft: root.position.endsWith("left")
            // clear of the bar at the top; at the bottom the dock is centred, the corners are free
            readonly property real edge: 14
            anchors.top: atTop
            anchors.bottom: !atTop
            anchors.left: atLeft
            anchors.right: !atLeft
            margins.top: atTop ? Math.max(0, (Config.moduleEnabled("bar") ? Theme.barHeight : 0) + 8 - root.pad) : 0
            margins.bottom: 0
            implicitWidth: root.cardWidth + root.pad + edge
            implicitHeight: card.height + root.pad * 2
            mask: Region { item: maskArea }
            // input area = the card plus the close button that overhangs its corner
            Item { id: maskArea; x: card.x - 8; y: card.y - 8; width: card.width + 16; height: card.height + 16 }

            HoverHandler { onHoveredChanged: root.hovered = hovered }

            RectangularShadow {
                anchors.fill: card
                radius: card.radius
                offset.y: 10; blur: 30; spread: -4
                color: Theme.rgba("#000000", 0.32)
                opacity: card.opacity
            }
            Glass {
                id: card
                menu: true
                color: Theme.cardGlass
                radius: Theme.square ? 6 : 16
                width: root.cardWidth
                height: col.implicitHeight + 24
                y: root.pad
                // slide in from the screen edge (like the notification banners)
                readonly property real restX: win.atLeft ? win.edge : root.pad
                x: root.shown && slid ? restX : (win.atLeft ? -width - 24 : win.width + 24)
                property bool slid: false
                Component.onCompleted: slid = true
                opacity: root.shown ? 1 : 0
                Behavior on x { NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
                Behavior on opacity { NumberAnimation { duration: Theme.durSheet } }

                Column {
                    id: col
                    x: 12; y: 12
                    width: card.width - 24
                    spacing: 10

                    // thumbnail; click opens the image in the default viewer
                    Rectangle {
                        width: parent.width
                        height: Math.min(170, Math.max(60, width * (thumb.implicitWidth > 0 ? thumb.implicitHeight / thumb.implicitWidth : 0.5625)))
                        radius: Theme.square ? 3 : 9
                        color: Theme.rgba("#000000", 0.35)
                        border.width: 1
                        border.color: Theme.hair
                        Image {
                            id: thumb
                            anchors.fill: parent
                            anchors.margins: 1
                            source: root.file ? "file://" + root.file : ""
                            fillMode: Image.PreserveAspectFit
                            sourceSize.width: 600
                            asynchronous: true
                            cache: false
                            smooth: true
                            mipmap: true
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { Quickshell.execDetached(["xdg-open", root.file]); root.dismiss(); }
                        }
                    }

                    // file name (or the hovered action / status)
                    Item {
                        width: parent.width
                        height: name.implicitHeight
                        GText {
                            id: name
                            width: parent.width
                            small: true
                            color: root.hint !== "" ? Theme.label : root.flash === "" ? Theme.label2 : root.phase === "error" ? Theme.accent : Theme.label
                            text: root.hint || root.flash || root.file.replace(/^.*\//, "")
                            elide: Text.ElideMiddle
                        }
                    }

                    // actions
                    Row {
                        visible: root.phase !== "confirm"
                        spacing: Math.max(4, Math.floor((col.width - root.actions.length * 30) / Math.max(1, root.actions.length - 1)))
                        Repeater {
                            model: root.actions
                            ActBtn { required property string modelData; actId: modelData }
                        }
                    }

                    // upload confirmation
                    Column {
                        visible: root.phase === "confirm"
                        width: parent.width
                        spacing: 8
                        GText {
                            width: parent.width
                            wrapMode: Text.Wrap
                            elide: Text.ElideNone
                            text: "Upload publicly to " + root.upLabel + "? Anyone with the link can open it."
                                + (root.upService === "0x0" && !root.up.command ? " Expires in " + (root.up.expires ?? 24) + " h." : "")
                        }
                        Row {
                            anchors.right: parent.right
                            spacing: 6
                            PillButton { text: "Cancel"; onClicked: { root.phase = ""; root.flash = ""; } }
                            PillButton { text: "Upload"; icon: "cloud_upload"; on: true; onClicked: root.startUpload() }
                        }
                    }
                }
            }

            // close button (mock .nt .x), on hover
            Rectangle {
                x: card.x - 6; y: card.y - 6
                width: 20; height: 20
                color: Theme.rgba(Theme.t.color.glass, 0.95)
                radius: Theme.square ? 4 : 10
                border.width: Theme.rimWidth
                border.color: Theme.rim
                opacity: root.hovered && root.shown ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.durHover } }
                Glyph { anchors.centerIn: parent; name: "x"; size: 10; color: Theme.label }
                MouseArea { anchors.fill: parent; hoverEnabled: true; onClicked: root.dismiss() }
            }
        }
    }
}
