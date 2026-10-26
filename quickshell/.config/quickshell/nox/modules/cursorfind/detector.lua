-- nox shake-to-find detector, run inside Hyprland's Lua state.
-- Not part of the hypr config: modules/cursorfind/CursorFind.qml sends this file with
-- `hyprctl eval` when the module loads (and again after every Hyprland config reload, which
-- recreates the Lua state), then calls NOX_CURSORFIND.start({...}). NOX_CURSORFIND.stop()
-- cancels it. Hyprland 0.56 has no pointer-motion event for Lua (hl.on knows no input.mouse.*),
-- so this samples hl.get_cursor_pos() on an hl.timer, in-process (no IPC per sample):
--   idle   one sample every idleMs (500): the pointer hasn't moved for a second
--   moving one sample every 1000/hz ms (33); back to idle after 1 s without motion
-- A shake = `reversals` direction flips (either axis, steps of 6+ px) with `travel` px of path
-- inside the last windowMs. It emits the socket2 event custom>>nox-cursorfind <x> <y> (global
-- layout px), which the shell sees through Hyprland.rawEvent: no process is spawned. Then
-- cooldownMs of quiet.
-- Cost (measured on the live session, 2026-10-26): ~250 us of compositor CPU per sample, so
-- ~0.05% of one core idle (2 Hz) and ~0.75% while the pointer moves (30 Hz).
-- Timer objects only have set_enabled / is_enabled / set_timeout (no cancel).
local M = NOX_CURSORFIND or {}
NOX_CURSORFIND = M

function M.stop()
    if M.timer then M.timer:set_enabled(false) end
    M.timer = nil
end

function M.start(cfg)
    M.stop()
    cfg = cfg or {}
    local fast = math.max(10, math.floor(1000 / (cfg.hz or 30) + 0.5))
    local slow = math.max(fast, cfg.idleMs or 500)
    local n = math.max(3, math.ceil((cfg.windowMs or 400) / fast))
    local travel = cfg.travel or 600
    local reversals = cfg.reversals or 3
    local cooldown = math.ceil((cfg.cooldownMs or 1000) / fast)
    local idleTicks = math.ceil(1000 / fast)

    -- ring buffers of path length and direction flips per sample, with running sums
    local dist, flip = {}, {}
    local at, sumD, sumF = 0, 0, 0
    local function reset()
        for k = 1, n do dist[k] = 0; flip[k] = 0 end
        at, sumD, sumF = 0, 0, 0
    end
    reset()
    local lx, ly, sx, sy = nil, nil, 0, 0
    local still, cool, idle = 0, 0, false

    local function tick()
        local p = hl.get_cursor_pos()
        if not p then return end
        local x, y = p.x, p.y
        if lx == nil then lx, ly = x, y; return end
        local dx, dy = x - lx, y - ly
        lx, ly = x, y
        local d = math.abs(dx) + math.abs(dy)
        if idle then
            -- woke up: sample fast again (this step spans a whole idle interval, so it isn't counted)
            if d >= 1 then idle = false; still = 0; sx, sy = 0, 0; M.timer:set_timeout(fast) end
            return
        end
        if d < 1 then
            still = still + 1
            if still >= idleTicks then idle = true; reset(); M.timer:set_timeout(slow) end
        else
            still = 0
        end
        local f = 0
        if math.abs(dx) >= 6 then
            local s = dx > 0 and 1 or -1
            if sx ~= 0 and s ~= sx then f = 1 end
            sx = s
        end
        if math.abs(dy) >= 6 then
            local s = dy > 0 and 1 or -1
            if sy ~= 0 and s ~= sy then f = 1 end
            sy = s
        end
        at = at % n + 1
        sumD = sumD - dist[at] + d; dist[at] = d
        sumF = sumF - flip[at] + f; flip[at] = f
        if cool > 0 then cool = cool - 1; return end
        if sumF >= reversals and sumD >= travel then
            cool = cooldown
            reset()
            hl.dispatch(hl.dsp.event(string.format("nox-cursorfind %d %d", math.floor(x), math.floor(y))))
        end
    end

    M.timer = hl.timer(function()
        local ok = pcall(tick)
        if not ok then M.stop() end      -- never keep a failing callback ticking
    end, { timeout = fast, type = "repeat" })
end
