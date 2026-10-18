pragma Singleton
import QtQuick
import Quickshell

// Launcher provider registry: id (shell.json launcher.providers, in display order) -> file in providers/.
// Add a provider = one QML file + one line here, then put its id in launcher.providers.
//
// Provider contract (duck-typed, an Item loaded by URL, so import qs.* modules explicitly):
//   property string providerId                  set by the launcher
//   readonly property var options: Config.launcherProvider(providerId)
//   property string name                        group header ("Applications")
//   property string defaultPrefix               e.g. "=" (shell.json launcher.provider.<id>.prefix overrides)
//   property bool defaultPrefixOnly             true = only queried when the prefix is typed
//   property bool fallback                      optional: unprefixed results only when the other providers found
//                                               fewer than options.fallbackBelow (default 3) rows; always last
//   function query(text, prefixed) -> [result]  text has the prefix stripped; prefixed = prefix was typed
// result = { title, sub?, type?, icon? (icon-font symbol) | image? (icon path/url) | glyph? (literal character, e.g. an emoji), highlight? ([indices in title]),
//            score? (sort within the group), actLabel? ("Open"), confirm? ("Restart now?" = ask before running),
//            big? ([left, leftLabel, right, rightLabel] = large calculator style row), thumb? (image url = tall row with a preview), thumbSlot? (true = tall row even while thumb is still ""), preview? (image url = large preview beside the list while selected),
//            previewFit? (true = letterbox the preview instead of cropping it to the screen's shape),
//            previewText? (text shown in the preview card when there is no image; a lone colour = swatch, a lone URL = its domain),
//            previewMono? (force / suppress the monospace text preview; default: guessed), previewTitle? / previewTag? (card caption),
//            remove? (function, Shift+Delete), run: function(),
//            stay? (true = Enter runs it and keeps the launcher open: the input resets to the typed prefix and the search re-runs),
//            alt? (function, Shift+Enter: secondary action, closes the launcher; altLabel? = footer hint, default "Alternate"),
//            mark? (function, Ctrl+Enter: toggle membership, the launcher stays open; markLabel? = footer hint, default "Mark"),
//            badge? (short string, e.g. "3" = small numbered pill on the icon/thumbnail),
//            keys? (["Super", "⇧", "S"] = keycaps of the result's shortcut, shown left of the type tag),
//            move? (function(delta) -> false if it couldn't, Alt+Up = -1 / Alt+Down = +1: reorder; the launcher
//                   re-runs the search and keeps the moved row selected, found by key? (stable id) ?? title) }
// Footer hints for alt / mark / move show only while the selected result has them.
// A provider may declare `signal resultsChanged()` (async sources): the launcher re-runs the search.
// Two-level providers: `property bool nested` (true while a sub-level is shown) + `function back()`;
// while its prefix is typed and nested, Esc and Backspace on an empty query call back() (footer: "Back").
// Per-provider shell.json options understood by the launcher itself: enabled, prefix, prefixOnly, limit (0 = all), title.
Singleton {
    readonly property var registry: ({
        "apps": "Apps.qml",
        "calculator": "Calculator.qml",
        "commands": "Commands.qml",
        "windows": "Windows.qml",
        "run": "Run.qml",
        "clipboard": "Clipboard.qml",
        "wallpapers": "Wallpapers.qml",
        "slideshow": "Slideshow.qml",
        "defaults": "DefaultApps.qml",
        "emoji": "Emoji.qml",
        "phone": "Phone.qml",
        "web": "WebSearch.qml",
        "files": "Files.qml",
        "palette": "Palette.qml"
    })
    function url(id) {
        const f = registry[id];
        if (!f) { console.warn("nox: unknown launcher provider id:", id); return ""; }
        return Qt.resolvedUrl("providers/" + f);
    }
}
