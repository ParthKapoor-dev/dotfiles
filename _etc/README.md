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

### Boot speed (2026-10-18)
| File | Why it matters |
|---|---|
| default/grub | menu hidden, 1 s (Esc after the ASUS logo shows it), `GRUB_TOP_LEVEL` keeps linux-lts default |
| mkinitcpio-lts.conf | linux-lts image only (preset `default_config`): no `kms` hook, so no nouveau + ~107 MB nouveau firmware (219 -> 103 MB) |
| modprobe.d/nvidia-modeset.conf | `fbdev=1` (was the typo `fbdev-1`) |

**This machine's GRUB reads `/boot/efi/grub/grub.cfg`** (EFI/BOOT/BOOTX64.EFI, prefix `(,gpt1)/grub`),
not `/boot/grub/grub.cfg`: regenerate with `grub-mkconfig -o /boot/efi/grub/grub.cfg` (or both).
Boot went 24.5 s -> 16.1 s (`systemd-analyze`).
