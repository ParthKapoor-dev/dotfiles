import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd
import Quickshell.Services.UPower
import Quickshell.Networking

// One screen of the greeter. Styles follow the mock's login screen: "ember" (default: thin clock,
// round avatar, pill field), "telemetry" (dot-matrix clock, ID badge with corner brackets, mono
// uppercase) and "sequoia" (classic macOS). The style comes from the look's tokens (name + card).
Item {
    id: g
    property var tokens: ({})
    property var conf: ({})
    property string dataDir: ""
    property bool testMode: false
    property bool showUi: true

    // ---- theme (subset of nox tokens) ----
    readonly property var tc: tokens.color ?? ({})
    readonly property var tf: tokens.font ?? ({})
    readonly property string look: tokens.name ?? "ember"
    readonly property bool tele: look === "telemetry" || (tokens.card?.brackets ?? false)
    readonly property bool seq: look === "sequoia"
    readonly property color accent: tc.accent ?? "#FF5A1F"
    readonly property color onAccent: tc.onAccent ?? "#120402"
    readonly property color page: tc.page ?? "#000000"
    readonly property color red: tele ? accent : "#FF6A5E"
    readonly property color yellow: tc.yellow ?? "#FFC24B"
    readonly property string fUi: tf.ui ?? "Geist"
    readonly property string fDisplay: tf.display ?? fUi
    readonly property string fLabel: tf.label ?? tf.mono ?? fUi
    readonly property string fNum: tf.numeric ?? fDisplay
    readonly property string fIcon: tf.icon ?? "Material Symbols Rounded"
    readonly property var numAxes: tf.numericAxes ?? ({})
    readonly property int easeType: Easing.BezierSpline
    readonly property var curve: (tokens.motion?.sheet ?? [0.2, 0, 0, 1]).concat([1, 1])
    function white(a) { return Qt.rgba(1, 1, 1, a); }
    function up(s) { return tele ? String(s).toUpperCase() : s; }

    // ---- user + sessions (greeter.json) ----
    readonly property string user: conf.user ?? "parth"
    readonly property string realName: conf.name ?? user
    readonly property string initials: realName.split(/\s+/).filter(x => x).slice(0, 2).map(x => x[0].toUpperCase()).join("")
    readonly property var sessions: conf.sessions ?? [
        { name: "Hyprland (nox)", cmd: ["start-hyprland"] },
        { name: "Hyprland (safe mode)", cmd: ["start-hyprland", "--", "--safe-mode"] },
        { name: "TTY shell", cmd: ["/bin/sh", "-c", "exec \"$SHELL\" -l"] }
    ]
    property int sessionIx: 0
    readonly property var session: sessions[Math.min(sessionIx, sessions.length - 1)] ?? sessions[0]

    // ---- login state ----
    // idle | auth | wrong | prompt (extra PAM question) | launching | error
    property string phase: "idle"
    property string message: ""
    property string pending: ""        // the password, until greetd asks for it
    property bool caps: false
    property bool reveal: false
    property bool menuOpen: false
    property string confirm: ""        // "" | "reboot" | "poweroff"
    readonly property bool busy: phase === "auth" || phase === "launching"

    function submit() {
        if (!showUi || busy) return;
        if (phase === "prompt") {            // second PAM question (e.g. a token): answer it directly
            phase = "auth"; message = "";
            Greetd.respond(field.text); field.text = "";
            return;
        }
        if (field.text === "") { shake.restart(); return; }
        pending = field.text;
        retryPw = field.text; retries = 0;
        phase = "auth"; message = "";
        if (testMode && !Greetd.available) { fakeAuth.restart(); return; }
        if (!Greetd.available) { fail("greetd is not available"); return; }
        if (Greetd.state !== GreetdState.Inactive) Greetd.cancelSession();
        Greetd.createSession(user);
    }
    // greetd can refuse the next request while it is still tearing down a failed attempt
    // ("Unable to send message: Connection refused"): retry the same password a few times
    property string retryPw: ""
    property int retries: 0
    Timer {
        id: retryTimer; interval: 500
        onTriggered: {
            if (g.phase !== "auth" || g.retryPw === "") return;
            if (Greetd.state !== GreetdState.Inactive) Greetd.cancelSession();
            g.pending = g.retryPw;
            Greetd.createSession(g.user);
        }
    }
    function wrong(msg) {
        pending = ""; retryPw = ""; field.text = "";
        phase = "wrong"; message = msg || "Incorrect password";
        shake.restart();
        field.forceActiveFocus();
    }
    function fail(msg) { pending = ""; retryPw = ""; phase = "error"; message = msg; field.forceActiveFocus(); }
    function launch() {
        retryPw = "";
        phase = "launching"; message = "";
        saveLast.setText(String(sessionIx) + "\n");
        leave.start();
    }

    Connections {
        target: g.showUi ? Greetd : null
        function onAuthMessage(msg, error, responseRequired, echoResponse) {
            if (responseRequired) {
                if (g.pending !== "") { const p = g.pending; g.pending = ""; Greetd.respond(p); }
                else { g.phase = "prompt"; g.message = msg; g.reveal = echoResponse; g.field.text = ""; g.field.forceActiveFocus(); }
            } else if (error) {
                g.message = msg;
            }
        }
        function onAuthFailure(msg) { g.wrong(""); }   // quickshell cancels the session itself
        function onReadyToLaunch() { g.launch(); }
        function onLaunched() { launchedMark.running = true; }
        function onError(err) {
            console.warn("greeter: greetd error:", err);
            if (g.phase === "auth" && g.retryPw !== "" && g.retries < 3) { g.retries++; retryTimer.restart(); return; }
            if (g.phase === "auth" || g.phase === "launching") g.fail("Login service didn't answer, try again");
        }
    }
    // after the leave animation: ask greetd to start the session, then mark + quit
    // (the launch wrapper sees the marker and exits cleanly instead of falling back to tuigreet)
    function startSession() {
        if (testMode && !Greetd.available) { console.log("greeter-test: launch", JSON.stringify(session.cmd)); Qt.quit(); return; }
        Greetd.launch(session.cmd, [], false);
    }
    Process {
        id: launchedMark
        command: ["sh", "-c", "touch \"${XDG_RUNTIME_DIR:-/tmp}/nox-greeter-launched\""]
        onExited: Qt.quit()
    }
    // demo auth without greetd (`nox greeter test --demo`): "wrong" fails, anything else passes
    Timer { id: fakeAuth; interval: 700; onTriggered: g.pending.includes("wrong") ? g.wrong("") : g.launch() }

    FileView { id: lastFile; path: (Quickshell.env("XDG_STATE_HOME") || "/tmp") + "/nox-greeter-session"; printErrors: false; blockLoading: true
        onLoaded: { const i = parseInt(text()); if (i >= 0 && i < g.sessions.length) g.sessionIx = i; } }
    FileView { id: saveLast; path: lastFile.path; printErrors: false }

    // caps lock: ask the compositor (cheap; only on key presses)
    Process {
        id: capsProc
        command: ["hyprctl", "-j", "devices"]
        stdout: StdioCollector { onStreamFinished: { try { g.caps = JSON.parse(text).keyboards.some(k => k.capsLock); } catch (e) {} } }
    }
    function checkCaps() { if (!capsProc.running) capsProc.running = true; }

    // status
    readonly property var bat: UPower.displayDevice
    readonly property bool hasBat: bat?.isLaptopBattery ?? false
    readonly property int batPct: Math.round((bat?.percentage ?? 0) * 100)
    readonly property bool charging: bat?.state === UPowerDeviceState.Charging || bat?.state === UPowerDeviceState.FullyCharged
    readonly property var wifiDev: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property string ssid: (wifiDev?.networks.values.find(n => n.connected))?.name ?? ""
    property string host: "localhost"
    FileView { path: "/etc/hostname"; blockLoading: true; printErrors: false; onLoaded: g.host = text().trim() || "localhost" }
    property real uptime: 0
    FileView { id: upFile; path: "/proc/uptime"; printErrors: false; onLoaded: g.uptime = parseFloat(text()) || 0 }
    SystemClock { id: clock; precision: g.tele ? SystemClock.Seconds : SystemClock.Minutes; onDateChanged: if (g.tele) upFile.reload() }
    function two(n) { return (n < 10 ? "0" : "") + n; }
    readonly property string upText: { const s = Math.floor(uptime); return two(Math.floor(s / 3600)) + ":" + two(Math.floor(s / 60) % 60) + ":" + two(s % 60); }

    function power(what) {
        if (testMode) { console.log("greeter-test: power", what); confirm = ""; return; }
        powerProc.command = ["systemctl", what];
        powerProc.running = true;
        confirm = "";
    }
    Process { id: powerProc }

    // test hooks (only with NOX_GREETER_TEST): `qs -p <dir> ipc call greeter type|submit|state`
    IpcHandler {
        target: "greeter"
        enabled: g.testMode && g.showUi
        function type(text: string): void { g.field.text = text; }
        function submit(): void { g.submit(); }
        function state(): string { return g.phase + "\t" + g.message; }
        function menu(): void { g.menuOpen = !g.menuOpen; }
        function ask(what: string): void { g.confirm = what; }
        function intro(): string { return g.introMode + "\t" + (g.introOn ? "on" : "off") + "\t" + (g.entered ? "entered" : "waiting"); }
    }

    // fonts that live in the user's home (e.g. Doto) are copied to dataDir/fonts by the sync
    Repeater {
        model: g.showUi ? (g.conf.fonts ?? []) : []
        Item { id: fl; required property string modelData; FontLoader { source: "file://" + g.dataDir + "/fonts/" + fl.modelData } }
    }

    // ==================== visuals ====================
    // wallpaper (pre-processed for the look by `nox greeter sync`)
    Rectangle { anchors.fill: parent; color: g.page }
    Image {
        id: wall
        anchors.fill: parent
        source: "file://" + g.dataDir + "/wallpaper.jpg"
        fillMode: Image.PreserveAspectCrop
        asynchronous: false
        cache: false
        scale: enterAnim.running || g.introOn ? 1.04 : 1
        Behavior on scale { NumberAnimation { duration: 900; easing.type: g.easeType; easing.bezierCurve: g.curve } }
    }
    Rectangle {      // greeter sits a bit darker than the lock screen (no session behind it)
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, g.tele ? 0.34 : 0.06) }
            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, g.tele ? 0.34 : 0.3) }
        }
    }

    Item {
        id: content
        anchors.fill: parent
        visible: g.showUi
        opacity: 0
        transform: Translate { id: contentShift; y: -14 }
        ParallelAnimation {
            id: enterAnim     // started by enter(), after the intro (or right away without one)
            NumberAnimation { target: content; property: "opacity"; to: 1; duration: 420 }
            NumberAnimation { target: contentShift; property: "y"; to: 0; duration: 520; easing.type: g.easeType; easing.bezierCurve: g.curve }
        }
        SequentialAnimation {
            id: leave
            ParallelAnimation {
                NumberAnimation { target: content; property: "opacity"; to: 0; duration: 220 }
                NumberAnimation { target: content; property: "scale"; to: 1.05; duration: 300; easing.type: g.easeType; easing.bezierCurve: g.curve }
                NumberAnimation { target: fadeOut; property: "opacity"; to: 1; duration: 300 }
            }
            ScriptAction { script: g.startSession() }
        }

        MouseArea { anchors.fill: parent; onClicked: { g.menuOpen = false; g.confirm = ""; g.field.forceActiveFocus(); } }

        // ---- status corner ----
        Row {
            anchors { right: parent.right; top: parent.top; rightMargin: 20; topMargin: 14 }
            spacing: g.tele ? 20 : 18
            Status { icon: "laptop_chromebook"; text: g.host }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: kb.implicitWidth + 10; height: 15; radius: g.tele ? 2 : 4
                color: "transparent"; border.width: 1; border.color: g.white(0.4)
                Text { id: kb; anchors.centerIn: parent; text: g.conf.keyboard ?? "EN"; color: g.white(0.82)
                    font { family: g.tele ? g.fLabel : g.fUi; pixelSize: g.tele ? 10 : 10.5; weight: Font.DemiBold; letterSpacing: 0.4 } }
            }
            Status { visible: g.ssid !== ""; icon: "wifi"; text: g.ssid }
            Status { visible: g.hasBat; icon: g.charging ? "battery_charging_full" : g.batPct > 80 ? "battery_full" : g.batPct > 50 ? "battery_5_bar" : g.batPct > 25 ? "battery_3_bar" : "battery_1_bar"; text: g.batPct + "%" }
        }

        // ---- date + clock ----
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: g.seq ? 92 : 96
            spacing: g.tele ? 10 : 2
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: g.seq ? Qt.formatDate(clock.date, "dddd, d MMMM") : Qt.formatDate(clock.date, "dddd, d MMMM").toUpperCase()
                color: "white"
                opacity: g.seq ? 0.85 : g.tele ? 0.7 : 0.75
                font.family: g.seq ? g.fDisplay : g.fLabel
                font.pixelSize: g.seq ? 22 : 13
                font.weight: Font.Medium
                font.letterSpacing: g.seq ? 0 : (g.tele ? 0.26 : 0.22) * 13
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatTime(clock.date, "hh:mm")
                color: "white"
                font.family: g.seq ? g.fDisplay : g.fNum
                font.pixelSize: g.tele ? 148 : 118
                font.weight: g.tele ? Font.Bold : Font.ExtraLight
                font.letterSpacing: g.tele ? 0 : (g.seq ? -0.02 : -0.045) * 118
                font.variableAxes: g.tele ? g.numAxes : ({})
                font.features: { "tnum": 1 }
            }
        }

        // ---- user block ----
        Item {
            id: userBlock
            z: 2           // above the power row: the session menu opens over it
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: g.tele ? 112 : 128
            width: g.tele ? 340 : 300
            height: g.tele ? teleCard.height : plain.height
            transform: Translate { id: shakeX }
            SequentialAnimation {
                id: shake
                NumberAnimation { target: shakeX; property: "x"; to: -10; duration: 60 }
                NumberAnimation { target: shakeX; property: "x"; to: 9; duration: 70 }
                NumberAnimation { target: shakeX; property: "x"; to: -6; duration: 70 }
                NumberAnimation { target: shakeX; property: "x"; to: 4; duration: 70 }
                NumberAnimation { target: shakeX; property: "x"; to: 0; duration: 80 }
            }

            // ember / sequoia
            Column {
                id: plain
                visible: !g.tele
                width: parent.width
                spacing: 10
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 64; height: 64; radius: 32
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: g.seq ? Qt.lighter(g.accent, 1.35) : "#ffa36b" }
                        GradientStop { position: 0.55; color: g.seq ? g.accent : "#ff5a1f" }
                        GradientStop { position: 1; color: g.seq ? Qt.darker(g.accent, 1.5) : "#b8270a" }
                    }
                    Text { anchors.centerIn: parent; visible: avatar.status !== Image.Ready; text: g.initials; color: "white"
                        font { family: g.fDisplay; pixelSize: 26; weight: Font.DemiBold } }
                    Image { id: avatar; anchors.fill: parent; source: g.conf.avatar ? "file://" + g.dataDir + "/avatar.png" : ""; fillMode: Image.PreserveAspectCrop; visible: status === Image.Ready }
                }
                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 1
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: g.realName; color: "white"; font { family: g.fUi; pixelSize: 15; weight: Font.DemiBold } }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: g.user; color: g.white(0.55); font { family: g.fLabel; pixelSize: 12; weight: Font.Medium } }
                }
                Item { width: 1; height: 4 }
                PwField { anchors.horizontalCenter: parent.horizontalCenter; width: 256; active: !g.tele }
                MsgLine { width: parent.width }
                SessionPill { anchors.horizontalCenter: parent.horizontalCenter }
            }

            // telemetry: ID badge
            Rectangle {
                id: teleCard
                visible: g.tele
                width: parent.width
                height: teleCol.implicitHeight + 34
                radius: 8
                color: "#050505"
                border.width: 1; border.color: g.white(0.14)
                Repeater {   // accent corner brackets, 7px outside the card
                    model: 8
                    Rectangle {
                        required property int index
                        readonly property bool horiz: index % 2 === 0
                        readonly property bool atRight: (index >> 1) % 2 === 1
                        readonly property bool atBottom: index >= 4
                        width: horiz ? 14 : 1.5; height: horiz ? 1.5 : 14
                        x: atRight ? teleCard.width + 7 - width : -7
                        y: atBottom ? teleCard.height + 7 - height : -7
                        color: g.accent
                    }
                }
                Column {
                    id: teleCol
                    x: 20; y: 18
                    width: parent.width - 40
                    spacing: 12
                    Item {
                        width: parent.width; height: 12
                        Row {
                            spacing: 7; anchors.verticalCenter: parent.verticalCenter
                            Rectangle { width: 6; height: 6; color: g.accent; anchors.verticalCenter: parent.verticalCenter }
                            Label9 { text: "LOGIN"; color: g.white(0.8) }
                        }
                        Label9 { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: "GREETD · TTY1"; color: g.white(0.45) }
                    }
                    Row {
                        spacing: 14
                        Rectangle {
                            width: 44; height: 44; radius: 4; color: "#111"
                            border.width: 1; border.color: g.white(0.22)
                            Text { anchors.centerIn: parent; text: g.initials; color: "white"
                                font { family: g.fNum; pixelSize: 22; weight: Font.ExtraBold; variableAxes: g.numAxes } }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3
                            Text { text: g.realName.toUpperCase(); color: "white"; font { family: g.fLabel; pixelSize: 18; weight: Font.Medium; letterSpacing: 1.8 } }
                            Text { text: g.user; color: g.white(0.45); font { family: g.fLabel; pixelSize: 11 } }
                        }
                    }
                    Rectangle { width: parent.width; height: 1; color: g.white(0.14) }
                    Grid {
                        columns: 2; columnSpacing: 14; rowSpacing: 8
                        width: parent.width
                        Meta { label: "HOST"; value: g.host.toUpperCase() + " · ARCH" }
                        Meta { label: "UPTIME"; value: g.upText }
                        Meta { label: "KEYBOARD"; value: (g.conf.keyboardLong ?? "EN · US") }
                        Meta { label: "STATUS"; accentValue: true
                            value: g.phase === "auth" ? "AUTH…" : g.phase === "wrong" ? "DENIED" : g.phase === "launching" ? "GRANTED" : "READY" }
                    }
                    Rectangle { width: parent.width; height: 1; color: g.white(0.14) }
                    PwField { width: parent.width; active: g.tele }
                    MsgLine { width: parent.width }
                    SessionPill { width: parent.width }
                }
            }
        }

        // ---- power row ----
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 24
            spacing: 4
            visible: g.confirm === ""
            PowerButton { icon: "bedtime"; text: "Sleep"; onClicked: g.power("suspend") }
            PowerButton { icon: "restart_alt"; text: "Restart"; onClicked: g.confirm = "reboot" }
            PowerButton { icon: "power_settings_new"; text: "Shut down"; onClicked: g.confirm = "poweroff" }
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 21
            visible: g.confirm !== ""
            width: confRow.implicitWidth + 18; height: 36; radius: g.tele ? 4 : 18
            color: g.tele ? "#050505" : Qt.rgba(0, 0, 0, 0.42)
            border.width: 1; border.color: g.white(0.18)
            Row {
                id: confRow
                anchors.verticalCenter: parent.verticalCenter
                x: 14; spacing: 6
                Text { anchors.verticalCenter: parent.verticalCenter; rightPadding: 6; color: g.white(0.85)
                    text: g.up(g.confirm === "reboot" ? "Restart now?" : "Shut down now?")
                    font { family: g.tele ? g.fLabel : g.fUi; pixelSize: g.tele ? 10.5 : 12.5; letterSpacing: g.tele ? 0.8 : 0 } }
                PowerButton { text: "Cancel"; onClicked: g.confirm = "" }
                PowerButton { text: g.confirm === "reboot" ? "Restart" : "Shut down"; primary: true; onClicked: g.power(g.confirm) }
            }
        }
    }

    // ---- intro: a short boot readout before the UI ----
    // greeter.json "intro": true (default) | false. telemetry: typed readout; ember: one accent
    // sweep; sequoia: none. Never in the way: the password field has the focus all along, so any
    // key goes to it and also skips the intro; a click skips it; introCap ends it whatever happens.
    Item {
        id: intro
        anchors.fill: parent
        visible: g.introOn || introFade.running
        Rectangle { anchors.fill: parent; color: "black"; opacity: g.tele ? 0.5 : 0.3 }
        MouseArea { anchors.fill: parent; onPressed: { g.enter(); g.field.forceActiveFocus(); } }

        // telemetry
        Column {
            visible: g.introMode === "tele"
            anchors.centerIn: parent
            width: 300
            spacing: 7
            Text {
                text: g.introType("NOX // " + g.host.toUpperCase(), 0, 0.16)
                color: "white"
                font { family: g.fNum; pixelSize: 30; weight: Font.Bold; variableAxes: g.numAxes; letterSpacing: 1 }
                bottomPadding: 8
            }
            Repeater {
                model: g.introMode === "tele" ? g.introLines : []
                Row {
                    id: il
                    required property var modelData
                    required property int index
                    readonly property real t0: 0.18 + index * 0.14
                    readonly property string head: modelData.k + " " + ".".repeat(Math.max(1, 11 - modelData.k.length)) + " "
                    readonly property bool done: g.introT >= t0 + 0.12
                    Text {
                        text: g.introType(il.head, il.t0, 0.12)
                        color: g.white(0.62)
                        font { family: g.fLabel; pixelSize: 13; weight: Font.Medium; letterSpacing: 1.2 }
                    }
                    Text {
                        visible: il.done
                        text: String(il.modelData.v).toUpperCase()
                        color: il.modelData.ok ? g.accent : "white"
                        font { family: g.fLabel; pixelSize: 13; weight: Font.DemiBold; letterSpacing: 1.2 }
                    }
                    Rectangle {     // block cursor on the line being typed
                        visible: g.introT >= il.t0 && !il.done
                        anchors.verticalCenter: parent.verticalCenter
                        width: 7; height: 13; color: g.accent
                    }
                }
            }
            Item { width: 1; height: 6 }
            Rectangle {     // boot progress
                width: parent.width; height: 2; color: g.white(0.12)
                Rectangle { width: parent.width * Math.min(1, g.introT / 0.86); height: 2; color: g.accent }
            }
        }

        // ember: one accent line sweeping out from the centre, the name fading in above it
        Item {
            visible: g.introMode === "ember"
            anchors.centerIn: parent
            width: 320; height: 40
            readonly property real e: 1 - Math.pow(1 - Math.min(1, g.introT / 0.8), 3)
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 4
                text: "NOX"
                color: "white"
                opacity: 0.7 * parent.e
                font { family: g.fLabel; pixelSize: 11; weight: Font.Medium; letterSpacing: 0.4 * 11 + 4 * (1 - parent.e) }
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 28
                width: parent.width * parent.e; height: 1.5
                color: g.accent
                opacity: 1 - 0.6 * Math.max(0, (g.introT - 0.7) / 0.3)
            }
        }
        NumberAnimation { id: introFade; target: intro; property: "opacity"; to: 0; duration: 180 }
    }
    readonly property string introKind: {
        if (!showUi || conf.intro === false || conf.intro === "off") return "";
        return tele ? "tele" : seq ? "" : "ember";
    }
    readonly property var introLines: [
        { k: "SYS", v: "OK", ok: true },
        { k: "NET", v: ssid !== "" ? ssid : Networking.devices.values.some(d => d.type === DeviceType.Wired && d.connected) ? "WIRED" : "OFFLINE", ok: false },
        { k: "PWR", v: hasBat ? batPct + "%" + (charging ? " AC" : "") : "AC", ok: false },
        { k: "USER", v: user, ok: false }
    ]
    property string introMode: ""      // introKind, latched when the intro starts
    property bool introStarted: false
    property bool introOn: false
    property bool entered: false
    // theme.json / greeter.json land a moment after this item is created: start once both are
    // in, or after dataWait without them (the UI then comes in as before, no intro)
    readonly property bool dataReady: Object.keys(tokens).length > 0 && Object.keys(conf).length > 0
    onDataReadyChanged: startIntro(false)
    Timer { id: dataWait; interval: 250; running: true; onTriggered: g.startIntro(true) }
    property real introT: 0
    function introType(s, t0, len) { return s.substring(0, Math.ceil(s.length * Math.max(0, Math.min(1, (introT - t0) / len)))); }
    NumberAnimation { id: introAnim; target: g; property: "introT"; from: 0; to: 1; duration: g.introMode === "tele" ? 900 : 560; onFinished: g.enter() }
    Timer { id: introCap; interval: 1200; onTriggered: g.enter() }
    function startIntro(force) {
        if (introStarted || entered || (!dataReady && !force)) return;
        introStarted = true;
        dataWait.stop();
        try {
            introMode = dataReady ? introKind : "";
            if (introMode === "") { enter(); return; }
            introOn = true;
            introAnim.start();
            introCap.start();
        } catch (e) { console.warn("greeter: intro failed", e); enter(); }
    }
    // the normal UI comes in (once): after the intro, on a key / click, or right away
    function enter() {
        if (entered) return;
        entered = true;
        introAnim.stop(); introCap.stop();
        if (introOn) { introOn = false; introFade.start(); }
        enterAnim.start();
    }

    // black veil for the hand-off to the session
    Rectangle { id: fadeOut; anchors.fill: parent; color: "black"; opacity: 0 }

    // typing anywhere goes to the field (it keeps the keyboard focus)
    property alias field: field

    // ==================== components ====================
    component Label9: Text {
        color: g.white(0.45)
        font { family: g.fLabel; pixelSize: 10; weight: Font.Medium; letterSpacing: 1.3 }
    }
    component Status: Row {
        property string icon
        property string text
        spacing: 6
        Text { anchors.verticalCenter: parent.verticalCenter; text: parent.icon; color: g.white(0.82)
            font { family: g.fIcon; pixelSize: 16 } }
        Text { anchors.verticalCenter: parent.verticalCenter; text: g.up(parent.text); color: g.white(0.82)
            font { family: g.tele ? g.fLabel : g.fUi; pixelSize: g.tele ? 11 : 12.5; weight: Font.Medium; letterSpacing: g.tele ? 0.9 : 0; features: { "tnum": 1 } } }
    }
    component Meta: Column {
        property string label
        property string value
        property bool accentValue: false
        width: (teleCol.width - 14) / 2
        spacing: 2
        Text { text: parent.label; color: g.white(0.4); font { family: g.fLabel; pixelSize: 10; weight: Font.Medium; letterSpacing: 0.9 } }
        Text { text: parent.value; color: parent.accentValue ? g.accent : "white"
            font { family: g.fLabel; pixelSize: 11; weight: parent.accentValue ? Font.DemiBold : Font.Medium; letterSpacing: 0.9 } }
    }
    component MsgLine: Text {
        height: 16
        elide: Text.ElideRight
        horizontalAlignment: g.tele ? Text.AlignLeft : Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: g.up(g.message !== "" ? g.message : g.caps ? "Caps Lock is on" : "")
        color: g.phase === "wrong" || g.phase === "error" ? g.red : g.caps && g.message === "" ? g.yellow : g.white(0.6)
        font { family: g.tele ? g.fLabel : g.fUi; pixelSize: g.tele ? 10 : 12; letterSpacing: g.tele ? 0.8 : 0 }
    }
    component PowerButton: Rectangle {
        id: pb
        property string icon: ""
        property string text: ""
        property bool primary: false
        signal clicked()
        height: g.confirm !== "" ? 28 : 30
        width: pbRow.implicitWidth + (icon ? 22 : 24)
        radius: g.tele ? 3 : height / 2
        color: primary ? g.accent : pbMouse.containsMouse ? g.white(0.1) : "transparent"
        Behavior on color { ColorAnimation { duration: 100 } }
        Row {
            id: pbRow
            anchors.centerIn: parent
            spacing: 7
            Text { visible: pb.icon !== ""; anchors.verticalCenter: parent.verticalCenter; text: pb.icon
                color: pbMouse.containsMouse ? "white" : g.white(0.55); font { family: g.fIcon; pixelSize: 15 } }
            Text { anchors.verticalCenter: parent.verticalCenter; text: g.up(pb.text)
                color: pb.primary ? g.onAccent : pbMouse.containsMouse ? "white" : g.white(pb.icon ? 0.55 : 0.8)
                font { family: g.tele ? g.fLabel : g.fUi; pixelSize: g.tele ? 10.5 : 12; weight: pb.primary ? Font.DemiBold : Font.Normal; letterSpacing: g.tele ? 0.8 : 0 } }
        }
        MouseArea { id: pbMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pb.clicked() }
    }
    component SessionPill: Item {
        id: sp
        height: g.tele ? 30 : 26
        implicitWidth: g.tele ? 300 : spRow.implicitWidth + 19
        z: 5
        Rectangle {
            anchors.fill: parent
            radius: g.tele ? 4 : height / 2
            color: g.tele ? (spMouse.containsMouse || g.menuOpen ? "#121212" : "#0b0b0b") : (spMouse.containsMouse || g.menuOpen ? g.white(0.14) : g.white(0.08))
            border.width: g.tele ? 1 : 0.5; border.color: g.white(g.tele ? 0.14 : 0.16)
        }
        Row {
            id: spRow
            x: g.tele ? 10 : 9
            anchors.verticalCenter: parent.verticalCenter
            spacing: g.tele ? 8 : 6
            Text { visible: !g.tele; anchors.verticalCenter: parent.verticalCenter; text: "desktop_windows"; color: g.white(0.72); font { family: g.fIcon; pixelSize: 13 } }
            Text { visible: g.tele; width: 62; anchors.verticalCenter: parent.verticalCenter; text: "SESSION"; color: g.white(0.4); font { family: g.fLabel; pixelSize: 10; letterSpacing: 1 } }
            Text { anchors.verticalCenter: parent.verticalCenter; text: g.up(g.session.name); color: g.white(g.tele ? 0.88 : 0.72)
                font { family: g.tele ? g.fLabel : g.fUi; pixelSize: g.tele ? 11 : 12; weight: Font.Medium; letterSpacing: g.tele ? 0.7 : 0 } }
            Text { visible: !g.tele; anchors.verticalCenter: parent.verticalCenter; text: "expand_more"; color: g.white(0.5); font { family: g.fIcon; pixelSize: 13 } }
        }
        Text { visible: g.tele; anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
            text: "expand_more"; color: g.white(0.5); font { family: g.fIcon; pixelSize: 14 } }
        MouseArea { id: spMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: g.menuOpen = !g.menuOpen }

        Rectangle {
            visible: g.menuOpen
            y: parent.height + 6
            x: g.tele ? 0 : (parent.width - width) / 2
            width: g.tele ? parent.width : 224
            height: menuCol.implicitHeight + 10
            radius: g.tele ? 4 : 10
            color: g.tele ? "#070707" : Qt.rgba(0.11, 0.11, 0.12, 0.96)
            border.width: 1; border.color: g.white(0.12)
            Column {
                id: menuCol
                x: 5; y: 5; width: parent.width - 10
                Repeater {
                    model: g.sessions
                    Rectangle {
                        required property var modelData
                        required property int index
                        width: menuCol.width; height: 30
                        radius: g.tele ? 3 : 6
                        color: miMouse.containsMouse ? g.accent : "transparent"
                        Text { x: 10; anchors.verticalCenter: parent.verticalCenter; text: g.up(parent.modelData.name)
                            color: miMouse.containsMouse ? g.onAccent : "white"
                            font { family: g.tele ? g.fLabel : g.fUi; pixelSize: g.tele ? 11 : 13; letterSpacing: g.tele ? 0.7 : 0 } }
                        Text { anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                            visible: parent.index === g.sessionIx; text: "check"
                            color: miMouse.containsMouse ? g.onAccent : "white"; font { family: g.fIcon; pixelSize: 14 } }
                        MouseArea { id: miMouse; anchors.fill: parent; hoverEnabled: true
                            onClicked: { g.sessionIx = parent.index; g.menuOpen = false; g.field.forceActiveFocus(); } }
                    }
                }
            }
        }
    }
    component PwField: Rectangle {
        height: g.tele ? 36 : 34
        radius: g.tele ? 4 : height / 2
        color: g.tele ? "#0c0c0c" : g.white(0.18)
        border.width: g.phase === "wrong" ? 1 : (g.tele ? 1 : 0)
        border.color: g.phase === "wrong" ? g.red : g.white(0.22)
        Text {   // placeholder
            x: g.tele ? 12 : 14
            anchors.verticalCenter: parent.verticalCenter
            visible: field.text === "" && !field.preedit
            text: g.phase === "prompt" ? g.up(g.message || "Response") : g.phase === "auth" ? g.up("Checking…") : g.up("Password")
            color: g.white(0.6)
            font { family: g.tele ? g.fLabel : g.fUi; pixelSize: 13; letterSpacing: g.tele ? 0.5 : 0 }
        }
        // only the field of the current style holds the real input
        property bool active: false
        function claim() { if (active) field.parent = fieldSlot; }
        onActiveChanged: claim()
        Component.onCompleted: claim()
        Item {
            id: fieldSlot
            anchors { left: parent.left; right: tools.left; top: parent.top; bottom: parent.bottom; leftMargin: g.tele ? 12 : 14; rightMargin: 4 }
        }
        Row {
            id: tools
            anchors.right: parent.right; anchors.rightMargin: g.tele ? 4 : 5
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Text { visible: g.caps; width: 24; height: 24; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                text: "keyboard_capslock"; color: g.yellow; font { family: g.fIcon; pixelSize: 15 } }
            Item {
                visible: field.text !== ""
                width: 24; height: 24
                Text { anchors.centerIn: parent; text: g.reveal ? "visibility_off" : "visibility"; color: eyeMouse.containsMouse || g.reveal ? "white" : g.white(0.55)
                    font { family: g.fIcon; pixelSize: 15 } }
                MouseArea { id: eyeMouse; anchors.fill: parent; hoverEnabled: true; onClicked: { g.reveal = !g.reveal; field.forceActiveFocus(); } }
            }
            Rectangle {
                width: g.tele ? 28 : 24; height: width
                radius: g.tele ? 3 : width / 2
                color: g.tele ? g.accent : g.white(0.2)
                opacity: field.text === "" && !g.busy ? 0.45 : 1
                Text { anchors.centerIn: parent; visible: !g.busy; text: "arrow_forward"; color: g.tele ? g.onAccent : "white"; font { family: g.fIcon; pixelSize: 15 } }
                Rectangle {   // spinner while greetd checks
                    anchors.centerIn: parent
                    visible: g.busy
                    width: 12; height: 12; radius: 6
                    color: "transparent"; border.width: 2; border.color: g.tele ? g.onAccent : "white"
                    Rectangle { width: 6; height: 6; color: parent.parent.color; anchors.right: parent.right; anchors.top: parent.top }
                    RotationAnimation on rotation { running: g.busy; from: 0; to: 360; duration: 800; loops: Animation.Infinite }
                }
                MouseArea { anchors.fill: parent; onClicked: g.submit() }
            }
        }
    }

    // the one real input (re-parented into the visible field of the current style)
    TextInput {
        id: field
        parent: g
        anchors.fill: parent ? parent : undefined
        verticalAlignment: TextInput.AlignVCenter
        clip: true
        focus: g.showUi
        enabled: !g.busy
        echoMode: g.reveal ? TextInput.Normal : TextInput.Password
        passwordCharacter: "•"
        color: "white"
        selectionColor: g.accent
        selectedTextColor: g.onAccent
        font.family: g.tele ? g.fLabel : g.fUi
        font.pixelSize: 13
        font.letterSpacing: g.reveal ? 0 : (g.tele ? 3 : 2)
        cursorDelegate: Rectangle { width: 1.5; color: g.accent; visible: field.activeFocus
            SequentialAnimation on opacity { loops: Animation.Infinite; NumberAnimation { to: 0; duration: 530 } NumberAnimation { to: 1; duration: 530 } } }
        onTextChanged: { if (!g.entered) g.enter(); if (g.phase === "wrong" || g.phase === "error") { g.phase = "idle"; g.message = ""; } }
        Keys.onPressed: e => {
            if (!g.entered) g.enter();      // skip the intro; the key itself still goes to the field
            g.checkCaps();
            if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { g.submit(); e.accepted = true; }
            else if (e.key === Qt.Key_Escape) { if (g.menuOpen || g.confirm !== "") { g.menuOpen = false; g.confirm = ""; } else text = ""; e.accepted = true; }
        }
    }
    Component.onCompleted: { checkCaps(); field.forceActiveFocus(); startIntro(false); }
}
