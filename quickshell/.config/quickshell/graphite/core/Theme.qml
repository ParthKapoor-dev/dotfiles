pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

// Design tokens, live-reloaded. Source order:
//   1. $XDG_STATE_HOME/graphite/tokens.json  (merged base + preset, written by `graphite-theme switch <look>`)
//   2. ~/.config/graphite/tokens.json        (base tokens, if the merged file is missing/broken)
//   3. `fallback` below                       (mirrors the base tokens.json minus _comment keys; also fills missing keys)
// Never rename keys here without renaming them in tokens.json (other tools read the same file).
Singleton {
    id: root

    readonly property var fallback: ({
        "name": "ember",
        "color": {
            "page": "#000000",
            "bg": "#11100F",
            "surface": "#1B1A19",
            "raised": "#282624",
            "glass": "#0E0D0C",
            "label": "#FFFFFF",
            "labelAlpha": 0.88,
            "label2Alpha": 0.56,
            "label3Alpha": 0.28,
            "sepAlpha": 0.08,
            "rimAlpha": 0.12,
            "hairAlpha": 0.09,
            "fillAlpha": 0.07,
            "fill2Alpha": 0.12,
            "fill3Alpha": 0.18,
            "accent": "#FF5A1F",
            "onAccent": "#140803",
            "green": "#30D158",
            "orange": "#FF9F0A",
            "red": "#FF453A",
            "yellow": "#FFD60A",
            "teal": "#64D2FF",
            "blue": "#0A84FF",
            "purple": "#BF5AF2",
            "pink": "#FF375F",
            "trafficClose": "#FF5F57",
            "trafficMin": "#FEBC2E",
            "trafficZoom": "#28C840",
            "trafficOff": "#3A3836",
            "signal2": "#64D2FF",
            "accentGlow": "#FF5418"
        },
        "terminal": {
            "background": "#0E0E0E",
            "foreground": "#E8E4E0",
            "cursor": "#FF5A1F",
            "selection": "#2A1D17",
            "black": "#1A1A1A",
            "red": "#FF5543",
            "green": "#A6D96A",
            "yellow": "#FFB547",
            "blue": "#7AA7FF",
            "magenta": "#E58CC5",
            "cyan": "#6FD3C7",
            "white": "#D6D2CE",
            "brightBlack": "#5C5855",
            "brightRed": "#FF7A6B",
            "brightGreen": "#BDE68A",
            "brightYellow": "#FFCB75",
            "brightBlue": "#9CBEFF",
            "brightMagenta": "#F0AEDA",
            "brightCyan": "#94E3D9",
            "brightWhite": "#FFFFFF"
        },
        "glass": {
            "alpha": 0.78,
            "menubarAlpha": 0.72,
            "launcherAlpha": 0.92,
            "blurSize": 6,
            "blurPasses": 2,
            "saturation": 1.2
        },
        "radius": {
            "window": 12,
            "menu": 10,
            "control": 6,
            "panel": 16,
            "launcher": 14
        },
        "size": {
            "menubar": 30,
            "dock": 52,
            "dockMagnify": 1.5,
            "gapsIn": 5,
            "gapsOut": 10,
            "border": 1,
            "rim": 0.5
        },
        "font": {
            "ui": "Geist",
            "display": "Geist",
            "mono": "Geist Mono",
            "icon": "Material Symbols Rounded",
            "size": 13,
            "sizeSmall": 11,
            "monoSize": 12.5,
            "iconSize": 17,
            "sizeLarge": 22,
            "sizeHero": 28,
            "uiPt": 11,
            "smallPt": 9,
            "monoPt": 10,
            "numericAxes": {},
            "label": "Geist Mono",
            "labelCase": "upper",
            "labelTracking": 0.08,
            "numeric": "Geist",
            "numericWeight": 200
        },
        "motion": {
            "ease": [
                0.25,
                0.1,
                0.25,
                1.0
            ],
            "sheet": [
                0.32,
                0.72,
                0.0,
                1.0
            ],
            "snap": [
                0.2,
                0.9,
                0.1,
                1.0
            ],
            "pop": 130,
            "fade": 220,
            "window": 380,
            "sheetMs": 320,
            "workspace": 460
        },
        "shadow": {
            "focused": {
                "range": 44,
                "power": 3,
                "color": "#000000",
                "alpha": 0.72,
                "offsetY": 14
            },
            "unfocused": {
                "range": 22,
                "power": 3,
                "color": "#000000",
                "alpha": 0.4,
                "offsetY": 6
            }
        },
        "theme": {
            "icons": "WhiteSur-dark",
            "cursor": "macOS",
            "cursorSize": 24,
            "gtk": "adw-gtk3-dark",
            "gnomeAccent": "orange"
        },
        "ui": {
            "selection": "neutral",
            "sectionLabels": "mono-upper",
            "meter": "bar",
            "focusDecor": "none",
            "dockIcons": "color",
            "workspaceStyle": "dots"
        },
        "desktop": {
            "wallpaper": "ember-glow",
            "dotGrid": {
                "enabled": false,
                "spacing": 24,
                "size": 1.3,
                "alpha": 0.09,
                "majorEvery": 8
            },
            "widgets": false
        },
        "card": {
            "style": "flat",
            "notch": false,
            "brackets": false
        }
    })

    function merge(base, over) {
        if (over === null || typeof over !== "object" || Array.isArray(over)) return over === undefined ? base : over;
        const out = Object.assign({}, base);
        for (const k in over) out[k] = (base && typeof base[k] === "object" && !Array.isArray(base[k])) ? merge(base[k], over[k]) : over[k];
        return out;
    }

    // "#RRGGBB" + alpha -> color
    function rgba(hex, a) {
        const h = String(hex).replace("#", "");
        return Qt.rgba(parseInt(h.substr(0, 2), 16) / 255, parseInt(h.substr(2, 2), 16) / 255, parseInt(h.substr(4, 2), 16) / 255, a === undefined ? 1 : a);
    }
    function white(a) { return rgba(t.color.label, a); }

    property var merged: null     // parsed state file (preset applied)
    property var base: null       // parsed ~/.config/graphite/tokens.json
    property var t: merge(fallback, merged ?? base ?? {})

    FileView {
        path: Paths.mergedTokens
        watchChanges: true
        blockLoading: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { root.merged = JSON.parse(text()); }
            catch (e) { console.warn("graphite: merged tokens unreadable, using base tokens.json:", e); root.merged = null; }
        }
        onLoadFailed: root.merged = null
    }
    FileView {
        path: Paths.tokens
        watchChanges: true
        blockLoading: true
        onFileChanged: reload()
        onLoaded: {
            try { root.base = JSON.parse(text()); }
            catch (e) { console.warn("graphite: tokens.json parse error, keeping previous tokens:", e); }
        }
        onLoadFailed: err => console.info("graphite: tokens.json not loaded (" + err + "), using built-in fallback")
    }

    // ---- colors ----
    readonly property color page: rgba(t.color.page)
    readonly property color bg: rgba(t.color.bg)
    readonly property color surface: rgba(t.color.surface)
    readonly property color raised: rgba(t.color.raised)
    readonly property color label: rgba(t.color.label, t.color.labelAlpha)
    readonly property color label2: rgba(t.color.label, t.color.label2Alpha)
    readonly property color label3: rgba(t.color.label, t.color.label3Alpha)
    readonly property color sep: rgba(t.color.label, t.color.sepAlpha)
    readonly property color hair: rgba(t.color.label, t.color.hairAlpha)
    readonly property color rim: rgba(t.color.label, t.color.rimAlpha)
    readonly property color fill: rgba(t.color.label, t.color.fillAlpha)
    readonly property color fill2: rgba(t.color.label, t.color.fill2Alpha)
    readonly property color fill3: rgba(t.color.label, t.color.fill3Alpha)
    readonly property color accent: rgba(t.color.accent)
    readonly property color onAccent: rgba(t.color.onAccent)
    readonly property color green: rgba(t.color.green)
    readonly property color orange: rgba(t.color.orange)
    readonly property color red: rgba(t.color.red)
    readonly property color yellow: rgba(t.color.yellow)
    readonly property color glass: rgba(t.color.glass, t.glass.alpha)
    readonly property color menubarGlass: rgba(t.color.glass, t.glass.menubarAlpha)
    readonly property color launcherGlass: rgba(t.color.glass, t.glass.launcherAlpha)
    readonly property color shadow: rgba(t.shadow.focused.color, t.shadow.focused.alpha)
    // glass.alpha >= 1 = opaque surfaces (Telemetry): no translucent rim, hairline edge instead
    readonly property bool glassOpaque: t.glass.alpha >= 1

    // ---- metrics ----
    readonly property int barHeight: t.size.menubar
    readonly property int dockSize: t.size.dock
    readonly property real dockMagnify: t.size.dockMagnify
    readonly property real rimWidth: t.size.rim
    readonly property int gapsOut: t.size.gapsOut
    readonly property int radiusWindow: t.radius.window
    readonly property int radiusMenu: t.radius.menu
    readonly property int radiusControl: t.radius.control
    readonly property int radiusPanel: t.radius.panel
    readonly property int radiusLauncher: t.radius.launcher

    // ---- type ----
    readonly property string fontUi: t.font.ui
    readonly property string fontDisplay: t.font.display
    readonly property string fontMono: t.font.mono
    readonly property string fontIcon: t.font.icon
    readonly property real fontSize: t.font.size
    readonly property real fontSizeSmall: t.font.sizeSmall
    readonly property real iconSize: t.font.iconSize
    readonly property real fontSizeLarge: t.font.sizeLarge
    readonly property real fontSizeHero: t.font.sizeHero

    // ---- section labels (ui.sectionLabels: "plain" | "mono-upper") ----
    readonly property bool labelsMono: (t.ui?.sectionLabels ?? "plain") === "mono-upper"
    readonly property string fontLabel: t.font.label ?? t.font.mono
    readonly property real labelTracking: t.font.labelTracking ?? 0.08   // em
    // ---- numerals (big numbers: OSD, calculator) ----
    readonly property string fontNumeric: t.font.numeric ?? t.font.display
    readonly property int numericWeight: t.font.numericAxes?.wght ?? t.font.numericWeight ?? 500
    readonly property var numericAxes: t.font.numericAxes ?? ({})

    // ---- style switches (tokens "ui" / "card") ----
    readonly property string workspaceStyle: t.ui?.workspaceStyle ?? "dots"      // dots | numbers
    readonly property string meter: t.ui?.meter ?? "bar"                          // bar | dot-matrix
    readonly property bool dotMatrix: meter === "dot-matrix"
    readonly property string dockIcons: t.ui?.dockIcons ?? "color"                // color | monochrome-until-running
    readonly property string selection: t.ui?.selection ?? "accent"               // accent | neutral
    readonly property bool selectionNeutral: selection === "neutral"
    readonly property string cardStyle: t.card?.style ?? "flat"                   // flat | hairline
    readonly property bool cardBrackets: t.card?.brackets ?? false

    // ---- motion (QML BezierSpline wants [x1,y1,x2,y2,1,1]) ----
    readonly property var curveEase: t.motion.ease.concat([1, 1])
    readonly property var curveSheet: t.motion.sheet.concat([1, 1])
    readonly property var curveSnap: t.motion.snap.concat([1, 1])
    readonly property int durPop: t.motion.pop
    readonly property int durFade: t.motion.fade
    readonly property int durSheet: t.motion.sheetMs
    readonly property int durWindow: t.motion.window
}
