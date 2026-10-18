import QtQuick
import Quickshell
import qs.core

// Web search in the default browser (xdg-open). Prefix "?": "? rust lifetimes" searches the default
// engine, a leading engine key picks another ("? yt lofi", "? aw hyprland", "? aur quickshell"),
// and the other engines are listed under it with their keys. An empty "?" lists the engines (Enter =
// their home page). Text that looks like a URL or domain ("archlinux.org/news", "localhost:5173")
// also offers "Open <url>".
// Unprefixed it is a fallback provider: "Search the web for …" (and "Open …") only when the other
// providers found fewer than fallbackBelow rows, always last.
// options: default (engine key, "g"), engines ({ key: { name, url with %s } } merged over the
// built-ins below; null removes one), opener (argv prefix, ["xdg-open"]), fallbackBelow (0 = never).
Item {
    id: root
    property string providerId: "web"
    readonly property var options: Config.launcherProvider(providerId)
    property string name: "Web"
    property string defaultPrefix: "?"
    property bool defaultPrefixOnly: false
    property bool fallback: true

    readonly property var builtin: ({
        "g":   { name: "Google", url: "https://www.google.com/search?q=%s" },
        "d":   { name: "DuckDuckGo", url: "https://duckduckgo.com/?q=%s" },
        "yt":  { name: "YouTube", url: "https://www.youtube.com/results?search_query=%s" },
        "gh":  { name: "GitHub", url: "https://github.com/search?q=%s&type=repositories" },
        "aw":  { name: "Arch Wiki", url: "https://wiki.archlinux.org/index.php?search=%s" },
        "aur": { name: "AUR", url: "https://aur.archlinux.org/packages?K=%s" },
        "ap":  { name: "Arch Packages", url: "https://archlinux.org/packages/?q=%s" },
        "r":   { name: "Reddit", url: "https://www.reddit.com/search/?q=%s" },
        "w":   { name: "Wikipedia", url: "https://en.wikipedia.org/w/index.php?search=%s" },
        "npm": { name: "npm", url: "https://www.npmjs.com/search?q=%s" },
        "mdn": { name: "MDN", url: "https://developer.mozilla.org/en-US/search?q=%s" }
    })
    // key -> { key, name, url }, built-ins first, then shell.json additions in their order
    readonly property var engines: {
        const out = {};
        const add = (k, e) => { if (e === null) delete out[k]; else if (e?.url) out[k] = { key: k, name: e.name ?? k, url: e.url }; };
        for (const k in builtin) add(k, builtin[k]);
        const user = options.engines ?? {};
        for (const k in user) add(k, user[k]);
        return out;
    }
    readonly property var defaultEngine: engines[options["default"] ?? "g"] ?? engines["g"] ?? Object.values(engines)[0] ?? null

    function open(url) { Quickshell.execDetached((options.opener ?? ["xdg-open"]).concat([url])); }
    function searchUrl(e, q) { return e.url.replace(/%s/g, encodeURIComponent(q)); }
    function home(e) { return (e.url.match(/^https?:\/\/[^\/?#]+/) ?? [e.url])[0]; }

    // "https://…" / "www.…" / "localhost:3000" / an IP / "name.tld[/path]" with a known TLD -> URL, else ""
    readonly property var tlds: ["com", "org", "net", "io", "dev", "app", "ai", "co", "me", "gg", "sh", "xyz", "info", "edu", "gov",
        "uk", "de", "in", "us", "ca", "fr", "jp", "nl", "eu", "ch", "au", "se", "no", "fi", "es", "it", "pl", "ru", "br", "tv",
        "fm", "so", "to", "ly", "is", "page", "site", "blog", "wiki", "news", "tech", "cloud", "run", "build", "zone", "social"]
    function urlOf(t) {
        if (/\s/.test(t) || !t) return "";
        if (/^[a-z][a-z0-9+.-]*:\/\/\S+$/i.test(t)) return t;
        if (/^(localhost|\d{1,3}(\.\d{1,3}){3})(:\d+)?(\/\S*)?$/i.test(t)) return "http://" + t;
        const m = t.match(/^(?:www\.)?(?:[a-z0-9-]+\.)+([a-z]{2,})(:\d+)?([\/?#]\S*)?$/i);
        return m && (tlds.includes(m[1].toLowerCase()) || /^www\./i.test(t)) ? "https://" + t : "";
    }

    function row(title, sub, icon, score, url) {
        return { title, sub, icon, type: "Web", actLabel: "Open", score, key: url, run: () => root.open(url) };
    }

    function query(text, prefixed) {
        const t = text.trim();
        const out = [];
        if (!engines || !defaultEngine) return out;
        if (!t) {
            // "?" alone: the engines and their keys
            if (prefixed) Object.values(engines).forEach((e, i) =>
                out.push(row(e.name, e.key + " …", "globe", e === defaultEngine ? 1000 : -i, home(e))));
            return out;
        }
        const url = urlOf(t);
        if (url) out.push(row("Open " + url.replace(/^https?:\/\//, ""), url, "link", 200, url));
        if (!prefixed) {
            out.push(row("Search the web for “" + t + "”", defaultEngine.name, "search", 100, searchUrl(defaultEngine, t)));
            return out;
        }
        // leading engine key: "yt lofi"
        const sp = t.indexOf(" ");
        const picked = sp > 0 ? engines[t.slice(0, sp).toLowerCase()] : null;
        const q = picked ? t.slice(sp + 1).trim() : t;
        const main = picked ?? defaultEngine;
        out.push(row("Search " + main.name + " for “" + q + "”", main.key + " …", "search", 100, searchUrl(main, q)));
        if (picked) return out;
        Object.values(engines).forEach((e, i) => {
            if (e !== main) out.push(row("Search " + e.name + " for “" + q + "”", e.key + " …", "globe", -i, searchUrl(e, q)));
        });
        return out;
    }
}
