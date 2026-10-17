# /etc reference copies — NOT stowed

Snapshot (2026-10-17) of system config that the desktop depends on. `setup.sh` skips `_*` dirs.
Restore by hand with `sudo install -Dm644 _etc/<path> /etc/<path>` and review diffs first.

| File | Why it matters |
|---|---|
| bluetooth/main.conf | FastConnectable / AutoEnable for the JBL headset |
| greetd/config.toml | login: tuigreet → start-hyprland on vt1 |
| modprobe.d/nvidia*.conf, blacklist-nouveau.conf | NVIDIA driver setup |
| X11/xorg.conf.d/00-keyboard.conf | keyboard layout for X11/XWayland |
| NetworkManager/NetworkManager.conf | wifi.scan-rand-mac-address=no |
| mkinitcpio.conf, default/grub | boot / initramfs |
| pacman.conf, systemd/journald.conf | package manager + journal limits |

Refresh: re-copy from /etc and commit; `git diff` shows what changed on the system.
