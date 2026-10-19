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
        { "XF86AudioRaiseVolume", X("wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%+ -l 1.5"), locked = true, repeating = true, desc = "Volume up" },
        { "XF86AudioLowerVolume", X("wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-"), locked = true, repeating = true, desc = "Volume down" },
        { "XF86AudioMute", X("wpctl set-mute @DEFAULT_SINK@ toggle"), locked = true, desc = "Toggle mute" },
        { "SUPER + SHIFT + M", X("wpctl set-mute @DEFAULT_SINK@ toggle"), locked = true, desc = "Toggle mute" },
        { "ALT + XF86AudioMute", X("wpctl set-mute @DEFAULT_SOURCE@ toggle"), locked = true, desc = "Toggle microphone mute" },
        { "XF86AudioMicMute", X("wpctl set-mute @DEFAULT_SOURCE@ toggle"), locked = true, desc = "Toggle microphone mute" },
        { "SUPER + ALT + M", X("wpctl set-mute @DEFAULT_SOURCE@ toggle"), locked = true, desc = "Toggle microphone mute" },

        -- color picker
        { "SUPER + SHIFT + C", X("hyprpicker -a"), desc = "Color picker" },
        -- screenshots (Print, Shift/Alt/Ctrl+Print): nox shot, bound in shells/nox.lua

        -- ##! Virtual machines: Super+Alt+F1 toggles a submap with no other binds
        { "SUPER + ALT + F1", C.fn("enter submap virtual-machine", function()
            hl.exec_cmd("notify-send 'Entered Virtual Machine submap' 'Keybinds disabled. Hit Super+Alt+F1 to escape' -a 'Hyprland'")
            hl.dispatch(hl.dsp.submap("virtual-machine"))
        end), desc = "Enter VM mode (other shortcuts off)" },
        { submap = "virtual-machine", binds = {
            { "SUPER + ALT + F1", C.fn("leave submap virtual-machine -> " .. back, function()
                hl.exec_cmd("notify-send 'Exited Virtual Machine submap' 'Keybinds re-enabled' -a 'Hyprland'")
                hl.dispatch(hl.dsp.submap(back))
            end), desc = "Leave VM mode" },
        } },

        -- Testing
        { "SUPER + ALT + F11", X([==[bash -c 'RANDOM_IMAGE=$(find ~/Pictures -type f | grep -v -i "nipple" | grep -v -i "pussy" | shuf -n 1); ACTION=$(notify-send "Test notification with body image" "This notification should contain your user account <b>image</b> and <a href=\"https://discord.com/app\">Discord</a> <b>icon</b>. Oh and here is a random image in your Pictures folder: <img src=\"$RANDOM_IMAGE\" alt=\"Testing image\"/>" -a "Hyprland keybind" -p -h "string:image-path:/var/lib/AccountsService/icons/$USER" -t 6000 -i "discord" -A "openImage=Profile image" -A "action2=Open the random image" -A "action3=Useless button"); [[ $ACTION == *openImage ]] && xdg-open "/var/lib/AccountsService/icons/$USER"; [[ $ACTION == *action2 ]] && xdg-open \"$RANDOM_IMAGE\"']==]), desc = "Send test notification with image" },
        { "SUPER + ALT + F12", X([==[bash -c 'RANDOM_IMAGE=$(find ~/Pictures -type f | grep -v -i "nipple" | grep -v -i "pussy" | shuf -n 1); ACTION=$(notify-send "Test notification" "This notification should contain a random image in your <b>Pictures</b> folder and <a href=\"https://discord.com/app\">Discord</a> <b>icon</b>.\n<i>Flick right to dismiss!</i>" -a "Discord (fake)" -p -h "string:image-path:$RANDOM_IMAGE" -t 6000 -i "discord" -A "openImage=Profile image" -A "action2=Useless button"); [[ $ACTION == *openImage ]] && xdg-open "/var/lib/AccountsService/icons/$USER"']==]), desc = "Send test notification" },
        { "SUPER + ALT + Equal", X([[notify-send "Urgent notification" "Ah hell no" -u critical -a 'Hyprland keybind']]), desc = "Send test urgent notification" },

        -- ##! Session
        { "SUPER + L", X("loginctl lock-session"), desc = "Lock screen" },
        { "SUPER + SHIFT + L", X("systemctl suspend || loginctl suspend"), locked = true, desc = "Suspend" },
        { "CTRL + SHIFT + ALT + SUPER + Delete", X("systemctl poweroff || loginctl poweroff"), desc = "Shut down" },

        -- ##! Screen: zoom (was zoom.sh -> `hyprctl keyword`, now in-process)
        { "SUPER + Minus", C.zoom_fn(-0.3), repeating = true, desc = "Zoom out" },
        { "SUPER + Equal", C.zoom_fn(0.3), repeating = true, desc = "Zoom in" },

        -- ##! Media
        { "SUPER + SHIFT + N", X(NEXT), locked = true, desc = "Next track" },
        { "XF86AudioNext", X(NEXT), locked = true, desc = "Next track" },
        { "XF86AudioPrev", X("playerctl previous"), locked = true, desc = "Previous track" },
        { "SUPER + SHIFT + ALT + mouse:275", X("playerctl previous"), desc = "Previous track" },
        { "SUPER + SHIFT + ALT + mouse:276", X(NEXT), desc = "Next track" },
        { "SUPER + SHIFT + B", X("playerctl previous"), locked = true, desc = "Previous track" },
        { "SUPER + SHIFT + P", X("playerctl play-pause"), locked = true, desc = "Play / pause" },
        { "XF86AudioPlay", X("playerctl play-pause"), locked = true, desc = "Play / pause" },
        { "XF86AudioPause", X("playerctl play-pause"), locked = true, desc = "Play / pause" },
    }
end
