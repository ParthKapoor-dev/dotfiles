-- Monitors + workspace rules.
-- The monitor list is settings.monitors: a generic fallback in nox/settings.lua, this machine's
-- outputs from nox/machine.lua (`nox detect`, git-ignored), hand overrides in nox/local.lua.
-- nwg-displays writes .conf files the Lua config does NOT read: run `nox detect` (it reads the
-- live layout from hyprctl) or edit local.lua instead.

return function(ctx)
    local T, S = ctx.tokens, ctx.settings

    for _, m in ipairs(S.monitors or {}) do hl.monitor(m) end

    hl.workspace_rule({ workspace = "special:special", gaps_out = T.hypr.specialGapsOut })
end
