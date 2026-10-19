pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

// User shell config from ~/.config/nox/shell.json (live reload).
// `defaults` mirrors the shipped shell.json; user values are deep-merged over it
// (arrays replace, objects merge).
Singleton {
    id: root

    // generated from nox/.config/nox/shell.json (keep in sync)
    readonly property var defaults: ({
        "modules": {
            "bar": true,
            "dock": true,
            "controlCenter": true,
            "launcher": true,
            "osd": true,
            "notifications": true,
            "wallpaper": true,
            "corners": true,
            "overview": true,
            "session": true,
            "polkit": true,
            "clipboard": true,
            "cheatsheet": true
        },
        "terminal": [
            "ghostty"
        ],
        "bar": {
            "screens": [],
            "left": [
                "logo",
                "appName",
                "menus",
                "workspaces",
                "layout"
            ],
            "center": [],
            "right": [
                "recording",
                "dnd",
                "tray",
                "stats",
                "network",
                "bluetooth",
                "battery",
                "search",
                "controlCenter",
                "clock"
            ]
        },
        "widgets": {
            "logo": {
                "menu": [
                    {
                        "label": "About This Desktop",
                        "action": "about"
                    },
                    {
                        "separator": true
                    },
                    {
                        "label": "Mission Control",
                        "action": "overview"
                    },
                    {
                        "label": "Force Quit Front App",
                        "action": "forceQuit"
                    },
                    {
                        "separator": true
                    },
                    {
                        "label": "Sleep",
                        "action": "sleep"
                    },
                    {
                        "label": "Restart…",
                        "action": "session"
                    },
                    {
                        "label": "Shut Down…",
                        "action": "session"
                    },
                    {
                        "separator": true
                    },
                    {
                        "label": "Lock Screen",
                        "action": "lock"
                    },
                    {
                        "label": "Log Out $USER…",
                        "action": "session"
                    }
                ]
            },
            "appName": {
                "fallback": "Desktop",
                "maxWidth": 180
            },
            "menus": {
                "items": [
                    "File",
                    "Edit",
                    "View",
                    "Window",
                    "Help"
                ]
            },
            "windowTitle": {
                "maxWidth": 360
            },
            "workspaces": {
                "minCount": 5,
                "scroll": true
            },
            "layout": {
                "showLabel": "hover"
            },
            "tray": {
                "mode": "popup",
                "monochrome": true
            },
            "network": {
                "settingsCommand": [
                    "ghostty",
                    "-e",
                    "nmtui"
                ],
                "maxOther": 8
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
            "stats": {
                "show": [
                    "cpu",
                    "mem"
                ],
                "hot": 0.85,
                "topCount": 5,
                "monitorCommand": [
                    "ghostty",
                    "-e",
                    "btop"
                ]
            },
            "clock": {
                "format": "ddd d MMM HH:mm",
                "clickPopup": "notifications"
            }
        },
        "dock": {
            "screens": [],
            "autohide": true,
            "reserveSpace": true,
            "magnify": true,
            "showRunning": true,
            "stacks": [
                "downloads",
                "trash"
            ],
            "iconScale": {},
            "ignoredAppIds": [],
            "pinned": [
                "zen",
                "slack",
                "dev.zed.Zed",
                "stably-orca",
                "netsoft-com.netsoft.hubstaff",
                "chromium",
                "helium",
                "com.mitchellh.ghostty"
            ]
        },
        "controlCenter": {
            "sections": [
                "connectivity",
                "performance",
                "display",
                "sound",
                "media",
                "tiles"
            ],
            "tiles": [
                "screenshot",
                "record",
                "look",
                "lock"
            ],
            "looks": [
                "default",
                "telemetry"
            ]
        },
        "session": {
            "items": [
                "lock",
                "logout",
                "sleep",
                "restart",
                "poweroff"
            ],
            "confirm": [
                "logout",
                "restart",
                "poweroff"
            ],
            "commands": {}
        },
        "screenshot": {
            "card": {
                "enabled": true,
                "timeout": 8000,
                "position": "bottom-right",
                "width": 300,
                "actions": [
                    "save",
                    "folder",
                    "annotate",
                    "copy",
                    "pin",
                    "phone",
                    "upload",
                    "delete"
                ]
            },
            "upload": {
                "service": "0x0",
                "expires": 24,
                "confirm": true
            }
        },
        "recorder": {
            "directory": "~/Videos",
            "args": []
        },
        "nightLight": {
            "temperature": 4500
        },
        "stats": {
            "interval": 2000,
            "thermalZone": "auto"
        },
        "brightness": {
            "device": "auto",
            "step": 5
        },
        "wallpaper": {
            "path": "",
            "fill": "cover",
            "color": "#000000",
            "transition": 500,
            "slideshowMinutes": 15
        },
        "overview": {
            "minWorkspaces": 5,
            "live": true
        },
        "corners": {
            "hideOnFullscreen": true
        },
        "desktopWidgets": {
            "enabled": true,
            "side": "auto",
            "screens": [],
            "show": [
                "date",
                "clock",
                "media",
                "quote"
            ],
            "timeFormat": "HH:mm",
            "dateFormat": "dddd d MMMM",
            "clockSize": 132,
            "width": 440,
            "marginX": 96,
            "offsetY": -24,
            "quoteWidth": 360,
            "alwaysShow": false,
            "quotes": [
                "Less, but better. — Dieter Rams",
                "Simplicity is prerequisite for reliability. — Edsger Dijkstra",
                "Make it work, make it right, make it fast. — Kent Beck",
                "The details are not the details. They make the design. — Charles Eames",
                "Stay hungry. Stay foolish."
            ]
        },
        "cheatsheet": {
            "labels": {},
            "groups": {},
            "showUnlabeled": false
        },
        "launcher": {
            "width": 680,
            "top": 0.18,
            "maxHeight": 404,
            "placeholder": "Search apps, files, commands…",
            "providers": [
                "calculator",
                "apps",
                "windows",
                "pins",
                "clipboard",
                "wallpapers",
                "commands",
                "run"
            ],
            "provider": {
                "apps": {
                    "limit": 8,
                    "showRecent": true,
                    "recentLimit": 6,
                    "frecencyWeight": 0.35,
                    "terminal": [
                        "ghostty",
                        "-e"
                    ]
                },
                "calculator": {
                    "prefix": "="
                },
                "windows": {
                    "prefix": "@",
                    "limit": 6
                },
                "clipboard": {
                    "prefix": ":",
                    "prefixOnly": true,
                    "limit": 60
                },
                "wallpapers": {
                    "prefix": "#",
                    "prefixOnly": true,
                    "limit": 30,
                    "directory": "~/Pictures",
                    "skipScreenshots": true
                },
                "commands": {
                    "prefix": "/",
                    "limit": 6,
                    "items": [
                        {
                            "label": "Lock Screen",
                            "icon": "lock",
                            "action": "lock",
                            "keywords": [
                                "lock"
                            ]
                        },
                        {
                            "label": "Log Out",
                            "icon": "logout",
                            "action": "logout",
                            "confirm": "Log out now?",
                            "keywords": [
                                "logout",
                                "sign out",
                                "exit"
                            ]
                        },
                        {
                            "label": "Sleep",
                            "icon": "moon",
                            "action": "sleep",
                            "confirm": "Sleep now?",
                            "keywords": [
                                "suspend"
                            ]
                        },
                        {
                            "label": "Restart",
                            "icon": "restart",
                            "action": "restart",
                            "confirm": "Restart now?",
                            "keywords": [
                                "reboot"
                            ]
                        },
                        {
                            "label": "Shut Down",
                            "icon": "power",
                            "action": "poweroff",
                            "confirm": "Shut down now?",
                            "keywords": [
                                "power off",
                                "poweroff",
                                "halt"
                            ]
                        },
                        {
                            "label": "Toggle Do Not Disturb",
                            "icon": "moonF",
                            "action": "dnd",
                            "keywords": [
                                "dnd",
                                "focus",
                                "notifications"
                            ]
                        },
                        {
                            "label": "Toggle Night Light",
                            "icon": "sunset",
                            "action": "nightLight",
                            "keywords": [
                                "night",
                                "warm",
                                "hyprsunset"
                            ]
                        },
                        {
                            "label": "Toggle Caffeine",
                            "icon": "coffee",
                            "action": "caffeine",
                            "keywords": [
                                "awake",
                                "idle",
                                "inhibit"
                            ]
                        },
                        {
                            "label": "Battery Protection (80% / Full Charge)",
                            "icon": "leaf",
                            "action": "chargeLimit",
                            "keywords": [
                                "battery",
                                "charge",
                                "limit",
                                "80",
                                "100",
                                "travel",
                                "health"
                            ]
                        },
                        {
                            "label": "Take Screenshot",
                            "icon": "shot",
                            "action": "screenshot",
                            "keywords": [
                                "screenshot",
                                "capture",
                                "grim"
                            ]
                        },
                        {
                            "label": "Record Screen",
                            "icon": "record",
                            "action": "record",
                            "keywords": [
                                "record",
                                "video",
                                "wf-recorder"
                            ]
                        },
                        {
                            "label": "Mission Control",
                            "icon": "grid",
                            "action": "overview",
                            "keywords": [
                                "overview",
                                "expose",
                                "workspaces"
                            ]
                        },
                        {
                            "label": "Clipboard History",
                            "icon": "clip",
                            "action": "clipboard",
                            "keywords": [
                                "clipboard",
                                "paste",
                                "cliphist"
                            ]
                        },
                        {
                            "label": "Choose Wallpaper",
                            "icon": "image",
                            "action": "wallpapers",
                            "keywords": [
                                "wallpaper",
                                "background",
                                "picture"
                            ]
                        },
                        {
                            "label": "Next Layout",
                            "icon": "layout",
                            "action": "layoutNext",
                            "keywords": [
                                "layout",
                                "tiling",
                                "scrolling",
                                "master"
                            ]
                        },
                        {
                            "label": "Control Center",
                            "icon": "cc",
                            "action": "controlCenter",
                            "keywords": [
                                "settings"
                            ]
                        },
                        {
                            "label": "Notification Center",
                            "icon": "bell",
                            "action": "notifications"
                        },
                        {
                            "label": "Power Menu",
                            "icon": "power",
                            "action": "session",
                            "keywords": [
                                "session",
                                "logout",
                                "shutdown"
                            ]
                        },
                        {
                            "label": "Toggle Dock",
                            "icon": "grid",
                            "action": "dock"
                        },
                        {
                            "label": "Desktop Widgets: On / Off",
                            "icon": "desktop",
                            "action": "desktopWidgets",
                            "keywords": [
                                "widgets",
                                "clock",
                                "desktop",
                                "quote"
                            ]
                        },
                        {
                            "label": "Widgets: Left",
                            "icon": "desktop",
                            "action": "widgetsLeft",
                            "keywords": [
                                "widgets",
                                "side",
                                "clock"
                            ]
                        },
                        {
                            "label": "Widgets: Right",
                            "icon": "desktop",
                            "action": "widgetsRight",
                            "keywords": [
                                "widgets",
                                "side",
                                "clock"
                            ]
                        },
                        {
                            "label": "Widgets: Auto Side",
                            "icon": "desktop",
                            "action": "widgetsAuto",
                            "keywords": [
                                "widgets",
                                "side",
                                "clock",
                                "wallpaper"
                            ]
                        }
                    ]
                },
                "run": {
                    "prefix": ">",
                    "prefixOnly": true,
                    "shell": [
                        "sh",
                        "-c"
                    ],
                    "terminal": [
                        "ghostty",
                        "-e"
                    ]
                }
            }
        },
        "osd": {
            "position": "bottom",
            "offset": 96,
            "width": 236,
            "timeout": 1300,
            "volume": true,
            "brightness": true,
            "mic": true,
            "hideWhilePopupOpen": true
        },
        "notifications": {
            "position": "top-right",
            "width": 344,
            "maxPopups": 3,
            "timeout": {
                "low": 4000,
                "normal": 5200,
                "critical": 0
            },
            "respectAppTimeout": true,
            "dndAllowCritical": true,
            "maxHistory": 100,
            "hideUnder": [
                "notifications",
                "controlCenter"
            ],
            "center": {
                "width": 356,
                "calendar": true,
                "batteries": true
            },
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
    // one dock option (the command palette's "Dock auto-hide" toggle). A scalar that is already in
    // the file's "dock" object is replaced in place, so the hand formatting survives; otherwise the
    // same rewrite as above
    function setDockOption(key, value) {
        const t = file.text();
        const at = t.search(/\n\s*"dock"\s*:\s*\{/);
        if (at >= 0 && typeof value !== "object") {
            const end = t.indexOf("\n  }", at + 1);
            const body = t.slice(at, end < 0 ? t.length : end);
            const re = new RegExp('("' + key + '"\\s*:\\s*)(true|false|-?[\\d.]+|"[^"]*")');
            if (re.test(body)) {
                file.setText(t.slice(0, at) + body.replace(re, "$1" + JSON.stringify(value)) + t.slice(at + body.length));
                return;
            }
        }
        const r = JSON.parse(JSON.stringify(raw));
        r.dock = r.dock || {};
        r.dock[key] = value;
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
            } catch (e) { console.warn("nox: shell.json parse error, keeping previous config:", e); }
            root.loaded = true;
        }
        onLoadFailed: err => { console.info("nox: shell.json not loaded (" + err + "), using defaults"); root.loaded = true; }
    }
}
