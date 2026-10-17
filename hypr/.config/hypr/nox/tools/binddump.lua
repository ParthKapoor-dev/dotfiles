-- Offline bind dump: runs the Graphite config under plain `lua` (5.5, same as
-- Hyprland 0.55) with a mock `hl`, and prints every bind as one JSON object per
-- line in a hyprctl-like shape (legacy dispatcher names). (Its partner
-- binddiff.py, a diff against a running .conf session, was removed with the
-- .conf config on 2026-10-17.)
--
--   lua graphite/tools/binddump.lua ~/.config/hypr/graphite.lua > lua-binds.jsonl
--
-- Not loaded by Hyprland (nothing require()s it).

local entry = assert(arg[1], "usage: lua binddump.lua <path/to/graphite.lua>")
local dir = entry:match("^(.*)/[^/]*$") or "."
package.path = dir .. "/?.lua;" .. dir .. "/?/init.lua;" .. package.path

local MODS = { SHIFT = 1, CAPS = 2, CTRL = 4, CONTROL = 4, ALT = 8, MOD2 = 16, MOD3 = 32, SUPER = 64, WIN = 64, LOGO = 64, MOD4 = 64, META = 64, MOD5 = 128 }

local binds, submap = {}, "" -- current submap while registering

local function dsp(path)
    return function(...) return { __dsp = path, args = { ... } } end
end

local function ns(prefix, names)
    local t = {}
    for _, n in ipairs(names) do t[n] = dsp(prefix .. n) end
    return t
end

local stub = function() end
hl = setmetatable({
    dsp = setmetatable({
        window = ns("window.", { "close", "kill", "signal", "float", "fullscreen", "fullscreen_state", "pseudo", "move",
            "swap", "center", "cycle_next", "tag", "clear_tags", "toggle_swallow", "pin", "bring_to_top", "alter_zorder",
            "set_prop", "deny_from_group", "drag", "resize" }),
        workspace = ns("workspace.", { "move", "rename", "swap_monitors", "toggle_special" }),
        cursor = ns("cursor.", { "move", "move_to_corner" }),
        group = ns("group.", { "toggle", "next", "prev", "active", "move_window", "lock", "lock_active" }),
    }, { __index = function(_, k) return dsp(k) end }),
    bind = function(keys, action, opts)
        binds[#binds + 1] = { submap = submap, keys = keys, action = action, opts = opts or {} }
    end,
    define_submap = function(name, a, b)
        local fn = type(a) == "function" and a or b
        local prev = submap
        submap = name
        fn()
        submap = prev
    end,
    get_config = function() return 1 end,
    get_monitors = function() return {} end,
    get_current_submap = function() return "" end,
}, { __index = function() return stub end })

local ok, err = pcall(dofile, entry)
if not ok then io.stderr:write("config error: " .. tostring(err) .. "\n") end

local core = package.loaded["graphite.core"]

local function legacy(action)
    if type(action) == "function" then
        return "lua", (core and core.labels[action]) or "function"
    end
    local p, a = action.__dsp, action.args
    local t = a[1]
    if p == "exec_cmd" then return "exec", t end
    if p == "global" then return "global", t end
    if p == "layout" then return "layoutmsg", t end
    if p == "submap" then return "submap", t end
    if p == "focus" then
        if t.direction then return "movefocus", t.direction end
        if t.workspace then
            return t.on_current_monitor and "focusworkspaceoncurrentmonitor" or "workspace", tostring(t.workspace)
        end
    end
    if p == "window.move" then
        if t.direction then return "movewindow", t.direction end
        if t.workspace then
            return (t.follow == false) and "movetoworkspacesilent" or "movetoworkspace", tostring(t.workspace)
        end
    end
    if p == "window.close" then return "killactive", "" end
    if p == "window.pin" then return "pin", "" end
    if p == "window.drag" then return "mouse", "movewindow" end
    if p == "window.resize" then
        if t then return "resizeactive", string.format("exact %d %d", t.x, t.y) end
        return "mouse", "resizewindow"
    end
    if p == "window.float" then return "togglefloating", "" end
    if p == "window.fullscreen" then return "fullscreen", (t and t.mode == "maximized") and "1" or "0" end
    if p == "window.fullscreen_state" then return "fullscreenstate", t.internal .. " " .. t.client end
    if p == "workspace.toggle_special" then return "togglespecialworkspace", t or "" end
    if p == "workspace.move" then return "movecurrentworkspacetomonitor", t.monitor end
    if p == "workspace.swap_monitors" then return "swapactiveworkspaces", t.monitor1 .. " " .. t.monitor2 end
    return p, "?"
end

local function jstr(s)
    s = tostring(s):gsub('[%c"\\]', function(c)
        local m = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\t"] = "\\t" }
        return m[c] or string.format("\\u%04x", c:byte())
    end)
    return '"' .. s .. '"'
end

for _, b in ipairs(binds) do
    local mask, key, keycode, catchall = 0, "", 0, false
    if b.keys == "catchall" then
        catchall = true
    else
        for raw in b.keys:gmatch("[^+]+") do
            local part = raw:match("^%s*(.-)%s*$")
            if MODS[part] then mask = mask | MODS[part]
            elseif part:match("^code:%d+$") then keycode = tonumber(part:sub(6))
            else key = part end
        end
    end
    local d, a = legacy(b.action)
    if d == "mouse" then b.opts.mouse = true end
    local o = b.opts
    print(string.format(
        '{"submap":%s,"modmask":%d,"key":%s,"keycode":%d,"catch_all":%s,"dispatcher":%s,"arg":%s,'
        .. '"locked":%s,"release":%s,"repeat":%s,"non_consuming":%s,"mouse":%s,"description":%s,'
        .. '"ignore_mods":%s,"transparent":%s,"dont_inhibit":%s}',
        jstr(b.submap), mask, jstr(key), keycode, tostring(catchall), jstr(d), jstr(a),
        tostring(o.locked == true), tostring(o.release == true), tostring(o.repeating == true),
        tostring(o.non_consuming == true), tostring(o.mouse == true), jstr(o.description or ""),
        tostring(o.ignore_mods == true), tostring(o.transparent == true), tostring(o.dont_inhibit == true)))
end
