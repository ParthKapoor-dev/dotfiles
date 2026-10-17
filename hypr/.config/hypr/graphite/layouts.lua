-- Tiling layout cycling (Super+\ next, Super+Shift+\ previous).
--
-- Not a MODULE: a helper table required by input.lua (initial layout) and
-- binds/windows.lua (cycle binds). Layout names are the tiled algorithms built
-- into Hyprland 0.55.4 (src/layout/supplementary/WorkspaceAlgoMatcher.cpp):
--   dwindle, master, scrolling, monocle   (unknown names fall back to dwindle)
-- Changing `general.layout` at runtime with hl.config() schedules REFRESH_LAYOUTS,
-- which re-creates the tiled algorithm of every workspace that has no
-- workspace-rule `layout` override.
--
-- Runtime entry points (same logic everywhere):
--   binds      -> L.step(S, +1 / -1)                      (in-process)
--   CLI        -> graphite-layout next|prev|set <n>|get
--                 = hyprctl eval 'graphite_layout("next")'  (global installed below)
-- After every change the shell is told: qs -c graphite ipc call layout changed <name>
--
-- Persistence: the choice survives config reloads (the config auto-reloads on
-- every file change, including theme token updates) through a file in
-- $XDG_RUNTIME_DIR, which is wiped at logout. A new session starts at layouts[1].
-- settings.layout_persist = false disables even that.

local L = {}

L.KNOWN = { dwindle = true, master = true, scrolling = true, monocle = true }
L.DEFAULT = { "dwindle", "scrolling", "master" }

-- validated list from settings.layouts (unknown names dropped, never empty)
function L.list(S)
    local out = {}
    for _, n in ipairs((S and S.layouts) or L.DEFAULT) do
        if L.KNOWN[n] then out[#out + 1] = n end
    end
    if #out == 0 then out = { "dwindle" } end
    return out
end

function L.state_file()
    local rt = os.getenv("XDG_RUNTIME_DIR")
    if not rt or rt == "" then return nil end
    return rt .. "/graphite-hypr-layout"
end

local function index_of(list, name)
    for i, n in ipairs(list) do
        if n == name then return i end
    end
    return nil
end

local function read_state()
    local p = L.state_file()
    local f = p and io.open(p, "r")
    if not f then return nil end
    local s = f:read("l")
    f:close()
    return s
end

local function write_state(name)
    local p = L.state_file()
    local f = p and io.open(p, "w")
    if not f then return end
    f:write(name, "\n")
    f:close()
end

-- layout to use when the config (re)loads
function L.initial(S)
    local list = L.list(S)
    if S.layout_persist ~= false then
        local saved = read_state()
        if saved and index_of(list, saved) then return saved end
    end
    return list[1]
end

function L.current()
    local ok, v = pcall(hl.get_config, "general.layout")
    if ok and type(v) == "string" and v ~= "" then return v end
    return "dwindle"
end

-- shell notification; the IPC name lives in the API table of shells/graphite.lua
local function notify_cmd(name)
    local ok, gp = pcall(require, "graphite.shells.graphite")
    local qs = ok and type(gp) == "table" and gp.QS or "qs -c graphite"
    local call = ok and type(gp) == "table" and gp.IPC and gp.IPC.layout_changed or "layout changed"
    return string.format("%s ipc call %s %s >/dev/null 2>&1", qs, call, name)
end

-- set layout `name` (must be a known algorithm); returns the active name
function L.set(S, name)
    if not L.KNOWN[name] then return L.current() end
    hl.config({ general = { layout = name } })
    if S.layout_persist ~= false then write_state(name) end
    hl.exec_cmd(notify_cmd(name))
    return name
end

-- move `delta` steps through settings.layouts (wraps); a current layout that is
-- not in the list counts as "before the first entry"
function L.step(S, delta)
    local list = L.list(S)
    local i = index_of(list, L.current())
    if not i then
        i = delta > 0 and 0 or 1
    end
    local n = #list
    return L.set(S, list[((i - 1 + delta) % n) + 1])
end

-- bind action (labelled for tools/binddump.lua)
function L.bind_fn(C, S, delta)
    return C.fn("layout " .. (delta > 0 and "next" or "prev"), function() L.step(S, delta) end)
end

-- global for `hyprctl eval` (graphite-layout CLI). Returns the active layout name.
--   graphite_layout("next" | "prev" | "get")   graphite_layout("set", "master")
function L.install_global(S)
    _G.graphite_layout = function(cmd, arg)
        if cmd == "next" then return L.step(S, 1) end
        if cmd == "prev" then return L.step(S, -1) end
        if cmd == "set" then
            if not L.KNOWN[arg] then error("unknown layout '" .. tostring(arg) .. "'", 0) end
            return L.set(S, arg)
        end
        if cmd == "list" then return table.concat(L.list(S), " ") end
        return L.current()
    end
end

return L
