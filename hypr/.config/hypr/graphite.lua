-- Graphite: Hyprland 0.55 Lua config ("Sequoia Graphite" desktop).
--
-- NOT auto-loaded under this name. Hyprland picks ~/.config/hypr/hyprland.lua over
-- hyprland.conf, so activation = symlink hyprland.lua -> graphite.lua
-- (`graphite-hypr on`; revert with `graphite-hypr off`).
-- Check without running: Hyprland --verify-config -c ~/.config/hypr/graphite.lua
--
-- Layout
--   graphite/core.lua      helpers (tokens, colors, bind applier)
--   graphite/defaults.lua  token defaults (mirror of ~/.config/graphite/tokens.json)
--   graphite/settings.lua  non-look settings (shell, bind groups, programs)
--   graphite/<module>.lua  one concern each, see MODULES below
--   graphite/binds/*.lua   bind groups (pure data)
--   graphite/shells/*.lua  shell profiles: env + autostart + "shell" bind group + layer rules
--   graphite/local.lua     OPTIONAL machine overrides, applied last (see local.example.lua)
--
-- Every module is `return function(ctx) ... end` and gets the same ctx:
--   ctx.core (helpers) ctx.tokens (merged tokens) ctx.settings ctx.warn(msg)

-- Add / remove / reorder modules here. A module that errors is reported but does
-- not stop the others from loading.
local MODULES = {
    "env",        -- environment variables
    "execs",      -- autostart (exec-once) commands
    "input",      -- input devices, gestures, behaviour options (misc/binds/cursor/dwindle)
    "look",       -- gaps, borders, rounding, shadows, blur, dim (from tokens)
    "animations", -- curves + animation leaves (from tokens.motion)
    "monitors",   -- monitor + workspace rules
    "rules",      -- window rules + layer rules
    "keybinds",   -- bind groups (graphite/binds/*, shells/*)
}

local core = require("graphite.core")

local warnings = {}
local function warn(msg) warnings[#warnings + 1] = msg end

-- local overrides are read first so their `settings`/`tokens` tables shape every
-- module; their `after(ctx)` hook runs last.
local okLocal, overrides = pcall(core.optional_require, "graphite.local")
if not okLocal then
    warn("graphite/local.lua: " .. tostring(overrides))
    overrides = nil
end
if type(overrides) ~= "table" then overrides = {} end

local settings = core.deepmerge(core.deepcopy(require("graphite.settings")), overrides.settings)
local tokens = core.load_tokens()
core.deepmerge(tokens, overrides.tokens)

local ctx = { core = core, tokens = tokens, settings = settings, warn = warn }

for _, name in ipairs(MODULES) do
    if not core.contains(settings.disabled_modules, name) then
        local ok, err = pcall(function()
            local mod = require("graphite." .. name)
            assert(type(mod) == "function", "module must return function(ctx)")
            mod(ctx)
        end)
        if not ok then warn("module '" .. name .. "': " .. tostring(err)) end
    end
end

if type(overrides.after) == "function" then
    local ok, err = pcall(overrides.after, ctx)
    if not ok then warn("graphite/local.lua after(): " .. tostring(err)) end
end

-- Surface collected problems as ONE config error (red banner / verify-config
-- failure) only after everything else has been registered.
if #warnings > 0 then
    error("graphite: " .. table.concat(warnings, "\n  "), 0)
end
