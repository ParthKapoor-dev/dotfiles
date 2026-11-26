-- Keybinds: applies the bind groups listed in settings.bind_groups, in order.
--   "shell"  -> shells/<settings.shell>.lua  (field `binds`)
--   "<name>" -> binds/<name>.lua
-- Each group file returns `function(ctx) return { ...entries... } end` (pure data;
-- entry format documented in core.apply_binds).

local function load_group(ctx, name)
    local S = ctx.settings
    local src
    if name == "shell" then
        src = require("nox.shells." .. S.shell).binds
    else
        src = require("nox.binds." .. name)
    end
    if type(src) == "function" then src = src(ctx) end
    return src or {}
end

return function(ctx)
    local C, S = ctx.core, ctx.settings

    -- load (file I/O) BEFORE entering define_submap: its callback has a 100 ms budget
    local groups = {}
    for _, name in ipairs(S.bind_groups) do
        local ok, res = pcall(load_group, ctx, name)
        if ok then
            groups[#groups + 1] = res
        else
            ctx.warn("bind group '" .. name .. "': " .. tostring(res))
        end
    end

    -- Super tap = launcher: the shell opens it when Super comes up, unless another key was pressed
    -- meanwhile. Unbound keys reach the shell's catchall; since Hyprland 0.57 a catchall only fires
    -- for keys no other bind matches, so every bound Super combo also sends the interrupt
    -- (non-consuming: the combo's own action still runs, and Binds/cheatsheet skip "Internal:").
    local okShell, shellMod = pcall(require, "nox.shells." .. S.shell)
    local intr = okShell and type(shellMod) == "table" and shellMod.tap_interrupt or nil
    if intr then
        local function is_super_combo(key)
            if type(key) ~= "string" then return false end
            local k = key:upper()
            return k:find("SUPER", 1, true) ~= nil and not k:find("SUPER_[LR]") and not k:find("MOUSE")
                and k ~= "CATCHALL"
        end
        for gi, list in ipairs(groups) do
            local out = {}
            for _, b in ipairs(list) do
                out[#out + 1] = b
                if type(b) == "table" and not b.submap and b.enabled ~= false and b[2] ~= intr and is_super_combo(b[1]) then
                    out[#out + 1] = { b[1], intr, non_consuming = true, desc = "Internal: cancel Super-tap launcher" }
                end
            end
            groups[gi] = out
        end
    end

    local function register(in_submap)
        for _, list in ipairs(groups) do C.apply_binds(list, ctx, in_submap) end
    end

    local submap = S.bind_submap
    if submap and submap ~= "" then
        hl.define_submap(submap, function() register(true) end)
        -- old: `exec = hyprctl dispatch submap global` (ran on every load). The
        -- conf-syntax dispatch no longer parses under Lua, so use the events.
        -- Guard: `config.reloaded` also fires under `Hyprland --verify-config`, where
        -- there is no event manager and dispatching a submap segfaults (0.55.4).
        -- No monitors == not a live compositor (yet); hyprland.start covers startup.
        local function enter()
            local mons = hl.get_monitors()
            if not mons or #mons == 0 then return end
            if hl.get_current_submap() == submap then return end
            hl.dispatch(hl.dsp.submap(submap))
        end
        hl.on("hyprland.start", enter)
        hl.on("config.reloaded", enter)
    else
        register(false)
    end
end
