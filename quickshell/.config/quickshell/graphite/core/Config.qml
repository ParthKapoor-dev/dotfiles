pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

// User shell config from ~/.config/graphite/shell.json (live reload).
// `defaults` mirrors the shipped shell.json; user values are deep-merged over it
// (arrays replace, objects merge).
Singleton {
    id: root

    readonly property var defaults: ({
        "modules": {
            "bar": true,
            "dock": true,
            "controlCenter": true,
            "launcher": true,
            "osd": true,
            "notifications": false
        },
        "bar": {
            "screens": [],
            "left": [
                "logo",
                "appName",
                "workspaces"
            ],
            "center": [],
            "right": [
                "tray",
                "network",
                "bluetooth",
                "volume",
                "battery",
                "controlCenter",
                "clock"
            ]
        },
        "widgets": {
            "logo": {
                "menu": [
                    {
                        "label": "Lock Screen",
                        "command": [
                            "loginctl",
                            "lock-session"
                        ]
                    },
                    {
                        "separator": true
                    },
                    {
                        "label": "Sleep",
                        "command": [
                            "systemctl",
                            "suspend"
                        ]
                    },
                    {
                        "label": "Restart…",
                        "command": [
                            "systemctl",
                            "reboot"
                        ]
                    },
                    {
                        "label": "Shut Down…",
                        "command": [
                            "systemctl",
                            "poweroff"
                        ]
                    }
                ]
            },
            "appName": {
                "fallback": "Desktop"
            },
            "windowTitle": {
                "maxWidth": 360
            },
            "workspaces": {
                "minCount": 4,
                "scroll": true
            },
            "tray": {
                "monochrome": true
            },
            "network": {
                "settingsCommand": []
            },
            "bluetooth": {
                "settingsCommand": [
                    "blueman-manager"
                ]
            },
            "volume": {
                "step": 0.05
            },
            "battery": {
                "showPercent": "hover",
                "lowPercent": 20
            },
            "clock": {
                "format": "ddd d MMM HH:mm",
                "clickPopup": "notifications"
            }
        },
        "dock": {
            "screens": [],
            "reserveSpace": true,
            "magnify": true,
            "showRunning": true,
            "ignoredAppIds": [],
            "pinned": [
                "zen",
                "slack",
                "claude-desktop",
                "dev.zed.Zed",
                "code-oss",
                "com.mitchellh.ghostty",
                "obsidian",
                "org.kde.dolphin"
            ]
        },
        "controlCenter": {
            "sections": [
                "connectivity",
                "display",
                "sound",
                "media",
                "notifications"
            ],
            "lockCommand": [
                "loginctl",
                "lock-session"
            ]
        },
        "brightness": {
            "device": "auto",
            "step": 5
        },
        "launcher": {
            "width": 680,
            "top": 0.18,
            "maxHeight": 404,
            "placeholder": "Search apps, windows, commands…",
            "providers": ["calculator", "apps", "windows", "commands", "run"],
            "provider": {
                "apps": { "limit": 8, "showRecent": true, "recentLimit": 6, "frecencyWeight": 0.35, "terminal": ["ghostty", "-e"] },
                "calculator": { "prefix": "=" },
                "windows": { "prefix": "@", "limit": 6 },
                "commands": {
                    "prefix": "/",
                    "limit": 6,
                    "items": [
                        { "label": "Lock Screen", "icon": "lock", "command": ["loginctl", "lock-session"], "keywords": ["lock"] },
                        { "label": "Log Out", "icon": "logout", "command": ["hyprctl", "dispatch", "exit"], "confirm": "Log out now?", "keywords": ["logout", "sign out", "exit"] },
                        { "label": "Sleep", "icon": "bedtime", "command": ["systemctl", "suspend"], "confirm": "Sleep now?", "keywords": ["suspend"] },
                        { "label": "Restart", "icon": "restart_alt", "command": ["systemctl", "reboot"], "confirm": "Restart now?", "keywords": ["reboot"] },
                        { "label": "Shut Down", "icon": "power_settings_new", "command": ["systemctl", "poweroff"], "confirm": "Shut down now?", "keywords": ["power off", "poweroff", "halt"] },
                        { "label": "Do Not Disturb", "icon": "do_not_disturb_on", "action": "dnd", "keywords": ["dnd", "focus", "notifications"] },
                        { "label": "Control Center", "icon": "toggle_on", "action": "controlCenter", "keywords": ["settings"] },
                        { "label": "Notification Center", "icon": "notifications", "action": "notifications" },
                        { "label": "Toggle Dock", "icon": "dock_to_bottom", "action": "dock" }
                    ]
                },
                "run": { "prefix": ">", "prefixOnly": true, "shell": ["sh", "-c"], "terminal": ["ghostty", "-e"] }
            }
        },
        "osd": {
            "position": "bottom",
            "offset": 100,
            "width": 236,
            "timeout": 1500,
            "volume": true,
            "brightness": true,
            "mic": true,
            "hideWhilePopupOpen": true
        },
        "notifications": {
            "position": "top-right",
            "width": 344,
            "maxPopups": 4,
            "timeout": { "low": 4000, "normal": 6000, "critical": 0 },
            "respectAppTimeout": true,
            "dndAllowCritical": true,
            "maxHistory": 100,
            "centerMaxHeight": 560,
            "hideUnder": ["notifications", "controlCenter"],
            "rules": []
        }
    })
    property var opt: defaults
    property var raw: ({})      // the file as written by the user (for write-back)
    property bool loaded: false

    function merge(base, over) {
        if (over === null || typeof over !== "object" || Array.isArray(over)) return over === undefined ? base : over;
        const out = Object.assign({}, base);
        for (const k in over) out[k] = (base && typeof base[k] === "object" && !Array.isArray(base[k])) ? merge(base[k], over[k]) : over[k];
        return out;
    }

    // Options for a bar widget id ({} if none).
    function widget(id) { return (opt.widgets && opt.widgets[id]) || ({}); }
    function moduleEnabled(name) { return !!(opt.modules && opt.modules[name]); }
    // Options for a launcher provider id ({} if none).
    function launcherProvider(id) { return (opt.launcher && opt.launcher.provider && opt.launcher.provider[id]) || ({}); }
    // [] or missing = all screens
    function screensFor(list) {
        const all = Quickshell.screens;
        if (!list || list.length === 0) return all;
        return all.filter(s => list.indexOf(s.name) !== -1);
    }

    // Write-back (used by the dock's "Keep in Dock"). Rewrites shell.json as formatted JSON.
    function setDockPinned(list) {
        const r = JSON.parse(JSON.stringify(raw));
        r.dock = r.dock || {};
        r.dock.pinned = list;
        file.setText(JSON.stringify(r, null, 2) + "\n");
    }

    FileView {
        id: file
        path: Paths.shell
        watchChanges: true
        blockLoading: true
        atomicWrites: false  // keep stow symlinks intact
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                root.raw = parsed;
                root.opt = root.merge(root.defaults, parsed);
            } catch (e) { console.warn("graphite: shell.json parse error, keeping previous config:", e); }
            root.loaded = true;
        }
        onLoadFailed: err => { console.info("graphite: shell.json not loaded (" + err + "), using defaults"); root.loaded = true; }
    }
}
