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
//   function query(text, prefixed) -> [result]  text has the prefix stripped; prefixed = prefix was typed
// result = { title, sub?, type?, icon? (icon-font symbol) | image? (icon path/url) | glyph? (literal character, e.g. an emoji), highlight? ([indices in title]),
//            score? (sort within the group), actLabel? ("Open"), confirm? ("Restart now?" = ask before running),
//            big? ([left, leftLabel, right, rightLabel] = large calculator style row), thumb? (image url = tall row with a preview), thumbSlot? (true = tall row even while thumb is still ""),
//            remove? (function, Shift+Delete), run: function() }
// A provider may declare `signal resultsChanged()` (async sources): the launcher re-runs the search.
// Per-provider shell.json options understood by the launcher itself: enabled, prefix, prefixOnly, limit, title.
Singleton {
    readonly property var registry: ({
        "apps": "Apps.qml",
        "calculator": "Calculator.qml",
        "commands": "Commands.qml",
        "windows": "Windows.qml",
        "run": "Run.qml",
        "clipboard": "Clipboard.qml",
        "wallpapers": "Wallpapers.qml",
        "emoji": "Emoji.qml"
    })
    function url(id) {
        const f = registry[id];
        if (!f) { console.warn("nox: unknown launcher provider id:", id); return ""; }
        return Qt.resolvedUrl("providers/" + f);
    }
}
