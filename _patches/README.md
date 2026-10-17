# Local patches against upstream

No config patches right now. The end-4 illogical-impulse ("ii") Quickshell
config and its two patches (`quickshell-ii.patch`, `quickshell-ii-lua-dispatch.patch`)
were removed on 2026-10-17 together with ii itself (see git history and
`lnx/reports/remove-ii.md`); the desktop shell is `quickshell/.config/quickshell/nox`.

Quickshell binary: the package is still `illogical-impulse-quickshell-git` (keep it:
it is the patched Quickshell build that `qs -c nox` runs on; currently
0.1.0.r1-8 = Quickshell 0.3.2). The BT sink-removal crash fix lives in that build
(r1-7: pin 6e17efab + upstream 5721955, 13fe9b0).
Recipe: ~/code/sandbox/void/lnx/build/quickshell/. Do NOT reinstall r1-6 from dots-hyprland.
