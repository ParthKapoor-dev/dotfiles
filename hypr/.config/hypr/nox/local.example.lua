-- Hand-written machine overrides (`nox detect` writes nox/machine.lua; this file wins over it).
-- Copy to nox/local.lua (it is optional and
-- ignored when missing; it is hot-reloaded like every other module).
--
-- All three fields are optional.
return {
    -- merged over nox/settings.lua BEFORE any module runs
    settings = {
        -- shell = "nox",                       -- swap env + autostart + shell binds
        -- bind_groups = { "shell", "windows", "workspaces", "system", "apps", "custom" },
        -- disabled_modules = { "animations" },
        -- bind_submap = false,                      -- binds in the default submap (no catchall)
        -- monitors = {                              -- replaces nox/machine.lua's list (nox detect)
        --     { output = "", mode = "preferred", position = "auto", scale = "auto" },
        --     { output = "eDP-1", mode = "2560x1600@120", position = "0x0", scale = "1.6" },
        -- },
    },

    -- merged over the tokens (defaults <- ~/.local/state/nox/tokens.lua)
    tokens = {
        -- hypr = { dimInactive = true, blurSpecial = false },
        -- size = { gapsOut = 6 },
    },

    -- runs LAST: direct hl.* calls here override everything above
    after = function(ctx)
        -- hl.config({ misc = { vrr = 0 } })
        -- hl.bind("SUPER + F12", hl.dsp.exec_cmd("notify-send hi"))
        --   (note: binds made here land in the default submap, not settings.bind_submap;
        --    wrap them in hl.define_submap(ctx.settings.bind_submap, function() ... end))
    end,
}
