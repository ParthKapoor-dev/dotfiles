-- Bind group "system": volume/mute, screenshots, color picker, VM submap, test
-- notifications, session, zoom, media. Shell-independent (no qs calls); the
-- qs-dependent bits of these sections live in shells/<shell>.lua.

return function(ctx)
    local C, S = ctx.core, ctx.settings
    local X = hl.dsp.exec_cmd
    local back = (S.bind_submap and S.bind_submap ~= "") and S.bind_submap or "reset"
    local NEXT = [[playerctl next || playerctl position `bc <<< "100 * $(playerctl metadata mpris:length) / 1000000 / 100"`]]

    return {
        -- volume / mute
        { "XF86AudioRaiseVolume", X("wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%+ -l 1.5"), locked = true, repeating = true },
        { "XF86AudioLowerVolume", X("wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-"), locked = true, repeating = true },
        { "XF86AudioMute", X("wpctl set-mute @DEFAULT_SINK@ toggle"), locked = true },
        { "SUPER + SHIFT + M", X("wpctl set-mute @DEFAULT_SINK@ toggle"), locked = true, desc = "Toggle mute" },
        { "ALT + XF86AudioMute", X("wpctl set-mute @DEFAULT_SOURCE@ toggle"), locked = true },
        { "XF86AudioMicMute", X("wpctl set-mute @DEFAULT_SOURCE@ toggle"), locked = true },
        { "SUPER + ALT + M", X("wpctl set-mute @DEFAULT_SOURCE@ toggle"), locked = true, desc = "Toggle mic" },

        -- color picker + full-screen screenshots
        { "SUPER + SHIFT + C", X("hyprpicker -a"), desc = "Color picker" },
        { "Print", X("grim - | wl-copy"), locked = true },
        { "CTRL + Print", X([[mkdir -p $(xdg-user-dir PICTURES)/Screenshots && grim $(xdg-user-dir PICTURES)/Screenshots/Screenshot_"$(date '+%Y-%m-%d_%H.%M.%S')".png]]), locked = true, non_consuming = true },
        { "CTRL + Print", X("grim - | wl-copy"), locked = true, non_consuming = true },

        -- ##! Virtual machines: Super+Alt+F1 toggles a submap with no other binds
        { "SUPER + ALT + F1", C.fn("enter submap virtual-machine", function()
            hl.exec_cmd("notify-send 'Entered Virtual Machine submap' 'Keybinds disabled. Hit Super+Alt+F1 to escape' -a 'Hyprland'")
            hl.dispatch(hl.dsp.submap("virtual-machine"))
        end) },
        { submap = "virtual-machine", binds = {
            { "SUPER + ALT + F1", C.fn("leave submap virtual-machine -> " .. back, function()
                hl.exec_cmd("notify-send 'Exited Virtual Machine submap' 'Keybinds re-enabled' -a 'Hyprland'")
                hl.dispatch(hl.dsp.submap(back))
            end) },
        } },

        -- Testing
        { "SUPER + ALT + F11", X([==[bash -c 'RANDOM_IMAGE=$(find ~/Pictures -type f | grep -v -i "nipple" | grep -v -i "pussy" | shuf -n 1); ACTION=$(notify-send "Test notification with body image" "This notification should contain your user account <b>image</b> and <a href=\"https://discord.com/app\">Discord</a> <b>icon</b>. Oh and here is a random image in your Pictures folder: <img src=\"$RANDOM_IMAGE\" alt=\"Testing image\"/>" -a "Hyprland keybind" -p -h "string:image-path:/var/lib/AccountsService/icons/$USER" -t 6000 -i "discord" -A "openImage=Profile image" -A "action2=Open the random image" -A "action3=Useless button"); [[ $ACTION == *openImage ]] && xdg-open "/var/lib/AccountsService/icons/$USER"; [[ $ACTION == *action2 ]] && xdg-open \"$RANDOM_IMAGE\"']==]) },
        { "SUPER + ALT + F12", X([==[bash -c 'RANDOM_IMAGE=$(find ~/Pictures -type f | grep -v -i "nipple" | grep -v -i "pussy" | shuf -n 1); ACTION=$(notify-send "Test notification" "This notification should contain a random image in your <b>Pictures</b> folder and <a href=\"https://discord.com/app\">Discord</a> <b>icon</b>.\n<i>Flick right to dismiss!</i>" -a "Discord (fake)" -p -h "string:image-path:$RANDOM_IMAGE" -t 6000 -i "discord" -A "openImage=Profile image" -A "action2=Useless button"); [[ $ACTION == *openImage ]] && xdg-open "/var/lib/AccountsService/icons/$USER"']==]) },
        { "SUPER + ALT + Equal", X([[notify-send "Urgent notification" "Ah hell no" -u critical -a 'Hyprland keybind']]) },

        -- ##! Session
        { "SUPER + L", X("loginctl lock-session"), desc = "Lock" },
        { "SUPER + SHIFT + L", X("systemctl suspend || loginctl suspend"), locked = true, desc = "Suspend system" },
        { "CTRL + SHIFT + ALT + SUPER + Delete", X("systemctl poweroff || loginctl poweroff"), desc = "Shutdown" },

        -- ##! Screen: zoom (was zoom.sh -> `hyprctl keyword`, now in-process)
        { "SUPER + Minus", C.zoom_fn(-0.3), repeating = true },
        { "SUPER + Equal", C.zoom_fn(0.3), repeating = true },

        -- ##! Media
        { "SUPER + SHIFT + N", X(NEXT), locked = true },
        { "XF86AudioNext", X(NEXT), locked = true },
        { "XF86AudioPrev", X("playerctl previous"), locked = true },
        { "SUPER + SHIFT + ALT + mouse:275", X("playerctl previous") },
        { "SUPER + SHIFT + ALT + mouse:276", X(NEXT) },
        { "SUPER + SHIFT + B", X("playerctl previous"), locked = true },
        { "SUPER + SHIFT + P", X("playerctl play-pause"), locked = true },
        { "XF86AudioPlay", X("playerctl play-pause"), locked = true },
        { "XF86AudioPause", X("playerctl play-pause"), locked = true },
    }
end
