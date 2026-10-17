# Local patches against upstream

`quickshell-ii.patch`: diff of `quickshell/.config/quickshell/ii` vs end-4/dots-hyprland
commit `1dcf90ac` (`dots/.config/quickshell/ii`). Local changes:

- `GlobalStates.qml` / `modules/ii/overview/Overview.qml`: Super-key guard
- `services/Idle.qml`: idle inhibitor defaults on
- `modules/ii/bar/LeftSidebarButton.qml`: only reference Ai/Booru singletons when policies.ai/weeb are on, so the AI + booru services never start when disabled (2026-10-17)

When syncing to a newer upstream ii, copy the new tree in and re-apply this patch.

Quickshell binary: crash on Bluetooth sink removal is fixed by the patched package
`illogical-impulse-quickshell-git 0.1.0.r1-7` (pin 6e17efab + upstream 5721955, 13fe9b0).
Recipe: ~/code/sandbox/void/lnx/build/quickshell/. Do NOT reinstall r1-6 from dots-hyprland.
