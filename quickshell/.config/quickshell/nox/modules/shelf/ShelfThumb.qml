pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.services

// Thumbnail of one shelf item (mock .dsh-th, 124x72): a real image (Image + sourceSize), the first
// lines of a text / code file, the dropped text, a link card, or the file type's theme icon, with
// the extension tag in the corner.
Rectangle {
    id: root
    required property var item
    property bool missing: false
    property bool showTag: true
    readonly property string kind: item?.kind ?? "file"
    readonly property string ext: Shelf.extOf(item?.name ?? item?.path ?? "")
    readonly property var codeExts: ["md", "txt", "ts", "tsx", "js", "jsx", "mjs", "py", "sh", "bash", "zsh", "fish", "json", "jsonc", "qml", "lua", "conf",
        "cfg", "ini", "toml", "yaml", "yml", "csv", "tsv", "rs", "go", "c", "h", "cpp", "hpp", "java", "kt", "rb", "php", "css", "scss", "html", "xml", "sql", "log", "diff", "patch"]
    readonly property bool code: kind === "file" && codeExts.indexOf(ext) !== -1 && (item?.bytes ?? -1) >= 0 && item.bytes <= 262144 && !missing
    readonly property var extColor: ({ md: "#7aa2ff", sh: "#32D74B", csv: "#30D158", py: "#FFD60A", ts: "#409CFF", js: "#FFD60A", qml: "#41CD52", png: "#FF9F0A",
        jpg: "#FF9F0A", jpeg: "#FF9F0A", webp: "#FF9F0A", gif: "#FF9F0A", pdf: "#FF453A", zip: "#BF5AF2", xz: "#BF5AF2", gz: "#BF5AF2", zst: "#BF5AF2",
        "7z": "#BF5AF2", tar: "#BF5AF2", dmg: "#8e8e93", iso: "#8e8e93", txt: "#aeaeb2", odt: "#409CFF", docx: "#409CFF", json: "#aeaeb2", lua: "#5AA9FF" })

    width: 124; height: 72
    radius: Theme.square ? 2 : 7
    color: Theme.square ? "#050505" : "#0d0d0e"
    clip: true
    border.width: 1
    border.color: Theme.hair

    function iconName() {
        if (kind === "dir") return "folder";
        const map = { pdf: "application-pdf", zip: "application-zip", gz: "application-x-compressed-tar", xz: "application-x-xz-compressed-tar",
            zst: "application-x-zstd-compressed-tar", tar: "application-x-tar", "7z": "application-x-7z-compressed", dmg: "application-x-apple-diskimage",
            iso: "application-x-cd-image", doc: "x-office-document", docx: "x-office-document", odt: "x-office-document", xls: "x-office-spreadsheet",
            xlsx: "x-office-spreadsheet", ods: "x-office-spreadsheet", ppt: "x-office-presentation", pptx: "x-office-presentation", mp3: "audio-x-generic",
            flac: "audio-x-generic", wav: "audio-x-generic", ogg: "audio-x-generic", m4a: "audio-x-generic", mp4: "video-x-generic", mkv: "video-x-generic",
            webm: "video-x-generic", mov: "video-x-generic", deb: "application-x-deb", rpm: "application-x-rpm", exe: "application-x-ms-dos-executable",
            appimage: "application-x-executable", ttf: "font-x-generic", otf: "font-x-generic", woff2: "font-x-generic", html: "text-html", svg: "image-svg+xml" };
        return map[ext] ?? "text-x-generic";
    }
    readonly property string iconPath: (kind === "file" || kind === "dir") && !code
        ? (Quickshell.iconPath(iconName(), true) || Quickshell.iconPath(kind === "dir" ? "inode-directory" : "application-octet-stream", true) || "")
        : ""

    // ---- image ----
    Image {
        anchors.fill: parent
        visible: root.kind === "image"
        source: root.kind === "image" && !root.missing && root.item?.path ? Shelf.fileUrl(root.item.path) : ""
        sourceSize.width: 248
        sourceSize.height: 144
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        mipmap: true
        cache: false
        opacity: status === Image.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.durFade } }
    }

    // ---- first lines of a text / code file (mock .th-code) ----
    FileView {
        id: peek
        path: root.code ? root.item.path : ""
        printErrors: false
        blockLoading: false
    }
    Text {
        visible: root.code
        anchors.fill: parent
        anchors.margins: 8
        anchors.leftMargin: 9
        textFormat: Text.RichText
        font.family: Theme.fontMono
        font.pointSize: 4.8
        lineHeight: 1.45
        color: "#9a9aa0"
        clip: true
        readonly property var lines: root.code && peek.loaded ? peek.text().slice(0, 1600).split("\n").slice(0, 7) : []
        function esc(s) { return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/ /g, "&nbsp;"); }
        text: lines.map((l, i) => i === 0 ? "<b><font color='" + Theme.accent + "'>" + esc(l) + "</font></b>"
            : i % 3 === 2 ? "<font color='#e6e6e8'>" + esc(l) + "</font>" : esc(l)).join("<br>")
    }

    // ---- dropped text (mock .th-txt) ----
    Rectangle {
        visible: root.kind === "text"
        x: 6; y: 9; width: 2; height: parent.height - 18
        radius: Theme.square ? 0 : 1
        color: Theme.accent
    }
    Text {
        visible: root.kind === "text"
        x: 13; y: 8; width: parent.width - 23; height: parent.height - 16
        text: root.item?.text ?? ""
        wrapMode: Text.Wrap
        maximumLineCount: 4
        elide: Text.ElideRight
        font.family: Theme.fontUi
        font.pointSize: 7.125
        lineHeight: 1.12
        color: Theme.label
    }

    // ---- link (mock .th-lnk) ----
    Rectangle {
        visible: root.kind === "link"
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Theme.rgba(Theme.t.color.accent, 0.16) }
            GradientStop { position: 0.65; color: "transparent" }
        }
    }
    Column {
        visible: root.kind === "link"
        x: 10; width: parent.width - 20
        anchors.verticalCenter: parent.verticalCenter
        spacing: 5
        Rectangle {
            width: 18; height: 18
            radius: Theme.square ? 2 : 5
            color: Theme.fill2
            Text {
                anchors.centerIn: parent
                text: (root.item?.host ?? "?").replace(/^www\./, "").charAt(0).toUpperCase()
                font.family: Theme.fontUi; font.pixelSize: 10; font.weight: Font.DemiBold
                color: Theme.label
            }
        }
        Text {
            width: parent.width
            text: root.item?.title || root.item?.host || ""
            elide: Text.ElideRight
            font.family: Theme.fontUi; font.pixelSize: 11; font.weight: Font.DemiBold
            color: Theme.label
        }
        Text {
            width: parent.width
            text: (root.item?.host ?? "") + (root.item?.pathname ?? "")
            elide: Text.ElideRight
            font.family: Theme.fontMono; font.pointSize: 6.375
            font.underline: true
            color: Theme.label3
        }
    }

    // ---- file type icon ----
    Image {
        visible: root.iconPath !== ""
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -2
        width: 44; height: 44
        sourceSize: Qt.size(88, 88)
        source: root.iconPath
        smooth: true
        asynchronous: true
    }

    // extension tag (mock .th-tag)
    Rectangle {
        visible: root.showTag && root.ext !== "" && (root.kind === "file" || root.kind === "image")
        x: 7; y: parent.height - height - 6
        height: 13
        width: tag.implicitWidth + 8
        radius: 2
        color: root.extColor[root.ext] ?? "#8e8e93"
        Text {
            id: tag
            anchors.centerIn: parent
            text: root.ext.toUpperCase()
            font.family: Theme.fontLabel; font.pointSize: 5.625; font.weight: Font.Bold
            font.letterSpacing: 0.4
            color: "#ffffff"
        }
    }
}
