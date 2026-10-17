-- Nox: Hyprland 0.55 Lua config ("Sequoia" desktop).
--
-- NOT auto-loaded under this name: Hyprland loads ~/.config/hypr/hyprland.lua, a
-- symlink to this file (tracked in the dotfiles repo; `nox hypr on` recreates
-- it). There is no hyprland.conf fallback any more (removed with ii, 2026-10-17).
-- Check without running: Hyprland --verify-config -c ~/.config/hypr/nox.lua
--
-- Layout
--   nox/core.lua      helpers (tokens, colors, bind applier)
--   nox/defaults.lua  token defaults (mirror of ~/.config/nox/tokens.json)
--   nox/settings.lua  non-look settings (shell, bind groups, programs)
--   nox/<module>.lua  one concern each, see MODULES below
--   nox/binds/*.lua   bind groups (pure data)
--   nox/shells/*.lua  shell profiles: env + autostart + "shell" bind group + layer rules
--   nox/local.lua     OPTIONAL machine overrides, applied last (see local.example.lua)
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
    "keybinds",   -- bind groups (nox/binds/*, shells/*)
}

local core = require("nox.core")

local warnings = {}
local function warn(msg) warnings[#warnings + 1] = msg end

-- local overrides are read first so their `settings`/`tokens` tables shape every
-- module; their `after(ctx)` hook runs last.
local okLocal, overrides = pcall(core.optional_require, "nox.local")
if not okLocal then
    warn("nox/local.lua: " .. tostring(overrides))
    overrides = nil
end
if type(overrides) ~= "table" then overrides = {} end

local settings = core.deepmerge(core.deepcopy(require("nox.settings")), overrides.settings)
local tokens = core.load_tokens()
core.deepmerge(tokens, overrides.tokens)

local ctx = { core = core, tokens = tokens, settings = settings, warn = warn }

for _, name in ipairs(MODULES) do
    if not core.contains(settings.disabled_modules, name) then
        local ok, err = pcall(function()
            local mod = require("nox." .. name)
            assert(type(mod) == "function", "module must return function(ctx)")
            mod(ctx)
        end)
        if not ok then warn("module '" .. name .. "': " .. tostring(err)) end
    end
end

if type(overrides.after) == "function" then
    local ok, err = pcall(overrides.after, ctx)
    if not ok then warn("nox/local.lua after(): " .. tostring(err)) end
end

-- Surface collected problems as ONE config error (red banner / verify-config
-- failure) only after everything else has been registered.
if #warnings > 0 then
    error("nox: " .. table.concat(warnings, "\n  "), 0)
end
