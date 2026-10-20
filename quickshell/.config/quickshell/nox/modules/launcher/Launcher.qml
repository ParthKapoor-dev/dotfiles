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
// queries only that provider. Keys: Up/Down, Tab/Shift+Tab, Ctrl+N/Ctrl+P, Enter, Esc; for results
// that support them, Shift+Delete (remove), Ctrl+Enter (mark), Shift+Enter (alt action) and
// Alt+Up/Alt+Down (reorder).
// A prefixed provider showing a sub-level (nested) takes Esc / Backspace-on-empty as "back".
// A prefixed grid provider (emoji) shows square tiles in sections instead of rows: arrows move in
// 2D, PageUp/PageDown by a screen of rows, Home/End to the first/last tile; the footer names the
// selected tile.
// Layer surface namespace nox:launcher; it only exists while open.
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
    property var prefixed: null    // { p, prefix, q }: the provider whose prefix is typed, if any
    readonly property bool nested: !!prefixed?.p.nested

    // ---- grid mode (prefixed provider with `grid`): tiles of result.glyph, sectioned by result.section ----
    readonly property bool gridMode: !!prefixed?.p.grid
    readonly property int gridGap: 8
    readonly property int gridWidth: (opts.width ?? 680) - 16
    // as many columns as fit tiles of at least gridTileMin (8 at the default 680 width)
    readonly property int gridCols: Math.max(1, Math.floor((gridWidth + gridGap) / ((opts.gridTileMin ?? 72) + gridGap)))
    readonly property real gridTile: Math.floor((gridWidth - (gridCols - 1) * gridGap) / gridCols)
    readonly property int gridHeight: opts.gridHeight ?? 432
    property var gridRows: []      // [{ header, count }, { start, count, tr }]  (grid ListView model)
    property var tileRows: []      // [{ start, count, row }]: the tile rows only, for Up/Down
    property var tileRowOf: []     // selectable index -> tileRows index
    property int gridCol: -1       // sticky column while Up/Down passes shorter rows (-1 = from sel)

    // large preview beside the list for results that carry one: an image (result.preview:
    // wallpapers, image files, clipboard images) or text (result.previewText: clipboard text). Text
    // that is just a colour ("#e5484d", "rgb(…)", "hsl(…)") shows a swatch, just a URL its domain.
    readonly property var previewItem: open ? (selectable[sel]?.item ?? null) : null
    readonly property string previewUrl: previewItem?.preview ?? ""
    readonly property string previewText: previewUrl ? "" : (previewItem?.previewText ?? "")
    readonly property bool previewOn: previewUrl !== "" || previewText !== ""
    readonly property var previewColor: colorOf(previewText)
    readonly property string previewHost: previewColor === null ? hostOf(previewText) : ""
    readonly property bool previewMono: previewItem?.previewMono ?? codeish(previewText)

    // "#rgb[a]" / "#rrggbb[aa]" (CSS order) / rgb[a](…) / hsl[a](…) -> color, else null
    function colorOf(t) {
        t = (t ?? "").trim();
        if (t.length > 64) return null;
        let m = t.match(/^#([0-9a-f]{3,4}|[0-9a-f]{6}|[0-9a-f]{8})$/i);
        if (m) {
            let h = m[1];
            if (h.length <= 4) h = h.split("").map(c => c + c).join("");
            const n = i => parseInt(h.slice(i, i + 2), 16) / 255;
            return Qt.rgba(n(0), n(2), n(4), h.length === 8 ? n(6) : 1);
        }
        m = t.match(/^(rgba?|hsla?)\(\s*([\d.]+)(%?)[\s,]+([\d.]+)%?[\s,]+([\d.]+)%?(?:\s*[,\/]\s*([\d.]+)(%?))?\s*\)$/i);
        if (!m) return null;
        const a = m[6] === undefined ? 1 : Math.min(1, parseFloat(m[6]) / (m[7] ? 100 : 1));
        const v = [parseFloat(m[2]), parseFloat(m[4]), parseFloat(m[5])];
        if (m[1].toLowerCase().startsWith("rgb")) {
            const k = m[3] ? 100 : 255;
            return Qt.rgba(Math.min(1, v[0] / k), Math.min(1, v[1] / k), Math.min(1, v[2] / k), a);
        }
        return Qt.hsla((v[0] % 360) / 360, Math.min(1, v[1] / 100), Math.min(1, v[2] / 100), a);
    }
    // a lone http(s) URL -> its host, else ""
    function hostOf(t) {
        const m = (t ?? "").trim().match(/^https?:\/\/(?:[^@\/\s]*@)?([^\/\s:?#]+)[^\s]*$/i);
        return m ? m[1].replace(/^www\./i, "") : "";
    }
    // looks like code / a shell line / structured data -> monospace preview
    function codeish(t) {
        if (!t) return false;
        const lines = t.split("\n");
        if (lines.filter(l => /^(\t| {2,})\S/.test(l)).length >= 2) return true;
        if (/[{};]\s*$|=>|::|^\s*[$#>] \S|^\s*(import|from|def|class|fn|pub|const|let|var|function|return|if|for|#include|SELECT|sudo|git|cd|npm|pnpm|cargo|yay|pacman)\b/m.test(t)) return true;
        const sym = (t.match(/[{}()\[\];=<>|&$\/\\_*`]/g) ?? []).length;
        return sym / t.length > 0.12;
    }
    readonly property int previewGap: 12

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
    ListModel { id: rowModel }
    ListModel { id: gridModel }

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
                          : all.filter(x => !x.prefixOnly && !x.p.fallback).map(x => ({ x, q: text.trim(), prefixed: false }));
        prefixed = excl ? { p: excl.p, prefix: excl.prefix, q: runs[0].q } : null;
        // fallback providers (web search): unprefixed, they run after all the others and only
        // when those found fewer than options.fallbackBelow rows (default 3), so they stay last
        if (!excl && text.trim())
            for (const x of all.filter(x => !x.prefixOnly && x.p.fallback))
                runs.push({ x, q: text.trim(), prefixed: false, fallback: x.p.options?.fallbackBelow ?? 3 });
        const r = [], s = [];
        for (const run of runs) {
            if (run.fallback !== undefined && s.length >= run.fallback) continue;
            let res;
            try { res = run.x.p.query(run.q, run.prefixed) ?? []; }
            catch (e) { console.warn("nox: launcher provider failed:", run.x.p.providerId, e); continue; }
            // by score; ties keep the provider's order
            res = res.map((it, i) => [it, i]).sort((a, b) => ((b[0].score ?? 0) - (a[0].score ?? 0)) || (a[1] - b[1]))
                     .map(x => x[0]).slice(0, run.x.limit > 0 && !run.x.p.grid ? run.x.limit : undefined);   // limit 0 = all
            if (!res.length) continue;
            r.push({ header: run.x.title ?? run.x.p.name });
            for (const item of res) {
                s.push({ item, row: r.length });
                r.push({ item, sel: s.length - 1 });
            }
        }
        rows = r;
        // the ListView model only follows the row count: rows read root.rows[index] and update in
        // place. Assigning a new array as the model reset the view on every keystroke (and on every
        // thumbnail a provider finished), which flashed the selection onto row 0 (the header).
        const n = gridMode ? 0 : r.length;   // grid mode: the row list stays empty
        while (rowModel.count > n) rowModel.remove(rowModel.count - 1);
        while (rowModel.count < n) rowModel.append({});
        selectable = s;
        layoutGrid();
        sel = keepSel ? Math.min(prevSel, Math.max(0, s.length - 1)) : 0;
        confirming = false;
    }

    function move(d) {
        if (!selectable.length) return;
        sel = (sel + d + selectable.length) % selectable.length;
        confirming = false;
        gridCol = -1;
    }

    // grid mode: consecutive results with the same section become a header + rows of gridCols tiles
    function layoutGrid() {
        const g = [], t = [], of = [];
        if (gridMode) {
            const s = selectable;
            for (let i = 0; i < s.length;) {
                const sec = s[i].item.section ?? "";
                let j = i;
                while (j < s.length && (s[j].item.section ?? "") === sec) j++;
                if (sec !== "") g.push({ header: sec, count: j - i });
                for (let k = i; k < j; k += gridCols) {
                    const count = Math.min(gridCols, j - k);
                    t.push({ start: k, count, row: g.length });
                    g.push({ start: k, count, tr: t.length - 1 });
                    for (let c = 0; c < count; c++) of.push(t.length - 1);
                }
                i = j;
            }
        }
        tileRows = t;
        tileRowOf = of;
        while (gridModel.count > g.length) gridModel.remove(gridModel.count - 1);
        while (gridModel.count < g.length) gridModel.append({});
        gridRows = g;
        gridCol = -1;
    }
    // grid mode keys: Left/Right one tile (across sections), Up/Down a row (keeping the column, a
    // short row clamps it), PageUp/PageDown a screen of rows, Home/End the first/last tile
    function gridMove(key) {
        const n = selectable.length;
        if (!n) return;
        const tr = tileRowOf[sel] ?? 0;
        const col = gridCol >= 0 ? gridCol : sel - tileRows[tr].start;
        const page = Math.max(1, Math.floor(gridHeight / (gridTile + gridGap)) - 1);
        const toRow = r => {
            r = Math.max(0, Math.min(tileRows.length - 1, r));
            if (r === tr) return sel;
            gridCol = col;
            return tileRows[r].start + Math.min(col, tileRows[r].count - 1);
        };
        let next = sel;
        if (key === Qt.Key_Left) { next = Math.max(0, sel - 1); gridCol = -1; }
        else if (key === Qt.Key_Right) { next = Math.min(n - 1, sel + 1); gridCol = -1; }
        else if (key === Qt.Key_Down) next = tr === tileRows.length - 1 ? n - 1 : toRow(tr + 1);
        else if (key === Qt.Key_Up) next = tr === 0 ? 0 : toRow(tr - 1);
        else if (key === Qt.Key_PageDown) next = tr === tileRows.length - 1 ? n - 1 : toRow(tr + page);
        else if (key === Qt.Key_PageUp) next = tr === 0 ? 0 : toRow(tr - page);
        else if (key === Qt.Key_Home) { next = 0; gridCol = -1; }
        else if (key === Qt.Key_End) { next = n - 1; gridCol = -1; }
        sel = next;
        confirming = false;
    }
    // Ctrl+Enter: result.mark() toggles membership (e.g. in the wallpaper slideshow); the list stays
    function markSelected() {
        const cur = selectable[sel]?.item;
        if (!cur?.mark) return false;
        // mark() returning "reset" (e.g. opening an edit level) clears the input back to the prefix
        let r;
        try { r = cur.mark(); } catch (e) { console.warn("nox: launcher mark failed:", e); }
        if (r === "reset" && prefixed) { text = prefixed.prefix; search(); return true; }
        search(true);
        return true;
    }
    // Alt+Up/Down: result.move(delta) reorders; the selection follows the moved row (by key ?? title)
    function reorderSelected(d) {
        const cur = selectable[sel]?.item;
        if (!cur?.move) return false;
        const key = cur.key ?? cur.title;
        let moved = false;
        try { moved = cur.move(d) !== false; } catch (e) { console.warn("nox: launcher move failed:", e); }
        if (!moved) return true;
        search(true);
        const i = selectable.findIndex(x => (x.item.key ?? x.item.title) === key);
        if (i >= 0) sel = i;
        return true;
    }
    // nested provider (a sub-level is open): back() returns to its top level, the filter is cleared
    function goBack() {
        if (!nested || !prefixed.p.back) return false;
        try { prefixed.p.back(); } catch (e) { console.warn("nox: launcher back failed:", e); }
        text = prefixed.prefix;
        search();
        return true;
    }
    // Shift+Enter: result.alt() (e.g. reveal a file in its folder); closes the launcher like Enter
    function altSelected() {
        const cur = selectable[sel]?.item;
        if (!cur?.alt) return false;
        Panels.launcherOpen = false;
        try { cur.alt(); } catch (e) { console.warn("nox: launcher alt action failed:", e); }
        return true;
    }
    function runSelected() {
        const cur = selectable[sel]?.item;
        if (!cur) return;
        if (cur.confirm && !confirming) { confirming = true; return; }
        // result.stay: the launcher stays open (drill into / out of a provider's sub-level); the
        // input goes back to the typed prefix and the search re-runs
        if (cur.stay) {
            try { cur.run(); } catch (e) { console.warn("nox: launcher action failed:", e); }
            if (prefixed) text = prefixed.prefix;
            search();
            return;
        }
        Panels.launcherOpen = false;
        try { cur.run(); } catch (e) { console.warn("nox: launcher action failed:", e); }
    }

    // qs -c nox ipc call launcher toggle | open | close | search "<text>" | results
    IpcHandler {
        target: "launcher"
        function toggle(): void { Panels.launcherOpen = !Panels.launcherOpen; }
        function open(): void { Panels.launcherOpen = true; }
        function close(): void { Panels.launcherOpen = false; }
        // open with a query already typed
        // clipboard history (cliphist) inside the launcher
        function clipboard(): void { if (Panels.launcherOpen) { root.text = ":"; root.search(); } else { root.initialText = ":"; Panels.launcherOpen = true; } }
        // emoji picker (Super+.); a second press while it is showing closes the launcher
        function emoji(): void {
            if (Panels.launcherOpen && root.text.startsWith(".")) Panels.launcherOpen = false;
            else if (Panels.launcherOpen) { root.text = "."; root.search(); }
            else { root.initialText = "."; Panels.launcherOpen = true; }
        }
        // command palette (Ctrl+Super+Space): its prefix from shell.json (launcher.provider.palette.prefix,
        // default ">"); a second press while it is showing closes the launcher
        function palette(): void {
            const p = Config.launcherProvider("palette").prefix ?? ">";
            if (Panels.launcherOpen && root.text.startsWith(p)) Panels.launcherOpen = false;
            else if (Panels.launcherOpen) { root.text = p; root.search(); }
            else { root.initialText = p; Panels.launcherOpen = true; }
        }
        function search(query: string): void {
            if (Panels.launcherOpen) { root.text = query; root.search(); }
            else { root.initialText = query; Panels.launcherOpen = true; }
        }
        // run / mark the selected result, as Enter / Ctrl+Enter (scripting/tests)
        function activate(): void { if (Panels.launcherOpen) root.runSelected(); }
        function mark(): void { if (Panels.launcherOpen) root.markSelected(); }
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

    // keycap (mock kbd: 19px, min 19 wide, 0 5px padding, radius 5 / 3 in square looks, white 10%
    // fill, 0.5px light rim + dark bottom edge, label colour 11px medium; Telemetry: label font)
    component Kbd: Rectangle {
        property alias text: kt.text
        implicitWidth: Math.max(19, kt.implicitWidth + 10)
        implicitHeight: 19
        radius: Theme.square ? 3 : 5
        color: Theme.white(0.1)
        border.width: Theme.rimWidth
        border.color: Theme.white(0.14)
        Rectangle { x: parent.radius; width: parent.width - parent.radius * 2; y: parent.height - 1; height: 1; color: Qt.rgba(0, 0, 0, 0.35) }
        GText {
            id: kt
            anchors.centerIn: parent
            font.family: Theme.labelsMono ? Theme.fontLabel : Theme.fontUi
            font.pixelSize: Theme.labelsMono ? 10 : 11
            font.weight: Font.Medium
        }
    }
    // footer hint: "Label ⌨" or "⌨ Label"
    component Hint: Row {
        property string label
        property var keys: []
        property bool keysFirst: false
        spacing: 6
        GText { visible: !parent.keysFirst; text: parent.label; small: true; secondary: true; anchors.verticalCenter: parent.verticalCenter }
        Row {
            spacing: 2
            anchors.verticalCenter: parent.verticalCenter
            Repeater { model: parent.parent.keys; Kbd { required property string modelData; text: modelData } }
        }
        GText { visible: parent.keysFirst; text: parent.label; small: true; secondary: true; anchors.verticalCenter: parent.verticalCenter }
    }

    LazyLoader {
        active: root.shown

        PanelWindow {
            id: win
            screen: root.targetScreen
            color: "transparent"
            WlrLayershell.namespace: "nox:launcher"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            readonly property real shadowPad: 48
            anchors.top: true
            margins.top: Math.max(0, Math.round((screen?.height ?? 900) * (root.opts.top ?? 0.18)) - shadowPad)
            readonly property int bodyWidth: root.opts.width ?? 680
            readonly property int previewWidth: root.opts.previewWidth ?? 560
            implicitWidth: bodyWidth + root.previewGap + previewWidth + shadowPad * 2
            // tall enough for the preview card too when the list is short (one clipboard match)
            implicitHeight: Math.max(body.height, root.previewOn ? preview.height : 0) + shadowPad * 2
            mask: Region { item: body; Region { item: preview } }

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
                // centred alone; slides left to make room for the preview so the pair stays centred
                x: root.previewOn ? win.shadowPad : Math.round((win.width - width) / 2)
                Behavior on x { NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
                y: win.shadowPad
                width: win.bodyWidth
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
                                const alt = e.modifiers & Qt.AltModifier;
                                // modified keys first: they would otherwise fall into the plain branches
                                if (alt && (e.key === Qt.Key_Up || e.key === Qt.Key_Down)) { root.reorderSelected(e.key === Qt.Key_Up ? -1 : 1); e.accepted = true; }
                                else if (ctrl && (e.key === Qt.Key_Return || e.key === Qt.Key_Enter)) { root.markSelected(); e.accepted = true; }
                                else if ((e.modifiers & Qt.ShiftModifier) && (e.key === Qt.Key_Return || e.key === Qt.Key_Enter)) { root.altSelected(); e.accepted = true; }
                                else if (root.gridMode && !(e.modifiers & ~Qt.KeypadModifier)
                                         && [Qt.Key_Left, Qt.Key_Right, Qt.Key_Up, Qt.Key_Down, Qt.Key_PageUp, Qt.Key_PageDown, Qt.Key_Home, Qt.Key_End].includes(e.key)) {
                                    root.gridMove(e.key); e.accepted = true;
                                }
                                else if (e.key === Qt.Key_Down || e.key === Qt.Key_Tab || (ctrl && e.key === Qt.Key_N)) { root.move(1); e.accepted = true; }
                                else if (e.key === Qt.Key_Up || e.key === Qt.Key_Backtab || (ctrl && e.key === Qt.Key_P)) { root.move(-1); e.accepted = true; }
                                else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { root.runSelected(); e.accepted = true; }
                                else if (e.key === Qt.Key_Delete && (e.modifiers & Qt.ShiftModifier)) {
                                    const it = root.selectable[root.sel]?.item;
                                    if (it?.remove) { it.remove(); e.accepted = true; }
                                }
                                else if (e.key === Qt.Key_Backspace && root.nested && root.prefixed.q === "" && !(e.modifiers & ~Qt.KeypadModifier)) {
                                    root.goBack(); e.accepted = true;
                                }
                                else if (e.key === Qt.Key_Escape) {
                                    if (root.confirming) root.confirming = false;
                                    else if (!root.goBack()) Panels.launcherOpen = false;
                                    e.accepted = true;
                                }
                            }
                        }
                    }

                    // ---- results (mock .ln-res) ----
                    Rectangle { visible: root.rows.length > 0 || root.gridMode; width: parent.width; height: Theme.rimWidth; color: Theme.sep }
                    ListView {
                        id: list
                        visible: root.rows.length > 0 && !root.gridMode
                        x: 8
                        width: parent.width - 16
                        height: Math.min(contentHeight, root.opts.maxHeight ?? 404) + (visible ? 8 : 0)
                        bottomMargin: 8
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: rowModel
                        // selection slides between rows (one highlight item under the rows instead
                        // of each row switching its own fill); big rows keep their own outline
                        readonly property var selRow: root.selectable[root.sel] ?? null
                        currentIndex: selRow && !selRow.item?.big ? selRow.row : -1
                        highlightFollowsCurrentItem: true
                        highlightMoveDuration: Theme.durHover
                        highlightMoveVelocity: -1
                        highlightResizeDuration: Theme.durHover
                        highlightResizeVelocity: -1
                        highlight: Rectangle {
                            radius: Theme.square ? 3 : Math.min(8, Theme.radiusMenu)
                            color: Theme.selectionNeutral ? Theme.fill2 : Theme.accent
                            Rectangle { visible: Theme.selectionNeutral; width: 2; height: parent.height; color: Theme.accent }
                        }
                        // keep the selection in view
                        Connections {
                            target: root
                            function onSelChanged() {
                                if (root.gridMode) return;
                                const r = root.selectable[root.sel]?.row;
                                if (r !== undefined) list.positionViewAtIndex(r, ListView.Contain);
                                if (root.sel === 0) list.positionViewAtBeginning();
                            }
                        }
                        delegate: Loader {
                            id: rowLoader
                            required property int index
                            readonly property var row: root.rows[index] ?? null
                            width: list.width
                            sourceComponent: !row ? null : row.header !== undefined ? headerRow : row.item.big ? bigRow : itemRow
                            onLoaded: item.modelData = row
                            onRowChanged: if (item && row) item.modelData = row
                        }
                    }

                    // ---- grid (grid providers: emoji) - one ListView row per header / row of tiles,
                    // so only the visible tiles exist; fixed height, so typing never resizes the panel ----
                    Item {
                        visible: root.gridMode
                        width: parent.width
                        height: visible ? root.gridHeight : 0
                        GText {
                            visible: root.selectable.length === 0
                            anchors.centerIn: parent
                            text: root.prefixed?.p.entries?.length === 0 ? "Loading…" : "No results"
                            secondary: true
                        }
                        ListView {
                            id: grid
                            // 4px wider on each side than the tiles, so the selection ring isn't clipped
                            x: 4; y: 0
                            width: root.gridWidth + 8
                            height: parent.height
                            topMargin: 4; bottomMargin: 10
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            cacheBuffer: 2 * (root.gridTile + root.gridGap)
                            model: gridModel
                            // keep the selected tile in view, with its section header when it's the first row
                            function reveal() {
                                const tr = root.tileRows[root.tileRowOf[root.sel] ?? -1];
                                if (!tr) return;
                                if (root.sel === 0) { positionViewAtBeginning(); return; }
                                if (root.gridRows[tr.row - 1]?.header !== undefined) positionViewAtIndex(tr.row - 1, ListView.Contain);
                                positionViewAtIndex(tr.row, ListView.Contain);
                            }
                            Connections {
                                target: root
                                function onSelChanged() { if (root.gridMode) grid.reveal(); }
                                function onGridRowsChanged() { if (root.gridMode && root.sel === 0) grid.positionViewAtBeginning(); }
                            }
                            delegate: Loader {
                                required property int index
                                readonly property var row: root.gridRows[index] ?? null
                                width: grid.width
                                sourceComponent: !row ? null : row.header !== undefined ? gridHeader : tileRow
                                onLoaded: item.modelData = row
                                onRowChanged: if (item && row) item.modelData = row
                            }
                        }
                    }

                    // ---- footer (mock .ln-foot) ----
                    Rectangle { width: parent.width; height: Theme.rimWidth; color: Theme.sep }
                    // Right: action / navigate / close (always shown). Left: brand + provider prefix
                    // hints, as many as fit before the right group (the rest are dropped, never
                    // overlapped); the brand text elides if even it doesn't fit.
                    Item {
                        width: parent.width; height: 38
                        Item {
                            id: footLeft
                            x: 14; height: parent.height
                            width: Math.max(0, footRight.x - 16 - x)
                            clip: true
                            readonly property real gap: 14
                            // how many prefix hints fit after the brand (delegate widths don't
                            // depend on visibility, so this can't feed back)
                            readonly property int fit: {
                                hintRep.count; width;
                                let w = brand.implicitWidth, n = 0;
                                for (let i = 0; i < hintRep.count; i++) {
                                    const it = hintRep.itemAt(i);
                                    if (!it) break;
                                    w += footLeft.gap + it.implicitWidth;
                                    if (w > footLeft.width) break;
                                    n++;
                                }
                                return n;
                            }
                            // grid mode: the selected tile, large, and its name instead of brand + hints
                            Row {
                                visible: root.gridMode && root.selectable.length > 0
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 9
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.selectable[root.sel]?.item.glyph ?? ""
                                    font.family: Theme.fontEmoji; font.pixelSize: 18
                                }
                                GText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.min(implicitWidth, footLeft.width - 27)
                                    text: root.selectable[root.sel]?.item.title ?? ""
                                }
                            }
                            Row {
                                id: brand
                                visible: !root.gridMode
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 7
                                LogoGlyph { anchors.verticalCenter: parent.verticalCenter; width: 14; height: 14 }
                                GText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.min(implicitWidth, footLeft.width - 21)
                                    text: "Nox Launcher"; small: true; secondary: true
                                }
                            }
                            Row {
                                x: brand.implicitWidth + footLeft.gap
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: footLeft.gap
                                Repeater {
                                    id: hintRep
                                    model: root.text === "" ? root.footerHints : []
                                    Hint {
                                        required property var modelData
                                        required property int index
                                        visible: index < footLeft.fit && !root.gridMode
                                        anchors.verticalCenter: parent?.verticalCenter
                                        keysFirst: true
                                        keys: [modelData[0]]
                                        label: modelData[1]
                                    }
                                }
                            }
                        }
                        Row {
                            id: footRight
                            anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                            spacing: 16
                            Hint {
                                visible: root.selectable.length > 0
                                label: root.confirming ? "Confirm" : (root.selectable[root.sel]?.item.actLabel ?? "Open")
                                keys: ["↵"]
                            }
                            // only while the selected result supports them
                            Hint {
                                visible: !!root.selectable[root.sel]?.item.mark
                                label: root.selectable[root.sel]?.item.markLabel ?? "Mark"
                                keys: ["ctrl", "↵"]
                            }
                            Hint {
                                visible: !!root.selectable[root.sel]?.item.alt
                                label: root.selectable[root.sel]?.item.altLabel ?? "Alternate"
                                keys: ["⇧", "↵"]
                            }
                            Hint {
                                visible: !!root.selectable[root.sel]?.item.move
                                label: "Reorder"
                                keys: ["alt", "↑", "↓"]
                            }
                            Hint { visible: !root.gridMode; label: "Navigate"; keys: ["↑", "↓"] }
                            Hint { label: root.nested ? "Back" : "Close"; keys: ["esc"] }
                        }
                    }
                }
            }

            // ---- preview of the selected result: screen-shaped, so a wallpaper is judged as it
            // will be cropped (result.previewFit = letterbox instead: files, clipboard images).
            // The shown image only changes once the next one is decoded, so moving the selection
            // never blinks to empty. Text (result.previewText) fills the same frame: a colour as a
            // swatch, a lone URL as its domain, anything else as wrapped text (monospace when it
            // looks like code, or result.previewMono). Caption: result.previewTitle / previewTag,
            // default = the title's last path segment and its folder. ----
            RectangularShadow {
                anchors.fill: preview
                radius: preview.radius
                offset.y: 24; blur: 60; spread: -6
                color: Theme.rgba("#000000", 0.5)
                opacity: preview.opacity
            }
            Glass {
                id: preview
                strong: true
                brackets: Theme.cardBrackets
                x: body.x + body.width + root.previewGap
                y: win.shadowPad
                width: win.previewWidth
                height: shot.height + 2 * pad + caption.height
                radius: body.radius
                readonly property int pad: 8
                opacity: root.open && root.previewOn ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Theme.durPop; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }

                readonly property real aspect: win.screen ? win.screen.width / win.screen.height : 16 / 9
                readonly property real dpr: win.screen?.devicePixelRatio ?? 1
                readonly property int fill: root.previewItem?.previewFit ? Image.PreserveAspectFit : Image.PreserveAspectCrop
                property string cur: ""
                Connections {
                    target: root
                    function onPreviewUrlChanged() { if (root.previewUrl && preview.cur === "") preview.cur = root.previewUrl; }
                }

                ClippingRectangle {
                    id: shot
                    x: preview.pad; y: preview.pad
                    width: parent.width - 2 * preview.pad
                    height: Math.round(width / preview.aspect)
                    radius: Math.max(0, preview.radius - preview.pad / 2)
                    color: root.previewColor ?? Theme.page
                    Image {
                        anchors.fill: parent
                        visible: root.previewUrl !== ""
                        source: preview.cur
                        fillMode: preview.fill
                        sourceSize: Qt.size(Math.round(shot.width * preview.dpr), Math.round(shot.height * preview.dpr))
                        asynchronous: true
                        cache: true
                        smooth: true
                    }
                    // decodes the next selection off-screen, then takes over
                    Image {
                        id: incoming
                        visible: false
                        source: root.previewUrl
                        sourceSize: Qt.size(Math.round(shot.width * preview.dpr), Math.round(shot.height * preview.dpr))
                        fillMode: preview.fill
                        asynchronous: true
                        cache: true
                        onStatusChanged: if (status === Image.Ready || status === Image.Error) preview.cur = source
                    }

                    // colour: the frame is the swatch; the value in a contrasting colour
                    Column {
                        visible: root.previewText !== "" && root.previewColor !== null
                        anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 18
                        spacing: 4
                        readonly property color ink: root.previewColor && (0.299 * root.previewColor.r + 0.587 * root.previewColor.g + 0.114 * root.previewColor.b) * root.previewColor.a > 0.55 ? "#000000" : "#ffffff"
                        GText {
                            text: root.previewText.trim()
                            color: parent.ink
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fontSizeLarge
                        }
                        GText {
                            readonly property var c: root.previewColor
                            text: c ? "rgb(" + Math.round(c.r * 255) + ", " + Math.round(c.g * 255) + ", " + Math.round(c.b * 255) + ")"
                                      + (c.a < 1 ? " · " + Math.round(c.a * 100) + "%" : "") : ""
                            color: parent.ink
                            opacity: 0.7
                            small: true
                            font.family: Theme.fontMono
                        }
                    }
                    // URL: the domain large, the full address under it
                    Column {
                        visible: root.previewText !== "" && root.previewHost !== ""
                        anchors.centerIn: parent
                        width: parent.width - 48
                        spacing: 10
                        Glyph { anchors.horizontalCenter: parent.horizontalCenter; name: "globe"; size: 30; color: Theme.label2 }
                        GText {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideMiddle
                            text: root.previewHost
                            font.family: Theme.fontDisplay
                            font.pixelSize: Theme.fontSizeHero
                        }
                        GText {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WrapAnywhere
                            maximumLineCount: 3
                            text: root.previewText.trim()
                            small: true; secondary: true
                        }
                    }
                    // plain text
                    GText {
                        visible: root.previewText !== "" && root.previewColor === null && root.previewHost === ""
                        x: 16; y: 14
                        width: parent.width - 32
                        height: parent.height - 28
                        verticalAlignment: Text.AlignTop
                        textFormat: Text.PlainText
                        wrapMode: root.previewMono ? Text.WrapAnywhere : Text.Wrap
                        elide: Text.ElideRight
                        // a huge entry: only what can show (the elide still marks the cut)
                        text: (root.previewText.length > 6000 ? root.previewText.slice(0, 6000) : root.previewText).replace(/\t/g, "    ")
                        font.family: root.previewMono ? Theme.fontMono : Theme.fontUi
                        font.pixelSize: root.previewMono ? Theme.fontSize - 1 : Theme.fontSize
                        lineHeight: root.previewMono ? 1.05 : 1.15
                    }
                }
                Item {
                    id: caption
                    x: preview.pad + 4
                    y: shot.y + shot.height
                    width: parent.width - 2 * preview.pad - 8
                    height: 34
                    readonly property var it: root.previewItem
                    GText {
                        anchors.left: parent.left
                        anchors.right: tag.left; anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideMiddle
                        text: caption.it?.previewTitle ?? (caption.it?.title ?? "").split("/").pop()
                    }
                    GText {
                        id: tag
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        small: true; secondary: true
                        text: caption.it?.previewTag ?? (caption.it?.type === "Current" ? "Current" : (caption.it?.title ?? "").split("/").slice(-2, -1)[0] ?? "")
                    }
                }
            }
        }
    }

    // ---- grid row types: section header ("Smileys & Emotion  171") and a row of tiles ----
    Component {
        id: gridHeader
        Row {
            property var modelData: null
            leftPadding: 6; topPadding: 10; bottomPadding: 8
            spacing: 7
            SectionLabel { width: implicitWidth; leftPadding: 0; rightPadding: 0; topPadding: 0; bottomPadding: 0; text: parent.modelData?.header ?? "" }
            SectionLabel { width: implicitWidth; leftPadding: 0; rightPadding: 0; topPadding: 0; bottomPadding: 0; text: parent.modelData?.count ?? ""; color: Theme.label3; font.family: Theme.fontMono }
        }
    }

    Component {
        id: tileRow
        Item {
            id: tr
            property var modelData: null
            height: root.gridTile + root.gridGap
            Repeater {
                model: tr.modelData?.count ?? 0
                Rectangle {
                    id: tile
                    required property int index
                    readonly property int si: (tr.modelData?.start ?? 0) + index
                    readonly property bool selected: si === root.sel
                    x: 4 + index * (root.gridTile + root.gridGap)
                    width: root.gridTile; height: root.gridTile
                    radius: Theme.square ? 3 : Math.min(12, Theme.radiusPanel)
                    color: selected ? Theme.rgba(Theme.t.color.accent, 0.12) : Theme.fill
                    // the ring: accent, drawn just outside the fill so the tile keeps its size
                    Rectangle {
                        anchors.fill: parent; anchors.margins: -3
                        radius: parent.radius + 3
                        color: "transparent"
                        border.width: 2
                        border.color: root.confirming ? Theme.red : Theme.accent
                        opacity: tile.selected ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.durHover } }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: root.selectable[tile.si]?.item.glyph ?? ""
                        font.family: Theme.fontEmoji
                        font.pixelSize: Math.round(root.gridTile * 0.44)
                        scale: tile.selected ? 1.1 : 1
                        Behavior on scale { NumberAnimation { duration: Theme.durHover; easing.type: Easing.OutCubic } }
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onPositionChanged: if (root.sel !== tile.si) { root.sel = tile.si; root.confirming = false; root.gridCol = -1; }
                        onClicked: { root.sel = tile.si; root.runSelected(); }
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
            height: (r.it.thumb ?? "") !== "" || r.it.thumbSlot ? 52 : 40
            radius: Theme.square ? 3 : Math.min(8, Theme.radiusMenu)
            // the selection fill is the ListView highlight (it slides); only the confirm state paints here
            color: asking ? Theme.red : "transparent"
            readonly property color fg: accentSel ? Theme.onAccent : Theme.label
            readonly property color fg2: accentSel ? Theme.rgba(Theme.t.color.onAccent, 0.75) : Theme.label2

            Item {
                id: ico
                readonly property bool hasThumb: (r.it.thumb ?? "") !== "" || !!r.it.thumbSlot
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
                    Glyph { anchors.centerIn: parent; visible: !r.it.glyph; name: r.it.icon ?? "dots"; size: 15; color: r.fg }
                    // literal character (emoji): the UI font's fallback is monochrome, so name the emoji font
                    Text { anchors.centerIn: parent; visible: !!r.it.glyph; text: r.it.glyph ?? ""; font.family: Theme.fontEmoji; font.pixelSize: 16 }
                }
                // result.badge: small numbered pill on the icon's corner (slideshow position)
                Rectangle {
                    visible: (r.it.badge ?? "") !== ""
                    x: -4; y: -4
                    width: Math.max(height, badgeText.implicitWidth + 8); height: 16
                    radius: Theme.square ? 3 : height / 2
                    color: Theme.accent
                    border.width: Theme.rimWidth
                    border.color: Theme.rgba("#000000", 0.35)
                    GText {
                        id: badgeText
                        anchors.centerIn: parent
                        text: r.it.badge ?? ""
                        color: Theme.onAccent
                        font.family: Theme.labelsMono ? Theme.fontLabel : Theme.fontUi
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }
                }
            }
            Row {
                anchors.left: ico.right; anchors.leftMargin: 11
                anchors.right: kc.left; anchors.rightMargin: 12
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
            // result.keys: keycaps of the result's shortcut (command palette), left of the type tag
            Row {
                id: kc
                anchors.right: ty.left; anchors.rightMargin: (r.it.keys ?? []).length && (r.it.type ?? "") !== "" ? 10 : 0
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                visible: !r.asking
                Repeater {
                    model: r.asking ? [] : (r.it.keys ?? [])
                    Keycap { required property string modelData; text: modelData }
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
