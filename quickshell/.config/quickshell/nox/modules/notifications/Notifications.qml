import QtQuick
import Quickshell

// Notifications module: popups + Notification Center. The D-Bus server lives in services/Notifs
// and follows the same shell.json switch (modules.notifications).
Scope {
    Popups {}
    NotificationCenter {}
}
