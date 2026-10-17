pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import qs.core
import qs.components
import qs.services

// Spotlight-style launcher (mock #launcher): centred glass panel, keyboard first.
// Results come from pluggable providers (LauncherProviders registry; order/options in shell.json
// launcher.providers + launcher.provider.<id>). Typing a provider's prefix ("=", "@", "/", ">")
// queries only that provider. Keys: Up/Down, Tab/Shift+Tab, Ctrl+N/Ctrl+P, Enter, Esc.
// Layer surface namespace graphite:launcher; it only exists while open.
Scope {
    id: root
    readonly property var opts: Config.opt.launcher ?? ({})
    readonly property bool open: Panels.launcherOpen
    property bool shown: false

    property string text: ""
    property var rows: []          // [{ header }, { item, sel }]  (ListView model)
    property var selectable: []    // [{ item, row }]
    property int sel: 0
    property bool confirming: false
    property var footerHints: []   // [[prefix, provider name]]

    property string initialText: ""   // set by IPC "search"
    onOpenChanged: {
        if (open) {
            hideTimer.stop();
            text = initialText || Panels.launcherQuery;
            initialText = "";
            Panels.launcherQuery = "";
            search();
            shown = true;
        } else {
            confirming = false;
            hideTimer.restart();
        }
    }
    Timer { id: hideTimer; interval: Theme.durFade; onTriggered: root.shown = false }

    // ---- providers (one Loader per configured id; they live as long as the module) ----
    readonly property var providerIds: opts.providers ?? []
    Instantiator {
        id: providers
        model: root.providerIds
        delegate: Loader {
            required property string modelData
            source: LauncherProviders.url(modelData)
            onLoaded: {
                if (item.hasOwnProperty("providerId")) item.providerId = modelData;
                if (item.resultsChanged) item.resultsChanged.connect(() => { if (root.open) root.search(true); });
            }
        }
    }

    function activeProviders() {
        const out = [];
        for (let i = 0; i < providers.count; i++) {
            const p = providers.objectAt(i)?.item;
            if (!p) continue;
            const o = p.options ?? {};
            if (o.enabled === false) continue;
            out.push({
                p,
                prefix: o.prefix ?? p.defaultPrefix ?? "",
                prefixOnly: o.prefixOnly ?? p.defaultPrefixOnly ?? false,
                limit: o.limit ?? 8,
                title: o.title
            });
        }
        return out;
    }

    function search(keepSel) {
        const prevSel = sel;
        const all = activeProviders();
        footerHints = all.filter(x => x.prefix).map(x => [x.prefix, x.title ?? x.p.name]);
        // the longest typed prefix wins and is queried alone
        let excl = null;
        for (const x of all)
            if (x.prefix && text.startsWith(x.prefix) && (!excl || x.prefix.length > excl.prefix.length)) excl = x;
        const runs = excl ? [{ x: excl, q: text.slice(excl.prefix.length).replace(/^\s+/, ""), prefixed: true }]
                          : all.filter(x => !x.prefixOnly).map(x => ({ x, q: text.trim(), prefixed: false }));
        const r = [], s = [];
        for (const run of runs) {
            let res;
            try { res = run.x.p.query(run.q, run.prefixed) ?? []; }
            catch (e) { console.warn("graphite: launcher provider failed:", run.x.p.providerId, e); continue; }
            // by score; ties keep the provider's order
            res = res.map((it, i) => [it, i]).sort((a, b) => ((b[0].score ?? 0) - (a[0].score ?? 0)) || (a[1] - b[1]))
                     .map(x => x[0]).slice(0, run.x.limit);
            if (!res.length) continue;
            r.push({ header: run.x.title ?? run.x.p.name });
            for (const item of res) {
                s.push({ item, row: r.length });
                r.push({ item, sel: s.length - 1 });
            }
        }
        rows = r;
        selectable = s;
        sel = keepSel ? Math.min(prevSel, Math.max(0, s.length - 1)) : 0;
        confirming = false;
    }

    function move(d) {
        if (!selectable.length) return;
        sel = (sel + d + selectable.length) % selectable.length;
        confirming = false;
    }
    function runSelected() {
        const cur = selectable[sel]?.item;
        if (!cur) return;
        if (cur.confirm && !confirming) { confirming = true; return; }
        Panels.launcherOpen = false;
        try { cur.run(); } catch (e) { console.warn("graphite: launcher action failed:", e); }
    }

    // qs -c graphite ipc call launcher toggle | open | close | search "<text>" | results
    IpcHandler {
        target: "launcher"
        function toggle(): void { Panels.launcherOpen = !Panels.launcherOpen; }
        function open(): void { Panels.launcherOpen = true; }
        function close(): void { Panels.launcherOpen = false; }
        // open with a query already typed
        // clipboard history (cliphist) inside the launcher
        function clipboard(): void { if (Panels.launcherOpen) { root.text = ":"; root.search(); } else { root.initialText = ":"; Panels.launcherOpen = true; } }
        function search(query: string): void {
            if (Panels.launcherOpen) { root.text = query; root.search(); }
            else { root.initialText = query; Panels.launcherOpen = true; }
        }
        // current results, one per line: "<group>\t<title>\t<sub>" (scripting/tests)
        function results(): string {
            let group = "";
            return root.rows.map(r => {
                if (r.header !== undefined) { group = r.header; return null; }
                return group + "\t" + (r.item.title ?? "") + "\t" + (r.item.sub ?? "") + (r.sel === root.sel ? "\t<selected>" : "");
            }).filter(x => x !== null).join("\n");
        }
    }

    // screen picked when opening: the focused monitor
    property ShellScreen targetScreen: null
    onShownChanged: if (shown) targetScreen = Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0] ?? null

    component Kbd: Rectangle {
        property alias text: kt.text
        implicitWidth: Math.max(18, kt.implicitWidth + 8)
        implicitHeight: 18
        radius: 4
        color: Theme.fill2
        border.width: Theme.rimWidth
        border.color: Theme.sep
        GText { id: kt; anchors.centerIn: parent; small: true; secondary: true; font.family: Theme.fontUi }
    }

    LazyLoader {
        active: root.shown

        PanelWindow {
            id: win
            screen: root.targetScreen
            color: "transparent"
            WlrLayershell.namespace: "graphite:launcher"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            readonly property real shadowPad: 48
            anchors.top: true
            margins.top: Math.max(0, Math.round((screen?.height ?? 900) * (root.opts.top ?? 0.18)) - shadowPad)
            implicitWidth: (root.opts.width ?? 680) + shadowPad * 2
            implicitHeight: body.height + shadowPad * 2
            mask: Region { item: body }

            HyprlandFocusGrab {
                active: root.open
                windows: [win]
                onCleared: Panels.launcherOpen = false
            }

            RectangularShadow {
                anchors.fill: body
                radius: body.radius
                offset.y: 24; blur: 60; spread: -6
                color: Theme.rgba("#000000", 0.5)
                opacity: body.opacity
                scale: body.scale
            }

            Glass {
                id: body
                strong: true
                brackets: Theme.cardBrackets
                x: win.shadowPad; y: win.shadowPad
                width: root.opts.width ?? 680
                height: col.implicitHeight
                radius: Math.min(Theme.radiusLauncher, Theme.radiusPanel)
                opacity: root.open ? 1 : 0
                scale: root.open ? 1 : 0.97
                Behavior on opacity { NumberAnimation { duration: Theme.durPop; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
                Behavior on scale { NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }

                Column {
                    id: col
                    width: parent.width

                    // ---- input (mock .ln-in) ----
                    Item {
                        width: parent.width; height: 56
                        Glyph { id: glass; x: 18; anchors.verticalCenter: parent.verticalCenter; name: "search"; size: 22; color: Theme.label2 }
                        TextInput {
                            id: input
                            anchors.left: glass.right; anchors.leftMargin: 12
                            anchors.right: parent.right; anchors.rightMargin: 18
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.label
                            selectionColor: Theme.accent
                            selectedTextColor: Theme.onAccent
                            // Telemetry: mono 18px input (mock .ln-in input)
                            readonly property bool mono: Theme.square && Theme.labelsMono
                            font.family: mono ? Theme.fontLabel : Theme.fontDisplay
                            font.pixelSize: mono ? 18 : Theme.fontSizeLarge
                            clip: true
                            focus: true
                            onTextEdited: { root.text = text; root.search(); }
                            Connections {
                                target: root
                                function onTextChanged() { if (input.text !== root.text) input.text = root.text; }
                                function onOpenChanged() { if (root.open) input.forceActiveFocus(); }
                            }
                            Component.onCompleted: { text = root.text; forceActiveFocus(); }

                            GText {
                                visible: input.text === ""
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.opts.placeholder ?? "Search"
                                color: Theme.label3
                                font.family: input.font.family
                                font.pixelSize: input.font.pixelSize
                            }

                            Keys.onPressed: e => {
                                const ctrl = e.modifiers & Qt.ControlModifier;
                                if (e.key === Qt.Key_Down || e.key === Qt.Key_Tab || (ctrl && e.key === Qt.Key_N)) { root.move(1); e.accepted = true; }
                                else if (e.key === Qt.Key_Up || e.key === Qt.Key_Backtab || (ctrl && e.key === Qt.Key_P)) { root.move(-1); e.accepted = true; }
                                else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { root.runSelected(); e.accepted = true; }
                                else if (e.key === Qt.Key_Delete && (e.modifiers & Qt.ShiftModifier)) {
                                    const it = root.selectable[root.sel]?.item;
                                    if (it?.remove) { it.remove(); e.accepted = true; }
                                }
                                else if (e.key === Qt.Key_Escape) {
                                    if (root.confirming) root.confirming = false;
                                    else Panels.launcherOpen = false;
                                    e.accepted = true;
                                }
                            }
                        }
                    }

                    // ---- results (mock .ln-res) ----
                    Rectangle { visible: root.rows.length > 0; width: parent.width; height: Theme.rimWidth; color: Theme.sep }
                    ListView {
                        id: list
                        visible: root.rows.length > 0
                        x: 8
                        width: parent.width - 16
                        height: Math.min(contentHeight, root.opts.maxHeight ?? 404) + (visible ? 8 : 0)
                        bottomMargin: 8
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: root.rows
                        // keep the selection in view
                        Connections {
                            target: root
                            function onSelChanged() {
                                const r = root.selectable[root.sel]?.row;
                                if (r !== undefined) list.positionViewAtIndex(r, ListView.Contain);
                                if (root.sel === 0) list.positionViewAtBeginning();
                            }
                        }
                        delegate: Loader {
                            id: rowLoader
                            required property var modelData
                            required property int index
                            width: list.width
                            sourceComponent: modelData.header !== undefined ? headerRow : modelData.item.big ? bigRow : itemRow
                            onLoaded: item.modelData = modelData
                            onModelDataChanged: if (item) item.modelData = modelData
                        }
                    }

                    // ---- footer (mock .ln-foot) ----
                    Rectangle { width: parent.width; height: Theme.rimWidth; color: Theme.sep }
                    Item {
                        width: parent.width; height: 38
                        Row {
                            x: 14; anchors.verticalCenter: parent.verticalCenter
                            spacing: 7
                            LogoGlyph { anchors.verticalCenter: parent.verticalCenter; width: 14; height: 14 }
                            GText { text: "Graphite Launcher"; small: true; secondary: true; anchors.verticalCenter: parent.verticalCenter }
                            Repeater {
                                model: root.text === "" ? root.footerHints : []
                                Row {
                                    required property var modelData
                                    spacing: 4
                                    anchors.verticalCenter: parent?.verticalCenter
                                    Item { width: 6; height: 1 }
                                    Kbd { text: modelData[0] }
                                    GText { text: modelData[1]; small: true; secondary: true; anchors.verticalCenter: parent.verticalCenter }
                                }
                            }
                        }
                        Row {
                            anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                            spacing: 16
                            Row {
                                visible: root.selectable.length > 0
                                spacing: 6
                                GText { text: root.confirming ? "Confirm" : (root.selectable[root.sel]?.item.actLabel ?? "Open"); small: true; secondary: true; anchors.verticalCenter: parent.verticalCenter }
                                Kbd { text: "↵" }
                            }
                            Row {
                                spacing: 6
                                GText { text: "Navigate"; small: true; secondary: true; anchors.verticalCenter: parent.verticalCenter }
                                Kbd { text: "↑" }
                                Kbd { text: "↓" }
                            }
                            Row {
                                spacing: 6
                                GText { text: "Close"; small: true; secondary: true; anchors.verticalCenter: parent.verticalCenter }
                                Kbd { text: "esc" }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- row types ----
    Component {
        id: headerRow
        SectionLabel {
            property var modelData: null
            leftPadding: 10; topPadding: 11; bottomPadding: 5
            text: modelData?.header ?? ""
        }
    }

    Component {
        id: itemRow
        Rectangle {
            id: r
            property var modelData: null
            readonly property var it: modelData?.item ?? ({})
            readonly property bool selected: (modelData?.sel ?? -1) === root.sel
            readonly property bool asking: selected && root.confirming
            // tokens ui.selection: accent fill, or "neutral" = fill2 + 2px accent bar on the left
            readonly property bool accentSel: selected && (asking || !Theme.selectionNeutral)
            height: (r.it.thumb ?? "") !== "" ? 52 : 40
            radius: Theme.square ? 3 : Math.min(8, Theme.radiusMenu)
            color: asking ? Theme.red : !selected ? "transparent" : Theme.selectionNeutral ? Theme.fill2 : Theme.accent
            readonly property color fg: accentSel ? Theme.onAccent : Theme.label
            readonly property color fg2: accentSel ? Theme.rgba(Theme.t.color.onAccent, 0.75) : Theme.label2
            Rectangle { visible: r.selected && !r.accentSel; width: 2; height: parent.height; color: Theme.accent }

            Item {
                id: ico
                readonly property bool hasThumb: (r.it.thumb ?? "") !== ""
                x: 10; width: hasThumb ? 64 : 24; height: hasThumb ? 40 : 24
                anchors.verticalCenter: parent.verticalCenter
                IconImage {
                    anchors.fill: parent
                    visible: !!r.it.image && !ico.hasThumb
                    source: r.it.image ?? ""
                    asynchronous: true
                }
                Rectangle {
                    anchors.fill: parent
                    visible: ico.hasThumb
                    radius: 5
                    color: Theme.fill2
                    clip: true
                    Image {
                        anchors.fill: parent
                        source: r.it.thumb ?? ""
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: 128; sourceSize.height: 80
                        asynchronous: true
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    visible: !r.it.image && !ico.hasThumb
                    radius: Theme.square ? 3 : 6
                    color: r.accentSel ? Theme.rgba(Theme.t.color.onAccent, 0.22) : Theme.fill2
                    Glyph { anchors.centerIn: parent; name: r.it.icon ?? "dots"; size: 15; color: r.fg }
                }
            }
            Row {
                anchors.left: ico.right; anchors.leftMargin: 11
                anchors.right: ty.left; anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 11
                GText {
                    id: title
                    width: Math.min(implicitWidth, parent.width)
                    text: r.asking ? (r.it.confirm + "  Press ↵ again") : Fuzzy.highlight(r.it.title ?? "", r.it.highlight)
                    textFormat: r.asking ? Text.PlainText : Text.StyledText
                    color: r.fg
                }
                GText {
                    width: Math.max(0, parent.width - title.width - 11)
                    visible: !r.asking && (r.it.sub ?? "") !== ""
                    text: r.it.sub ?? ""
                    color: r.fg2
                    font.pixelSize: Theme.fontSize - 1
                    anchors.baseline: title.baseline
                }
            }
            GText {
                id: ty
                anchors.right: parent.right; anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: r.it.type ?? ""
                color: r.accentSel ? r.fg2 : Theme.label3
                font.pixelSize: Theme.fontSize - 1
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onPositionChanged: if (root.sel !== r.modelData.sel) { root.sel = r.modelData.sel; root.confirming = false; }
                onClicked: { root.sel = r.modelData.sel; root.runSelected(); }
            }
        }
    }

    Component {
        id: bigRow
        Rectangle {
            id: b
            property var modelData: null
            readonly property var big: modelData?.item.big ?? ["", "", "", ""]
            readonly property bool selected: (modelData?.sel ?? -1) === root.sel
            height: 86
            radius: Math.min(10, Theme.radiusPanel)
            color: selected ? Theme.rgba(Theme.t.color.accent, 0.18) : "transparent"
            border.width: selected ? 1 : 0
            border.color: Theme.rgba(Theme.t.color.accent, 0.6)
            Row {
                anchors.centerIn: parent
                width: parent.width - 20
                Repeater {
                    model: [[b.big[0], b.big[1]], null, [b.big[2], b.big[3]]]
                    Item {
                        id: cell
                        required property var modelData
                        width: modelData ? (b.width - 20 - 40) / 2 : 40
                        height: 60
                        GIcon { visible: !cell.modelData; anchors.centerIn: parent; name: "arrow_forward"; size: 18; color: Theme.label3 }
                        Column {
                            visible: !!cell.modelData
                            anchors.centerIn: parent
                            width: parent.width
                            spacing: 6
                            GText {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: cell.modelData?.[0] ?? ""
                                font.family: Theme.fontNumeric
                                font.pixelSize: Theme.fontSizeHero
                                font.weight: Theme.numericWeight
                                font.variableAxes: Theme.numericAxes
                            }
                            GText {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: cell.modelData?.[1] ?? ""
                                small: true; secondary: true
                            }
                        }
                    }
                }
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onPositionChanged: if (root.sel !== b.modelData.sel) root.sel = b.modelData.sel
                onClicked: { root.sel = b.modelData.sel; root.runSelected(); }
            }
        }
    }
}
