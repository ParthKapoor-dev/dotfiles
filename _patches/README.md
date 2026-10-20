# Local patches against upstream

| Patch | Upstream | Applied by |
|---|---|---|
| `kdeconnect-rs-remote-input.patch` | [cosmic-utils/kdeconnect](https://github.com/cosmic-utils/kdeconnect) at the commit pinned in `nox phone build` | `nox phone build` (clone at the pin, `git apply`, `cargo build --release -p kdeconnect-service`, install to `~/.local/bin`) |

The Remote Input patch adds the phone's remote mouse/keyboard (KDE Connect "Remote input") to
the kdeconnect-rs daemon on Hyprland: virtual pointer + virtual keyboard over Wayland
(wayland-protocols-misc), plus the D-Bus bits nox uses.

No config patches. Quickshell is the official Arch package (`extra/quickshell` 0.3.2); the old
patched `illogical-impulse-quickshell-git` build and the end-4 "ii" config patches are gone
(removed 2026-10-17/18, see git history).
