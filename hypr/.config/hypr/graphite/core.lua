-- Graphite Hyprland config: shared helpers.
--
-- Pure helpers + the context object every module receives. Nothing in here touches
-- the compositor at require time; only functions called by modules do.

local C = {}

C.HOME = os.getenv("HOME") or ""

-- Lua functions used as bind actions get a human label here so tools/binddump.lua
-- can print what a function bind does (hyprctl only shows "__lua <ref>").
C.labels = setmetatable({}, { __mode = "k" })

function C.fn(label, f)
    C.labels[f] = label
    return f
end

---------------------------------------------------------------------------
-- tables
---------------------------------------------------------------------------

local function is_array(t)
    return type(t) == "table" and t[1] ~= nil
end

function C.deepcopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = C.deepcopy(x) end
    return out
end

-- Merge `src` into `dst` (in place). Maps merge recursively; arrays and scalars
-- from `src` replace the value in `dst` wholesale.
function C.deepmerge(dst, src)
    if type(src) ~= "table" then return dst end
    for k, v in pairs(src) do
        if type(v) == "table" and not is_array(v) and type(dst[k]) == "table" and not is_array(dst[k]) then
            C.deepmerge(dst[k], v)
        else
            dst[k] = C.deepcopy(v)
        end
    end
    return dst
end

function C.contains(list, x)
    for _, v in ipairs(list or {}) do
        if v == x then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- optional modules (tokens.lua, local.lua)
---------------------------------------------------------------------------

-- require() a module that may legitimately be absent. Hyprland's require wrapper
-- turns syntax/runtime errors of a FOUND module into a visible config error and
-- returns {} - so here we only need to swallow "not found".
-- Using require (not dofile) means Hyprland watches the file and auto-reloads.
function C.optional_require(name)
    local ok, res = pcall(require, name)
    if ok then return res end
    if type(res) == "string" and res:find("module '" .. name .. "' not found", 1, true) then
        return nil
    end
    error(res, 0)
end

function C.state_dir()
    local x = os.getenv("XDG_STATE_HOME")
    if x and x ~= "" then return x end
    return C.HOME .. "/.local/state"
end

-- defaults (graphite/defaults.lua) <- live tokens (~/.local/state/graphite/tokens.lua)
function C.load_tokens()
    local t = C.deepcopy(require("graphite.defaults"))
    local entry = C.state_dir() .. "/?.lua"
    if not package.path:find(entry, 1, true) then
        package.path = package.path .. ";" .. entry
    end
    -- resolves to <state>/graphite/tokens.lua (nothing named graphite/tokens.lua
    -- exists in the config dir, so the config dir entries of package.path miss).
    local live = C.optional_require("graphite.tokens")
    if type(live) == "table" then
        C.deepmerge(t, live)
        C.tokens_source = "live"
    else
        C.tokens_source = "defaults"
    end
    return t
end

---------------------------------------------------------------------------
-- colors / motion
---------------------------------------------------------------------------

-- "#RRGGBB" (+ alpha 0..1) -> "rgba(rrggbbaa)" as Hyprland expects.
function C.rgba(hex, alpha)
    hex = tostring(hex or "#000000"):gsub("^#", "")
    if #hex == 8 then -- already RRGGBBAA
        return "rgba(" .. hex:lower() .. ")"
    end
    assert(#hex == 6, "color must be #RRGGBB, got " .. tostring(hex))
    local a = math.floor(math.max(0, math.min(1, alpha or 1)) * 255 + 0.5)
    return string.format("rgba(%s%02x)", hex:lower(), a)
end

-- Hyprland animation speed is in deciseconds (1 = 100 ms).
function C.speed(ms)
    return math.max(0.1, (tonumber(ms) or 100) / 100)
end

function C.clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

---------------------------------------------------------------------------
-- execs / commands
---------------------------------------------------------------------------

-- Substitute ${name} placeholders from `vars` (settings.vars). Shell variables
-- like $HOME / ${TERMINAL} are left alone for /bin/sh to expand.
function C.subst(s, vars)
    return (s:gsub("%$%{([%w_]+)%}", function(k)
        local v = vars and vars[k]
        if v == nil then return nil end -- keep "${k}" for the shell
        return tostring(v)
    end))
end

---------------------------------------------------------------------------
-- actions that used helper scripts (those scripts call `hyprctl dispatch/keyword`
-- in conf syntax, which fails under a Lua config)
---------------------------------------------------------------------------

-- cursor zoom, clamped 1..3 (was the ii-era zoom.sh helper)
function C.zoom_fn(delta)
    return C.fn("zoom " .. delta, function()
        local v = tonumber((hl.get_config("cursor.zoom_factor"))) or 1
        hl.config({ cursor = { zoom_factor = C.clamp(v + delta, 1.0, 3.0) } })
    end)
end

-- workspace N within the current group of 10 (was the ii-era workspace_action.sh helper):
-- target = floor((current-1)/10)*10 + n.  mode "workspace" focuses it on the monitor
-- under focus (focusworkspaceoncurrentmonitor); "movetoworkspace" moves the window.
function C.workspace_action(mode, n)
    return C.fn("workspace_action " .. mode .. " " .. n, function()
        local ws = hl.get_active_workspace()
        local cur = (ws and ws.id and ws.id > 0) and ws.id or 1
        local target = math.floor((cur - 1) / 10) * 10 + n
        if mode == "workspace" then
            hl.dispatch(hl.dsp.focus({ workspace = target, on_current_monitor = true }))
        else
            hl.dispatch(hl.dsp.window.move({ workspace = target }))
        end
    end)
end

---------------------------------------------------------------------------
-- binds
---------------------------------------------------------------------------

-- Options accepted by hl.bind (0.55.4, LuaBindingsToplevel.cpp).
local BIND_OPTS = {
    "repeating", "locked", "release", "non_consuming", "auto_consuming", "transparent",
    "ignore_mods", "dont_inhibit", "long_press", "submap_universal", "click", "drag", "device",
}

-- A bind entry is a table:
--   { "SUPER + Q", <dispatcher|function>, desc = "...", locked = true, ... }
-- or a submap block:
--   { submap = "name", binds = { ...entries... } }
-- Entries with enabled = false are skipped (keep them as documentation).
function C.apply_binds(list, ctx, in_submap)
    for _, b in ipairs(list or {}) do
        if b.enabled == false then
            -- skipped on purpose
        elseif b.submap then
            local inner = b.binds or {}
            hl.define_submap(b.submap, function() C.apply_binds(inner, ctx, true) end)
        else
            local key, action = b[1], b[2]
            if key == "catchall" and not in_submap then
                ctx.warn("catchall bind skipped: catchall only works inside a submap (settings.bind_submap)")
            else
                local opts, any = {}, false
                for _, o in ipairs(BIND_OPTS) do
                    if b[o] ~= nil then opts[o] = b[o]; any = true end
                end
                if b.desc then opts.description = b.desc; any = true end
                hl.bind(key, action, any and opts or nil)
            end
        end
    end
end

return C
