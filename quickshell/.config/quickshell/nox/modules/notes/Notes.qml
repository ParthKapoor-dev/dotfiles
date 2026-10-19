pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Window
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.core
import qs.components
import qs.services

// Notes: a floating, always-on-top markdown notepad (Ctrl+Super+N; IPC `notes toggle|open|hide|create|openNote <path>`).
// One real window (title "Notes", Hyprland rule: float, pin = on every desktop, centred) with a
// sidebar of notes (notes.directory, default ~/Notes, *.md, newest first, search) and a rich editor:
// Qt's own markdown document (TextEdit MarkdownText), so what you see is styled and what is saved is
// plain markdown any editor opens. Saves on its own 600 ms after you stop typing (and on switching
// notes / hiding). A new note is "Untitled.md" until its first line names it.
//   Blocks: type "# " "## " "### " "- " "1. " "[] " "> " at a line start, or "/" on an empty line
//           for the block menu; the toolbar; Ctrl+0..3 = paragraph / headings,
//           Ctrl+Shift+7 / 8 / 9 = numbered / bullets / checklist, Ctrl+Shift+. = quote
//   Inline: Ctrl+B / I, Ctrl+Shift+X strike, Ctrl+E code, Ctrl+K link
//   Checklist: click the box or Ctrl+Enter.  Ctrl+N new, Ctrl+P find a note, Ctrl+S save now,
//   Ctrl+\ sidebar, Ctrl+M markdown source view, Esc hide.
// How block changes work: Qt only parses markdown on insert and merges the first inserted block into
// the current one (keeping its old format), so a line is retyped as "\u200b<sep>" + markdown and the
// zero-width stub is deleted together with the separator before it (see setBlock).
Scope {
    id: root
    readonly property var opts: Config.opt.notes ?? ({})
    readonly property string home: Quickshell.env("HOME")
    readonly property string dir: (opts.directory ?? "~/Notes").replace(/^~/, home)
    property bool shown: false
    property string current: ""            // absolute path of the open note
    property bool source: false            // markdown source view
    property bool sidebar: state.data.sidebar ?? true
    property string status: ""
    property real savedAt: 0

    function toggle() { if (shown) hide(); else show(); }
    function show() {
        shown = true;
        if (!current) openLast();
        Qt.callLater(() => editor.forceActiveFocus());
    }
    function hide() {
        if (dropIfEmpty()) { current = ""; editor.text = ""; } else saveNow();
        shown = false;
    }
    function url(p) { return "file://" + p; }
    function base(p) { return p.split("/").pop().replace(/\.md$/i, ""); }

    JsonState { id: state; path: Paths.state("notes") }
    // the folder list is pointed at the directory only once it exists (it doesn't notice later)
    property bool dirReady: false
    Process { id: mk; command: ["mkdir", "-p", root.dir]; running: true; onExited: root.dirReady = true }

    function openLast() {
        const last = state.data.last ?? "";
        if (last) { checkOpen.path = last; checkOpen.running = true; }
        else newNote();
    }
    Process {
        id: checkOpen
        property string path
        command: ["test", "-f", path]
        onExited: code => { if (code === 0) root.open(path); else root.newNote(); }
    }

    // an "Untitled" note nobody wrote in is removed when you leave it
    function dropIfEmpty() {
        if (!current || !/^Untitled( \d+)?$/.test(base(current))) return false;
        if (editor.getText(0, editor.length).replace(/[\u200b\s]/g, "") !== "") return false;
        dropper.command = ["rm", "-f", "--", current];
        dropper.running = true;
        return true;
    }
    Process { id: dropper }
    function open(p) {
        if (p === current) return;
        if (!dropIfEmpty()) saveNow();
        loading = true;
        current = p;
        source = false;
        editor.textDocument.source = url(p);
        state.data = Object.assign({}, state.data, { last: p });
        state.save();
        Qt.callLater(() => { loading = false; editor.textDocument.modified = false; status = ""; editor.cursorPosition = editor.length; editor.forceActiveFocus(); });
    }
    property bool loading: false

    // Untitled.md, Untitled 2.md, ...
    function newNote() {
        let n = 1, name;
        const taken = {};
        for (let i = 0; i < files.count; i++) taken[files.get(i, "fileName").toLowerCase()] = true;
        do { name = n === 1 ? "Untitled.md" : "Untitled " + n + ".md"; n++; } while (taken[name.toLowerCase()]);
        creator.path = dir + "/" + name;
        creator.running = true;
    }
    Process {
        id: creator
        property string path
        command: ["sh", "-c", "mkdir -p \"${1%/*}\" && : >> \"$1\"", "sh", path]
        onExited: root.open(path)
    }

    function saveNow() {
        saveTimer.stop();
        if (!current || loading) return;
        if (source) { srcFile.setText(srcEdit.text.replace(/\u200b/g, "")); editor.textDocument.modified = false; markSaved(); return; }
        if (!editor.textDocument.modified) return;
        srcFile.setText(editor.text.replace(/\u200b/g, ""));
        editor.textDocument.modified = false;
        markSaved();
    }
    function markSaved() {
        savedAt = Date.now();
        status = "Saved";
        autoName();
    }
    Timer { id: saveTimer; interval: root.opts.saveDelay ?? 600; onTriggered: root.saveNow() }
    // writes are synchronous: a rename right after a save must find the file complete
    FileView { id: srcFile; path: root.current; printErrors: false; blockLoading: true; blockWrites: true }

    // an "Untitled" note takes the name of its first line once it has one
    function autoName() {
        if (!/^Untitled( \d+)?$/.test(base(current))) return;
        const first = editor.getText(0, Math.min(editor.length, 200)).split(/[\u2029\n\u2028]/)[0].replace(/[\/\\:*?"<>|\u200b]/g, "").trim().slice(0, 60);
        if (first.length < 2) return;
        rename(first);
    }
    function rename(name) {
        name = String(name).replace(/[\/\\]/g, "-").replace(/\.md$/i, "").trim();
        if (!name || !current || name === base(current)) return;
        renamer.from = current;
        renamer.to = dir + "/" + name + ".md";
        renamer.running = true;
    }
    Process {
        id: renamer
        property string from
        property string to
        command: ["sh", "-c", "[ ! -e \"$2\" ] && mv -- \"$1\" \"$2\"", "sh", from, to]
        onExited: code => {
            if (code !== 0) { root.status = "A note with that name exists"; return; }
            // same content, new path: no reload (keeps the cursor and undo); saves go to `current`
            if (root.current === from) {
                root.current = to;
                state.data = Object.assign({}, state.data, { last: to });
                state.save();
            }
        }
    }
    function trash(p) {
        trasher.path = p;
        trasher.running = true;
    }
    Process {
        id: trasher
        property string path
        command: ["gio", "trash", "--", path]
        onExited: {
            if (path !== root.current) return;
            root.current = "";
            Qt.callLater(() => { for (let i = 0; i < files.count; i++) { const f = files.get(i, "filePath"); if (f !== path) { root.open(f); return; } } root.newNote(); });
        }
    }

    FolderListModel {
        id: files
        folder: root.dirReady ? root.url(root.dir) : ""
        nameFilters: ["*.md"]
        showDirs: false
        sortField: FolderListModel.Time
    }

    // ---- block helpers (positions are plain-text positions; markers are not characters) ----
    function sepAt(t, i) { const c = t.charCodeAt(i); return c === 0x2029 || c === 10 || c === 0x2028; }
    function blockRange(pos) {
        const t = editor.getText(0, editor.length);
        let s = Math.min(pos, t.length), e = s;
        while (s > 0 && !sepAt(t, s - 1)) s--;
        while (e < t.length && !sepAt(t, e)) e++;
        return [s, e];
    }
    function blockMd(r) { return editor.getFormattedText(r[0], r[1]).replace(/\n+$/, ""); }
    // "- [ ] x" -> { kind: "check", checked, text } etc.; text keeps its inline markdown
    function parse(md) {
        let m;
        if ((m = md.match(/^(#{1,6})(?: ([\s\S]*))?$/))) return { kind: "h" + Math.min(3, m[1].length), text: m[2] ?? "" };
        if ((m = md.match(/^[-*+] \[([ xX])\](?: ([\s\S]*))?$/))) return { kind: "check", checked: m[1] !== " ", text: m[2] ?? "" };
        if ((m = md.match(/^[-*+](?: ([\s\S]*))?$/))) return { kind: "bullet", text: m[1] ?? "" };
        if ((m = md.match(/^\d+[.)](?: +([\s\S]*))?$/))) return { kind: "number", text: m[1] ?? "" };
        if ((m = md.match(/^>(?: ?([\s\S]*))?$/))) return { kind: "quote", text: m[1] ?? "" };
        return { kind: "p", text: md };
    }
    function marker(kind, checked) {
        return ({ h1: "# ", h2: "## ", h3: "### ", bullet: "- ", number: "1. ", check: checked ? "- [x] " : "- [ ] ", quote: "> ", p: "" })[kind] ?? "";
    }
    // replace the block at pos with markdown md; keeps the caret at the same text offset
    function setBlock(pos, md, caret) {
        const r = blockRange(pos);
        const off = caret === undefined ? editor.cursorPosition - r[0] : caret;
        const s = r[0];
        // a block with no text yet ("# " alone) is dropped by the markdown parser: hold it open
        // with a zero-width character
        const hold = md !== "" && /^(#{1,6} |[-*+] (\[[ xX]\] )?|\d+[.)] |> ?)$/.test(md);
        if (hold) md += "\u200b";
        editor.remove(r[0], r[1]);
        editor.insert(s, "\u200b\n\n" + (md || "\u200b"));
        // drop the stub: with a block before it, delete that block's separator + the stub (the
        // previous block keeps its format); at the very start, delete the stub + its separator
        // (Qt keeps the following block's format there)
        if (s > 0) editor.remove(s - 1, s + 1);
        else editor.remove(0, 2);
        if (!md) { const r2 = blockRange(s); if (editor.getText(r2[0], r2[1]) === "\u200b") editor.remove(r2[0], r2[1]); }
        // (the holding zero-width character stays until text is typed after it; saving strips it)
        editor.cursorPosition = Math.min(blockRange(s)[1], s + Math.max(0, off) + (hold ? 1 : 0));
    }
    // toolbar / shortcut: set (or toggle back to paragraph) the current block's kind
    function applyBlock(kind) {
        const r = blockRange(editor.cursorPosition);
        const b = parse(blockMd(r));
        const to = b.kind === kind && kind !== "p" ? "p" : kind;
        setBlock(r[0], marker(to, false) + b.text);
    }
    function toggleCheck(pos) {
        const r = blockRange(pos);
        const b = parse(blockMd(r));
        if (b.kind !== "check") return false;
        setBlock(r[0], marker("check", !b.checked) + b.text);
        return true;
    }
    function inline(prop) {
        const f = editor.cursorSelection.font;
        if (prop === "code") { f.family = f.family === Theme.fontMono ? Theme.fontUi : Theme.fontMono; }
        else f[prop] = !f[prop];
        editor.cursorSelection.font = f;
    }
    function insertLink(href) {
        const sel = editor.selectedText || href;
        const s = editor.selectionStart;
        editor.remove(editor.selectionStart, editor.selectionEnd);
        editor.insert(s, "[" + sel.replace(/[\[\]]/g, "") + "](" + href + ")");
    }
    function divider() {
        const r = blockRange(editor.cursorPosition);
        setBlock(r[0], "---");
        editor.insert(blockRange(editor.cursorPosition)[1], "\u200b\n\n\u200b");
    }
    // markdown typed at a line start + Space
    readonly property var triggers: ({ "#": "h1", "##": "h2", "###": "h3", "-": "bullet", "*": "bullet", "+": "bullet",
                                       "1.": "number", "1)": "number", ">": "quote", "[]": "check", "[ ]": "check", "[x]": "checkx" })
    function autoFormat() {
        const pos = editor.cursorPosition;
        const r = blockRange(pos);
        const head = editor.getText(r[0], pos);
        const k = triggers[head];
        if (!k || pos - r[0] > 3) return false;
        editor.remove(r[0], pos);
        const b = parse(blockMd(blockRange(r[0])));
        setBlock(r[0], (k === "checkx" ? marker("check", true) : marker(k, false)) + (b.kind === "p" ? b.text : b.text), 0);
        return true;
    }

    // Backspace at the start of a heading / list item / quote: back to plain text
    function backspaceKey() {
        if (editor.selectedText !== "") return false;
        const r = blockRange(editor.cursorPosition);
        if (editor.getText(r[0], editor.cursorPosition).replace(/\u200b/g, "") !== "") return false;
        const b = parse(blockMd(r));
        if (b.kind === "p") return false;
        setBlock(r[0], b.text.replace(/\u200b/g, ""), 0);
        return true;
    }
    // Enter on an empty list item / quote ends the list (back to a paragraph)
    function enterKey() {
        const r = blockRange(editor.cursorPosition);
        const b = parse(blockMd(r));
        if (b.kind === "p" || /^h/.test(b.kind) || b.text.replace(/\u200b/g, "").trim() !== "") return false;
        setBlock(r[0], "", 0);
        return true;
    }

    // ---- slash menu ----
    readonly property var blocks: [
        { id: "p", name: "Text", hint: "Plain paragraph", icon: "notes" },
        { id: "h1", name: "Heading 1", hint: "#", icon: "title" },
        { id: "h2", name: "Heading 2", hint: "##", icon: "title" },
        { id: "h3", name: "Heading 3", hint: "###", icon: "title" },
        { id: "bullet", name: "Bulleted list", hint: "-", icon: "format_list_bulleted" },
        { id: "number", name: "Numbered list", hint: "1.", icon: "format_list_numbered" },
        { id: "check", name: "Checklist", hint: "[]", icon: "checklist" },
        { id: "quote", name: "Quote", hint: ">", icon: "format_quote" },
        { id: "code", name: "Code block", hint: "```", icon: "code" },
        { id: "divider", name: "Divider", hint: "---", icon: "horizontal_rule" }
    ]
    property int slashAt: -1                // position of the "/" while the menu is open
    property string slashQuery: ""
    property int slashSel: 0
    readonly property var slashItems: blocks.filter(b => !slashQuery || (b.name + " " + b.id).toLowerCase().includes(slashQuery.toLowerCase()))
    function slashUpdate() {
        if (slashAt < 0) return;
        const pos = editor.cursorPosition;
        const r = blockRange(slashAt);
        if (pos <= slashAt || pos > r[1] || editor.getText(slashAt, slashAt + 1) !== "/") { slashAt = -1; return; }
        slashQuery = editor.getText(slashAt + 1, pos);
        if (slashQuery.includes(" ") || slashItems.length === 0 && slashQuery.length > 12) slashAt = -1;
        slashSel = Math.min(slashSel, Math.max(0, slashItems.length - 1));
    }
    function slashPick(b) {
        const at = slashAt;
        slashAt = -1;
        if (!b) return;
        editor.remove(at, editor.cursorPosition);
        editor.cursorPosition = at;
        if (b.id === "divider") divider();
        else if (b.id === "code") { const r = blockRange(at); setBlock(r[0], "```\n" + parse(blockMd(r)).text + "\n```", 0); }
        else applyBlock(b.id === "p" ? "p" : b.id);
    }

    // ---- what the caret is in (toolbar state) ----
    property string curKind: "p"
    property bool curBold: false
    property bool curItalic: false
    property bool curStrike: false
    property bool curCode: false
    function refreshState() {
        if (source || !current) return;
        curKind = parse(blockMd(blockRange(editor.cursorPosition))).kind;
        const f = editor.cursorSelection.font;
        curBold = f.bold; curItalic = f.italic; curStrike = f.strikeout; curCode = f.family === Theme.fontMono;
    }
    Timer { id: stateTimer; interval: 60; onTriggered: root.refreshState() }

    IpcHandler {
        target: "notes"
        function toggle(): void { root.toggle(); }
        function open(): void { root.show(); }
        function hide(): void { root.hide(); }
        function create(): void { root.show(); root.newNote(); }
        function openNote(path: string): void { root.open(path.replace(/^~/, root.home)); root.show(); }
        function current(): string { return root.current; }
    }
    Connections { target: Panels; function onNotesCommand(cmd) { if (cmd === "new") { root.show(); root.newNote(); } else if (cmd === "toggle") root.toggle(); else root.show(); } }

    // ---- UI ----
    component ToolBtn: Rectangle {
        id: tb
        property string icon
        property string label: ""
        property string tip: ""
        property bool on: false
        signal clicked()
        width: label ? Math.max(28, lbl.implicitWidth + 14) : 28; height: 28
        radius: Theme.square ? 4 : 7
        color: on ? Theme.rgba(Theme.t.color.accent, 0.18) : ma.containsMouse ? Theme.fill2 : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.durHover } }
        Glyph { visible: !tb.label; anchors.centerIn: parent; name: tb.icon; size: 16; color: tb.on ? Theme.accent : Theme.label }
        GText { id: lbl; visible: !!tb.label; anchors.centerIn: parent; text: tb.label; font.weight: Font.DemiBold; font.pixelSize: 13; color: tb.on ? Theme.accent : Theme.label }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: { tb.clicked(); editor.forceActiveFocus(); } }
        ToolTip_ { visible: ma.containsMouse && tb.tip !== ""; text: tb.tip }
    }
    component ToolTip_: Rectangle {
        property string text
        z: 50
        y: parent.height + 6
        anchors.horizontalCenter: parent.horizontalCenter
        width: tt.implicitWidth + 14; height: 22
        radius: Theme.square ? 3 : 6
        color: Theme.rgba("#0A0A0A", 0.95)
        border.width: 1; border.color: Theme.hair
        GText { id: tt; anchors.centerIn: parent; text: parent.text; small: true }
    }
    component Sep: Rectangle { width: 1; height: 16; color: Theme.sep; anchors.verticalCenter: parent?.verticalCenter }

    FloatingWindow {
        id: win
        visible: root.shown
        title: "Notes"
        color: Theme.bg
        implicitWidth: root.opts.width ?? 860
        implicitHeight: root.opts.height ?? 580
        onVisibleChanged: if (!visible) root.saveNow()

        Item {
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: { if (root.slashAt >= 0) root.slashAt = -1; else root.hide(); }

            // ---- sidebar ----
            Rectangle {
                id: side
                visible: root.sidebar
                width: visible ? 220 : 0
                anchors.top: parent.top; anchors.bottom: parent.bottom
                color: Theme.surface
                Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.sep }
                Column {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8
                    Row {
                        width: parent.width
                        spacing: 6
                        Rectangle {
                            width: parent.width - 34; height: 30
                            radius: Theme.square ? 4 : 8
                            color: Theme.fill
                            border.width: find.activeFocus ? 1 : 0; border.color: Theme.rgba(Theme.t.color.accent, 0.6)
                            Glyph { x: 8; anchors.verticalCenter: parent.verticalCenter; name: "search"; size: 14; color: Theme.label2 }
                            TextInput {
                                id: find
                                x: 28; width: parent.width - 34
                                anchors.verticalCenter: parent.verticalCenter
                                color: Theme.label; font.family: Theme.fontUi; font.pixelSize: 13
                                selectionColor: Theme.rgba(Theme.t.color.accent, 0.4)
                                clip: true
                                Keys.onEscapePressed: { text = ""; editor.forceActiveFocus(); }
                                Keys.onReturnPressed: { const f = list.itemAtIndex(0); if (f) root.open(f.path); find.text = ""; }
                                Keys.onDownPressed: editor.forceActiveFocus()
                                GText { visible: !find.text; text: "Find a note"; secondary: true; anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 13 }
                            }
                        }
                        ToolBtn { icon: "add"; tip: "New note  Ctrl+N"; onClicked: root.newNote(); width: 28; height: 30 }
                    }
                    ListView {
                        id: list
                        width: parent.width
                        height: parent.height - 38
                        clip: true
                        spacing: 2
                        boundsBehavior: Flickable.StopAtBounds
                        model: files
                        delegate: Rectangle {
                            id: row
                            required property string fileName
                            required property string filePath
                            required property date fileModified
                            readonly property string path: filePath
                            readonly property string nm: fileName.replace(/\.md$/i, "")
                            readonly property bool match: !find.text || nm.toLowerCase().includes(find.text.toLowerCase())
                            readonly property bool cur: filePath === root.current
                            visible: match
                            width: list.width
                            height: match ? 46 : 0
                            radius: Theme.square ? 4 : 8
                            color: cur ? Theme.fill2 : rm.containsMouse ? Theme.fill : "transparent"
                            Rectangle { visible: row.cur; width: 2; height: 18; radius: 1; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
                            Column {
                                x: 10; anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 40
                                spacing: 2
                                GText { width: parent.width; text: row.nm; elide: Text.ElideRight; font.weight: row.cur ? Font.DemiBold : Font.Medium }
                                GText {
                                    text: {
                                        const m = Math.floor((Date.now() - row.fileModified.getTime()) / 60000);
                                        return m < 1 ? "Just now" : m < 60 ? m + " min ago" : m < 1440 ? Math.floor(m / 60) + " h ago" : Qt.formatDate(row.fileModified, "d MMM yyyy");
                                    }
                                    small: true; secondary: true
                                }
                            }
                            MouseArea { id: rm; anchors.fill: parent; hoverEnabled: true; onClicked: root.open(row.filePath) }
                            Rectangle {
                                anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter
                                width: 22; height: 22; radius: Theme.square ? 3 : 6
                                visible: rm.containsMouse || dm.containsMouse
                                color: dm.containsMouse ? Theme.fill3 : "transparent"
                                Glyph { anchors.centerIn: parent; name: "trash"; size: 13; color: dm.containsMouse ? Theme.accent : Theme.label2 }
                                MouseArea { id: dm; anchors.fill: parent; hoverEnabled: true; onClicked: root.trash(row.filePath) }
                            }
                        }
                    }
                }
            }

            // ---- main ----
            Item {
                id: main
                anchors.left: side.right; anchors.right: parent.right
                anchors.top: parent.top; anchors.bottom: parent.bottom

                // header: name + status + view controls
                Item {
                    id: head
                    width: parent.width; height: 46
                    // drag the header (anywhere but its controls) to move the window
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.ArrowCursor
                        onPressed: head.Window.window?.startSystemMove()
                    }
                    Row {
                        x: 14; anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        ToolBtn { icon: "side_navigation"; tip: "Sidebar  Ctrl+\\"; on: root.sidebar; onClicked: { root.sidebar = !root.sidebar; state.data = Object.assign({}, state.data, { sidebar: root.sidebar }); state.save(); } }
                        TextInput {
                            id: nameEdit
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(Math.max(80, contentWidth + 4), main.width - 280)
                            text: root.current ? root.base(root.current) : ""
                            color: Theme.label
                            font.family: Theme.fontUi; font.pixelSize: 14; font.weight: Font.DemiBold
                            selectionColor: Theme.rgba(Theme.t.color.accent, 0.4)
                            clip: true
                            onEditingFinished: { root.rename(text); editor.forceActiveFocus(); }
                            Keys.onEscapePressed: { text = root.base(root.current); editor.forceActiveFocus(); }
                        }
                        GText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.status
                            small: true; secondary: true
                        }
                    }
                    Row {
                        anchors.right: parent.right; anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        Rectangle {
                            width: seg.width + 6; height: 30
                            radius: Theme.square ? 5 : 9
                            color: Theme.fill
                            Row {
                                id: seg
                                anchors.centerIn: parent
                                spacing: 2
                                ToolBtn { icon: "edit"; tip: "Rich text"; on: !root.source; onClicked: if (root.source) srcToggle.go() }
                                ToolBtn { icon: "code"; tip: "Markdown source  Ctrl+M"; on: root.source; onClicked: if (!root.source) srcToggle.go() }
                            }
                        }
                        ToolBtn { icon: "close"; tip: "Hide  Esc"; onClicked: root.hide() }
                    }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.sep }
                }
                QtObject {
                    id: srcToggle
                    function go() {
                        if (!root.source) { root.saveNow(); srcEdit.text = editor.text.replace(/\u200b/g, ""); root.source = true; srcEdit.forceActiveFocus(); }
                        else { root.saveNow(); root.loading = true; editor.text = srcEdit.text; root.source = false; Qt.callLater(() => { root.loading = false; editor.textDocument.modified = false; editor.forceActiveFocus(); }); }
                    }
                }

                // toolbar
                Item {
                    id: bar
                    visible: !root.source
                    anchors.top: head.bottom
                    width: parent.width; height: visible ? 42 : 0
                    Row {
                        x: 14; anchors.verticalCenter: parent.verticalCenter
                        spacing: 3
                        ToolBtn { label: "¶"; tip: "Text  Ctrl+0"; on: root.curKind === "p"; onClicked: root.applyBlock("p") }
                        ToolBtn { label: "H1"; tip: "Heading 1  Ctrl+1"; on: root.curKind === "h1"; onClicked: root.applyBlock("h1") }
                        ToolBtn { label: "H2"; tip: "Heading 2  Ctrl+2"; on: root.curKind === "h2"; onClicked: root.applyBlock("h2") }
                        ToolBtn { label: "H3"; tip: "Heading 3  Ctrl+3"; on: root.curKind === "h3"; onClicked: root.applyBlock("h3") }
                        Item { width: 6; height: 1 } Sep {} Item { width: 6; height: 1 }
                        ToolBtn { icon: "format_bold"; tip: "Bold  Ctrl+B"; on: root.curBold; onClicked: root.inline("bold") }
                        ToolBtn { icon: "format_italic"; tip: "Italic  Ctrl+I"; on: root.curItalic; onClicked: root.inline("italic") }
                        ToolBtn { icon: "format_strikethrough"; tip: "Strike  Ctrl+Shift+X"; on: root.curStrike; onClicked: root.inline("strikeout") }
                        ToolBtn { icon: "code"; tip: "Inline code  Ctrl+E"; on: root.curCode; onClicked: root.inline("code") }
                        Item { width: 6; height: 1 } Sep {} Item { width: 6; height: 1 }
                        ToolBtn { icon: "format_list_bulleted"; tip: "Bullets  Ctrl+Shift+8"; on: root.curKind === "bullet"; onClicked: root.applyBlock("bullet") }
                        ToolBtn { icon: "format_list_numbered"; tip: "Numbered  Ctrl+Shift+7"; on: root.curKind === "number"; onClicked: root.applyBlock("number") }
                        ToolBtn { icon: "checklist"; tip: "Checklist  Ctrl+Shift+9"; on: root.curKind === "check"; onClicked: root.applyBlock("check") }
                        ToolBtn { icon: "format_quote"; tip: "Quote  Ctrl+Shift+."; on: root.curKind === "quote"; onClicked: root.applyBlock("quote") }
                        Item { width: 6; height: 1 } Sep {} Item { width: 6; height: 1 }
                        ToolBtn { icon: "link"; tip: "Link  Ctrl+K"; onClicked: linkBox.ask() }
                        ToolBtn { icon: "horizontal_rule"; tip: "Divider"; onClicked: root.divider() }
                    }
                }

                // editor (rich) / source
                Flickable {
                    id: flick
                    visible: !root.source
                    anchors.top: bar.bottom; anchors.bottom: parent.bottom
                    width: parent.width
                    clip: true
                    contentWidth: width
                    contentHeight: editor.implicitHeight + 120
                    boundsBehavior: Flickable.StopAtBounds
                    // keep the caret in view
                    function follow(r) {
                        if (r.y < contentY + 10) contentY = Math.max(0, r.y - 10);
                        else if (r.y + r.height > contentY + height - 30) contentY = r.y + r.height - height + 30;
                    }
                    TextEdit {
                        id: editor
                        readonly property real maxW: 720
                        x: Math.max(28, (flick.width - maxW) / 2)
                        y: 22
                        width: Math.min(maxW, flick.width - 56)
                        textFormat: TextEdit.MarkdownText
                        wrapMode: TextEdit.Wrap
                        selectByMouse: true
                        persistentSelection: true
                        color: Theme.label
                        selectionColor: Theme.rgba(Theme.t.color.accent, 0.35)
                        selectedTextColor: Theme.label
                        font.family: Theme.fontUi
                        font.pixelSize: root.opts.fontSize ?? 15
                        tabStopDistance: 28
                        onCursorRectangleChanged: { flick.follow(cursorRectangle); stateTimer.restart(); root.slashUpdate(); }
                        onTextChanged: {
                            if (root.loading) return;
                            root.status = "Edited";
                            saveTimer.restart();
                            root.slashUpdate();
                        }
                        onLinkActivated: l => Qt.openUrlExternally(l)

                        GText {
                            visible: editor.length === 0 && !editor.preeditText
                            text: "Write markdown… type / for blocks"
                            secondary: true
                            font.pixelSize: editor.font.pixelSize
                        }

                        Keys.onPressed: e => {
                            const ctrl = e.modifiers & Qt.ControlModifier, shift = e.modifiers & Qt.ShiftModifier;
                            // slash menu navigation
                            if (root.slashAt >= 0) {
                                if (e.key === Qt.Key_Down) { root.slashSel = (root.slashSel + 1) % Math.max(1, root.slashItems.length); e.accepted = true; return; }
                                if (e.key === Qt.Key_Up) { root.slashSel = (root.slashSel - 1 + root.slashItems.length) % Math.max(1, root.slashItems.length); e.accepted = true; return; }
                                if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Tab) { root.slashPick(root.slashItems[root.slashSel]); e.accepted = true; return; }
                                if (e.key === Qt.Key_Escape) { root.slashAt = -1; e.accepted = true; return; }
                            }
                            if (e.key === Qt.Key_Slash && !ctrl) {
                                const r = root.blockRange(editor.cursorPosition);
                                if (editor.getText(r[0], r[1]).replace(/\u200b/g, "") === "") { root.slashAt = editor.cursorPosition; root.slashQuery = ""; root.slashSel = 0; }
                                return;     // the "/" itself is typed normally
                            }
                            if (e.key === Qt.Key_Space && !ctrl && root.autoFormat()) { e.accepted = true; return; }
                            if (e.key === Qt.Key_Backspace && !ctrl && !shift && root.backspaceKey()) { e.accepted = true; return; }
                            if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !ctrl && !shift && root.enterKey()) { e.accepted = true; return; }
                            if (!ctrl) return;
                            const k = e.key;
                            if (k === Qt.Key_B) root.inline("bold");
                            else if (k === Qt.Key_I) root.inline("italic");
                            else if (k === Qt.Key_X && shift) root.inline("strikeout");
                            else if (k === Qt.Key_E) root.inline("code");
                            else if (k === Qt.Key_K) linkBox.ask();
                            else if (k === Qt.Key_0) root.applyBlock("p");
                            else if (k === Qt.Key_1 && !shift) root.applyBlock("h1");
                            else if (k === Qt.Key_2 && !shift) root.applyBlock("h2");
                            else if (k === Qt.Key_3 && !shift) root.applyBlock("h3");
                            else if (shift && (k === Qt.Key_8 || k === Qt.Key_Asterisk)) root.applyBlock("bullet");
                            else if (shift && (k === Qt.Key_7 || k === Qt.Key_Ampersand)) root.applyBlock("number");
                            else if (shift && (k === Qt.Key_9 || k === Qt.Key_ParenLeft)) root.applyBlock("check");
                            else if (shift && (k === Qt.Key_Period || k === Qt.Key_Greater)) root.applyBlock("quote");
                            else if (k === Qt.Key_Return || k === Qt.Key_Enter) { if (!root.toggleCheck(editor.cursorPosition)) return; }
                            else if (k === Qt.Key_N) root.newNote();
                            else if (k === Qt.Key_P) { root.sidebar = true; find.forceActiveFocus(); }
                            else if (k === Qt.Key_S) root.saveNow();
                            else if (k === Qt.Key_M) srcToggle.go();
                            else if (k === Qt.Key_Backslash) root.sidebar = !root.sidebar;
                            else return;
                            e.accepted = true;
                        }

                        // click on a checklist box toggles it (the box sits left of the text)
                        TapHandler {
                            acceptedButtons: Qt.LeftButton
                            onTapped: (ev) => {
                                const p = ev.position;
                                const pos = editor.positionAt(p.x, p.y);
                                const r = root.blockRange(pos);
                                const start = editor.positionToRectangle(r[0]);
                                if (p.x < start.x - 2 && p.y >= start.y - 2 && p.y <= start.y + start.height + 2) root.toggleCheck(r[0]);
                            }
                        }

                        // slash menu under the caret
                        Rectangle {
                            id: slash
                            visible: root.slashAt >= 0 && root.slashItems.length > 0
                            z: 20
                            x: Math.min(editor.cursorRectangle.x, editor.width - width)
                            y: editor.cursorRectangle.y + editor.cursorRectangle.height + 6
                            width: 240
                            height: sl.height + 10
                            radius: Theme.square ? 6 : 12
                            color: Theme.cardGlass
                            border.width: 1; border.color: Theme.hair
                            layer.enabled: true
                            layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.6; shadowOpacity: 0.5; shadowVerticalOffset: 6 }
                            Column {
                                id: sl
                                x: 5; y: 5
                                width: parent.width - 10
                                Repeater {
                                    model: root.slashItems
                                    Rectangle {
                                        id: it
                                        required property var modelData
                                        required property int index
                                        width: sl.width; height: 32
                                        radius: Theme.square ? 4 : 8
                                        color: index === root.slashSel ? Theme.fill2 : "transparent"
                                        Glyph { x: 8; anchors.verticalCenter: parent.verticalCenter; name: it.modelData.icon; size: 16; color: it.index === root.slashSel ? Theme.accent : Theme.label2 }
                                        GText { x: 34; anchors.verticalCenter: parent.verticalCenter; text: it.modelData.name }
                                        GText { anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; text: it.modelData.hint; small: true; secondary: true; font.family: Theme.fontMono }
                                        MouseArea { anchors.fill: parent; hoverEnabled: true; onEntered: root.slashSel = it.index; onClicked: root.slashPick(it.modelData) }
                                    }
                                }
                            }
                        }
                    }
                }
                Flickable {
                    id: srcFlick
                    visible: root.source
                    anchors.top: head.bottom; anchors.bottom: parent.bottom
                    width: parent.width
                    clip: true
                    contentHeight: srcEdit.implicitHeight + 80
                    boundsBehavior: Flickable.StopAtBounds
                    TextEdit {
                        id: srcEdit
                        x: Math.max(28, (srcFlick.width - 720) / 2); y: 22
                        width: Math.min(720, srcFlick.width - 56)
                        textFormat: TextEdit.PlainText
                        wrapMode: TextEdit.Wrap
                        selectByMouse: true
                        color: Theme.label
                        selectionColor: Theme.rgba(Theme.t.color.accent, 0.35)
                        font.family: Theme.fontMono; font.pixelSize: 14
                        onTextChanged: if (root.source) { root.status = "Edited"; saveTimer.restart(); }
                        Keys.onPressed: e => {
                            if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_M) { srcToggle.go(); e.accepted = true; }
                            else if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_S) { root.saveNow(); e.accepted = true; }
                        }
                    }
                }

                // link prompt (Ctrl+K): the clipboard's URL is filled in when there is one
                Rectangle {
                    id: linkBox
                    visible: false
                    z: 30
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: head.height + 50
                    width: 420; height: 46
                    radius: Theme.square ? 6 : 12
                    color: Theme.cardGlass
                    border.width: 1; border.color: Theme.hair
                    function ask() { visible = true; linkIn.text = ""; clip.running = true; linkIn.forceActiveFocus(); }
                    Process { id: clip; command: ["wl-paste", "--no-newline", "--type", "text"]; stdout: StdioCollector { onStreamFinished: { const t = text.trim(); if (/^https?:\/\/\S+$/i.test(t) && !linkIn.text) { linkIn.text = t; linkIn.selectAll(); } } } }
                    Glyph { x: 14; anchors.verticalCenter: parent.verticalCenter; name: "link"; size: 16; color: Theme.label2 }
                    TextInput {
                        id: linkIn
                        x: 40; width: parent.width - 54
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.label; font.family: Theme.fontUi; font.pixelSize: 14
                        clip: true
                        selectionColor: Theme.rgba(Theme.t.color.accent, 0.4)
                        Keys.onReturnPressed: { const u = text.trim(); linkBox.visible = false; editor.forceActiveFocus(); if (u) root.insertLink(/^[a-z]+:/i.test(u) ? u : "https://" + u); }
                        Keys.onEscapePressed: { linkBox.visible = false; editor.forceActiveFocus(); }
                        GText { visible: !linkIn.text; text: "Paste or type a link, Enter"; secondary: true; anchors.verticalCenter: parent.verticalCenter }
                    }
                }
            }
        }
    }
}
