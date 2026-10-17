-- Monitors + workspace rules. Port of the old monitors.conf / workspaces.conf
-- (removed 2026-10-17; nwg-displays writes .conf files the Lua config does NOT
-- read - update this table by hand after using it) and the
-- `workspace = special:special` rule from the old rules.conf.

return function(ctx)
    local T = ctx.tokens

    local monitors = {
        -- fallback for anything else that gets plugged in
        { output = "", mode = "preferred", position = "auto", scale = "auto" },
        { output = "HDMI-A-1", mode = "1920x1080@60", position = "0x0", scale = "1" },
        { output = "eDP-1", mode = "1920x1080@144", position = "1920x0", scale = "1.25" },
    }
    for _, m in ipairs(monitors) do hl.monitor(m) end

    hl.workspace_rule({ workspace = "special:special", gaps_out = T.hypr.specialGapsOut })
end
