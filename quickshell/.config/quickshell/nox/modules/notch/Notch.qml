pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.core
import qs.services

// The agent notch's keys and IPC (the pill itself is the bar widget "notch", widgets/NotchPill;
// state in services/AgentNotch; mock lnx/design/mock/agent-notch.html).
// Keys from any window (GlobalShortcuts, appid nox): Super+Y allow · Super+Shift+Y always ·
// Super+BackSpace deny (the oldest request) · Super+O open the notch.
// IPC: qs -c nox ipc call notch toggle | open | close | view <agents|replay|laps|receipts> | status
Scope {
    id: root
    IpcHandler {
        target: "notch"
        function toggle(): void { AgentNotch.toggle(); }
        function open(): void { AgentNotch.show(); }
        function close(): void { AgentNotch.close(); }
        function view(name: string): void { AgentNotch.show(name); }
        function status(): string { return JSON.stringify({ open: AgentNotch.open, mode: AgentNotch.mode, requests: Agents.requests.length, gate: Agents.gateOn }); }
    }
    LazyLoader {
        active: !Quickshell.env("NOX_LINT")
        component: Scope {
            GlobalShortcut { appid: "nox"; name: "notchAllow"; description: "Agent notch: allow the oldest request"
                onPressed: if (AgentNotch.req) Agents.answerReq(AgentNotch.req, "allow"); else Panels.hud("Nothing waiting", "check") }
            GlobalShortcut { appid: "nox"; name: "notchAlways"; description: "Agent notch: always allow the oldest request"
                onPressed: if (AgentNotch.req) Agents.answerReq(AgentNotch.req, "always") }
            GlobalShortcut { appid: "nox"; name: "notchDeny"; description: "Agent notch: deny the oldest request"
                onPressed: if (AgentNotch.req) Agents.answerReq(AgentNotch.req, "deny") }
            GlobalShortcut { appid: "nox"; name: "notchToggle"; description: "Agent notch: open it"
                onPressed: { AgentNotch.laterId = ""; AgentNotch.toggle(); } }
        }
    }
}
