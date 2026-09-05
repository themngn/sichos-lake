------------------------
---- WORKSPACE POOL ----
------------------------

-- Implements the dynamic workspace-pool design in ~/Docs/workspaces.md: a
-- shared pool of `pool_size = max(6, peak_displays + 3)` workspace IDs,
-- where every empty/unopened workspace in that range is "Available Pool"
-- -- fluid, summonable onto whichever monitor currently has keyboard
-- focus -- while a hidden workspace with windows on it ("Background
-- Workflow") stays pinned to whatever monitor it was last shown on.
--
-- Deliberately does NOT keep a shadow table of "which workspace belongs
-- to which monitor" for everyday decisions: Hyprland's own live state
-- (ws.visible, ws.windows, ws.monitor) is queried at the moment of every
-- keybind/hotplug decision instead, since a second source of truth would
-- just drift from the first. The two things that genuinely can't be
-- derived live -- peak_displays (a historical high-water mark) and the
-- last workspace shown on each monitor, keyed by EDID description so it
-- survives a port change -- are persisted to a small state file, because
-- Hyprland's own CConfigManager::reload() calls reinitLuaState(), which
-- lua_close()s and recreates the whole Lua VM on *every* `hyprctl
-- reload` -- including the file-save-triggered reloads this repo relies
-- on for every other config file -- so anything kept only in a Lua
-- global is wiped by that hot-reload workflow.

local STATE_DIR  = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")) .. "/sichos"
local STATE_FILE = STATE_DIR .. "/hypr-workspaces.lua"

-- ---- tiny state persistence ----
-- Not JSON: Lua can read its own table syntax straight back with
-- loadfile(), so there's no parser to hand-roll for a two-field table.

local function serialize(v, indent)
    indent = indent or ""
    local t = type(v)
    if t == "number" or t == "boolean" then
        return tostring(v)
    elseif t == "string" then
        return string.format("%q", v)
    elseif t == "table" then
        local parts = {}
        for k, val in pairs(v) do
            local key = type(k) == "string" and ("[" .. string.format("%q", k) .. "]") or ("[" .. tostring(k) .. "]")
            table.insert(parts, indent .. "  " .. key .. " = " .. serialize(val, indent .. "  "))
        end
        return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
    end
    return "nil"
end

local function loadState()
    local chunk = loadfile(STATE_FILE)
    local ok, result = false, nil
    if chunk then
        ok, result = pcall(chunk)
    end
    if ok and type(result) == "table" then
        result.assignments = result.assignments or {}
        return result
    end
    return { peak_displays = 0, assignments = {} }
end

local state       = loadState()
local stateDirty  = false

local function saveState()
    if not stateDirty then return end
    local escapedDir = STATE_DIR:gsub("'", "'\\''")
    os.execute("mkdir -p -- '" .. escapedDir .. "'")
    local f = io.open(STATE_FILE, "w")
    if not f then return end
    f:write("return " .. serialize(state) .. "\n")
    f:close()
    stateDirty = false
end

-- ---- primary display (workspaces.md §1: "first monitor in Hyprland
-- config order") ----
-- hl.get_monitors() is connection order, not declaration order (verified
-- live: eDP-1 enumerates before DP-1 despite DP-1 being declared first in
-- monitors.lua), and there's no live API for declaration order -- so this
-- reads the deployed monitors.lua text and takes its first non-wildcard
-- `output = "..."`.
local function detectPrimaryOutput()
    local home = os.getenv("HOME")
    local path = home and (home .. "/.config/hypr/monitors.lua")
    local f = path and io.open(path, "r")
    if f then
        for line in f:lines() do
            local output = line:match('output%s*=%s*"([^"]*)"')
            if output and output ~= "" then
                f:close()
                return output
            end
        end
        f:close()
    end
    -- Wildcard-only monitors.lua (the repo's per-machine template before
    -- it's customized): fall back to whatever connects first. Not really
    -- "config order" but there's no config order to read yet either.
    local mons = hl.get_monitors()
    return mons[1] and mons[1].name or nil
end

local PRIMARY_OUTPUT = detectPrimaryOutput()

-- ---- pool sizing ----

local peakDisplays = math.max(state.peak_displays or 0, #hl.get_monitors())
if peakDisplays ~= state.peak_displays then
    state.peak_displays = peakDisplays
    stateDirty = true
end

local function poolSize()
    return math.max(6, peakDisplays + 3)
end

local POOL_SIZE_FILE = STATE_DIR .. "/pool-size"

-- Plain integer, not the Lua-table state file above: the quickshell bar's
-- Workspaces module reads this to render a placeholder pill for every
-- pool-range id even when it's empty/unsummoned (workspace_rule
-- persistent=true used to do this on Hyprland's side, but that actively
-- broke the pool -- see the comment above where that block used to be).
-- This file is cosmetic only; Lua stays the sole source of truth for
-- everything that actually dispatches or binds.
local function writePoolSizeFile()
    local escapedDir = STATE_DIR:gsub("'", "'\\''")
    os.execute("mkdir -p -- '" .. escapedDir .. "'")
    local f = io.open(POOL_SIZE_FILE, "w")
    if not f then return end
    f:write(tostring(poolSize()) .. "\n")
    f:close()
end
writePoolSizeFile()

-- peak_displays is meant to be a *this-session* high-water mark
-- (workspaces.md §1), but it lives in a file that survives a reboot (it
-- has to -- see the file-level comment on why nothing can live only in a
-- Lua global). hyprland.start fires once per real compositor start, never
-- on a `hyprctl reload`, so it's the only reliable "a new session just
-- began" signal available -- reset the floor here. If hl.get_monitors()
-- is still empty this early in boot, the reset just floors it at 0 and
-- the monitor.added growth logic below brings it back up to the real
-- count as each boot-time monitor connects, so an early/empty read here
-- self-corrects and isn't a problem.
hl.on("hyprland.start", function()
    peakDisplays = #hl.get_monitors()
    state.peak_displays = peakDisplays
    stateDirty = true
    saveState()
    writePoolSizeFile()
end)

-- Pool workspaces are deliberately NOT marked persistent (this used to be
-- a hardcoded `for i=1,6 do hl.workspace_rule({workspace=tostring(i),
-- persistent=true}) end` block in look_and_feel.lua, kept and extended
-- here at first for the quickshell bar's Workspaces module -- always
-- showing a pill for the whole pool, not just whatever currently has
-- windows). Confirmed live that it actively breaks the pool: a persistent
-- workspace_rule with no explicit `monitor` field makes Hyprland's own
-- CWorkspacePlacementController::ensurePersistentWorkspacesPresent (see
-- WorkspacePlacementController.cpp) run on *every* monitor connect, for
-- every already-connected monitor, and force-reassign each such
-- workspace onto whichever monitor currently has keyboard focus -- if
-- that workspace happened to be actively showing on some OTHER monitor,
-- moveWorkspaceToMonitor's own gap-plugging logic replaces it there with
-- a freshly-created placeholder, i.e. a real, visible workspace swap on a
-- monitor the user wasn't even touching. Giving the rule an explicit
-- `monitor = PRIMARY_OUTPUT` doesn't fix this either -- it just changes
-- the trigger to "any monitor connects while a pool workspace the user
-- summoned elsewhere isn't on primary," which is just as disruptive.
-- Without persistence, a pool workspace that goes empty+hidden is simply
-- recycled by Hyprland, and isPoolWorkspace() already treats "doesn't
-- exist" the same as "exists but empty and hidden" -- so the pool logic
-- doesn't need the rule at all. Trade-off: the bar now only shows a pill
-- for a pool workspace once it's actually visible or occupied, not for
-- every unsummoned pool slot.

saveState()

-- "Shift focus... warp the cursor there, centered" (workspaces.md §3, the
-- two primitives). Hyprland's own Actions::changeWorkspace already does
-- exactly this whenever cursor.warp_on_change_workspace is non-zero (2 =
-- centered -- see ConfigActions.cpp) -- one config value, not a
-- hand-rolled cursor move.
hl.config({ cursor = { warp_on_change_workspace = 2 } })

-- ---- pool queries (live, no cached state) ----

local function isPoolWorkspace(id)
    if id < 1 or id > poolSize() then return false end
    local ws = hl.get_workspace(tostring(id))
    if not ws then return true end
    return (not ws.visible) and (ws.windows or 0) == 0
end

local function lowestPoolWorkspace()
    for i = 1, poolSize() do
        if isPoolWorkspace(i) then return i end
    end
    return nil
end

local function highestBackgroundWorkspace()
    for i = poolSize(), 1, -1 do
        local ws = hl.get_workspace(tostring(i))
        if ws and not ws.visible and (ws.windows or 0) > 0 then
            return i
        end
    end
    return nil
end

-- ---- monitor <-> workspace tracking ----
-- lastActiveByMonitor is session-local (rebuilt fresh every load from
-- live state) and exists only to answer "what was on a monitor a moment
-- ago" from inside monitor.removed, where the removed monitor's own
-- active_workspace has already been cleared by the time our handler runs
-- (see the comment on that handler below). state.assignments is the
-- persisted, EDID-keyed counterpart used for daemon-startup restore
-- (§3.4), so it survives a port change or a reboot.

local lastActiveByMonitor = {}
for _, m in ipairs(hl.get_monitors()) do
    if m.active_workspace then
        lastActiveByMonitor[m.name] = m.active_workspace.id
    end
end

hl.on("workspace.active", function(ws)
    if not ws or not ws.monitor then return end
    lastActiveByMonitor[ws.monitor.name] = ws.id

    local desc = ws.monitor.description
    if desc and state.assignments[desc] ~= ws.id then
        state.assignments[desc] = ws.id
        stateDirty = true
        saveState()
    end
end)

-- ---- hotplugging (§3.3) + daemon startup restore (§3.4) ----
-- monitor.added does NOT mean "this monitor has nothing yet" -- by the
-- time it fires, CMonitor::onConnect (src/output/Monitor.cpp) has
-- already run setupDefaultWS() *and* its own remembered-workspace restore
-- (keyed by port name, e.g. "was DP-1 last on workspace 8? put it back")
-- and switched the monitor there. It also refires on a plain `hyprctl
-- reload`, not just a real hotplug (confirmed live: reloading with no
-- hardware change still fires it). So this can never treat "has an
-- active workspace" as "unbound" -- it always does, even for a monitor
-- that's been connected the whole time. The only thing worth overriding
-- is a pick that's actively wrong for our pool: an empty workspace inside
-- the pool range (Hyprland's own default-numbering handed it a
-- placeholder that our Tier 1/2 should own instead). Anything with
-- windows, or any id outside the pool entirely (the user parked real work
-- on workspace 7/8/9 before this pool existed), is left alone.
--
-- This also means Hyprland's native per-name restore already implements
-- most of §3.4 on its own, so this function doesn't separately consult
-- state.assignments (the EDID-keyed persisted map) for restore purposes
-- -- a second restore mechanism raced the native one and actively made
-- things worse in testing (overrode a correct native restore with a
-- Tier-1 pick, displacing a real window). state.assignments is still
-- written on every workspace.active (below) because monitor.removed
-- needs it -- Hyprland's own native remember is keyed by port name, which
-- doesn't survive the monitor moving to a different port, so it can't
-- serve that case -- but it is deliberately not read here.
local function bindMonitor(mon)
    local current = mon.active_workspace
    if current and ((current.windows or 0) > 0 or current.id < 1 or current.id > poolSize()) then
        return -- already showing something worth keeping
    end

    local tier1 = lowestPoolWorkspace()
    if tier1 then
        mon:set_workspace({ workspace = tostring(tier1) })
        return
    end

    local tier2 = highestBackgroundWorkspace()
    if tier2 then
        mon:set_workspace({ workspace = tostring(tier2) })
    end
    -- Neither tier found anything: the Always-Spare Guarantee would be
    -- violated, which shouldn't happen since peak_displays/pool_size is
    -- updated (below) before this runs. Leave Hyprland's own default
    -- assignment in place rather than fail loudly.
end

hl.on("monitor.added", function(mon)
    local connected = #hl.get_monitors()
    if connected > peakDisplays then
        peakDisplays = connected
        state.peak_displays = peakDisplays
        stateDirty = true
        saveState()
        writePoolSizeFile()
    end
    bindMonitor(mon)
end)

-- Hyprland's own CMonitor::onDisconnect (src/output/Monitor.cpp) already
-- force-migrates every workspace the disconnected monitor owned onto
-- "the first other monitor it finds" (its internal BACKUPMON, not
-- necessarily our config's primary) *before* emitting monitor.removed --
-- the emit is inside a scope guard that runs at function return, after
-- all of that migration. So by the time this fires, mon.active_workspace
-- has already been reset to nil; lastActiveByMonitor is the only record
-- of what was on it a moment ago.
--
-- A monitor connected through a link with an LTTPR repeater (a dock, a
-- long/active DP cable) can drop and immediately re-negotiate on its own
-- -- confirmed on this machine via a real disconnect/reconnect pair in
-- Hyprland's own log lining up with amdgpu logging "LTTPR count is
-- nonzero but invalid lane count reported" in dmesg, a known Display Core
-- driver quirk, not anything under this repo's control. Each flap is a
-- genuine monitor.removed + monitor.added pair seconds apart, so
-- re-pinning an occupied workspace to primary immediately on every
-- removed -- only to have the monitor reappear and Hyprland's own
-- restore-by-name try to put it right back -- is a self-inflicted
-- tug-of-war between the two restore mechanisms. FLICKER_GRACE_MS defers
-- the re-pin and cancels it if the monitor comes back first.
local FLICKER_GRACE_MS = 4000

hl.on("monitor.removed", function(mon)
    local name  = mon.name
    local wasId = lastActiveByMonitor[name]
    lastActiveByMonitor[name] = nil
    if not wasId or not PRIMARY_OUTPUT then return end

    hl.timer(function()
        if hl.get_monitor(name) then
            return -- reconnected within the grace window -- a flap, not a real removal
        end

        local ws = hl.get_workspace(tostring(wasId))
        if not ws or (ws.windows or 0) == 0 then
            return -- was empty -> already released to the pool, nothing to pin down
        end

        if ws.visible then
            -- The user's focus followed it to wherever Hyprland's native
            -- fallback parked it (it was the disconnected monitor's
            -- active workspace, so focus moved there too). Forcing it
            -- onto primary now would yank a window out from under
            -- whatever they're doing. Deliberate deviation from a
            -- literal "occupied -> always primary" reading of §3.3.
            return
        end

        if ws.monitor and ws.monitor.name ~= PRIMARY_OUTPUT then
            -- Ownership-only reassignment: the workspace isn't active on
            -- its current (BACKUPMON) owner, so Hyprland's
            -- moveWorkspaceToMonitor won't make it visible/swap anything
            -- on primary either -- see
            -- CWorkspacePlacementController::moveWorkspaceToMonitor's
            -- SWITCHINGISACTIVE guard in WorkspacePlacementController.cpp.
            hl.dispatch(hl.dsp.workspace.move({ workspace = tostring(wasId), monitor = PRIMARY_OUTPUT }))
        end
    end, { timeout = FLICKER_GRACE_MS, type = "oneshot" })
end)

---------------------------------------
---- KEYBINDINGS: SUPER + [0-9,0] ----
---------------------------------------

-- Replaces the plain hl.dsp.focus/window.move binds that used to live in
-- keybindings.lua -- see workspaces.md §3.1/§3.2 for the dispatch table
-- these implement, and §4 for the out-of-bounds rejection.

local mainMod = "SUPER"

local function isReachable(id)
    return id >= 1 and id <= poolSize()
end

local function occupiedOrVisible(ws)
    return ws ~= nil and (ws.visible or (ws.windows or 0) > 0)
end

-- §3.1 User Navigation
local function callWorkspace(id)
    if not isReachable(id) then return end -- §4: request for an out-of-bounds id is rejected outright
    local key = tostring(id)
    local ws  = hl.get_workspace(key)
    if occupiedOrVisible(ws) then
        -- Active Workflow / Active Blank / Background Workflow: don't move it, just shift focus to its own monitor
        hl.dispatch(hl.dsp.focus({ workspace = key }))
    else
        -- Available Pool: summon it onto the monitor you're currently focused on
        hl.dispatch(hl.dsp.focus({ workspace = key, on_current_monitor = true }))
    end
end

-- §3.2 Window Management. forceSilent is the pre-existing
-- mainMod+SHIFT+ALT+key "move without following" escape hatch, kept as an
-- explicit override now that plain SHIFT+key already follows/doesn't
-- follow conditionally per the spec.
local function moveWindowToWorkspace(id, forceSilent)
    if not isReachable(id) then return end
    local key          = tostring(id)
    local ws           = hl.get_workspace(key)
    local hiddenTarget = forceSilent or not occupiedOrVisible(ws)

    if hiddenTarget then
        if not ws or (not ws.visible and (ws.windows or 0) == 0) then
            -- Available Pool target: pin it to the monitor you're
            -- focused on right now, before the window lands there --
            -- moveToWorkspace's silent path never touches workspace
            -- ownership (Actions::moveToWorkspace in ConfigActions.cpp),
            -- so without this it would keep whatever owner it had last.
            local focused = hl.get_active_monitor()
            if focused then
                hl.dispatch(hl.dsp.workspace.move({ workspace = key, monitor = focused.name }))
            end
        end
        hl.dispatch(hl.dsp.window.move({ workspace = key, follow = false }))
    else
        hl.dispatch(hl.dsp.window.move({ workspace = key }))
    end
end

for i = 1, 10 do
    local key = i == 10 and "0" or tostring(i)
    local id  = i
    hl.bind(mainMod .. " + " .. key,               function() callWorkspace(id) end)
    hl.bind(mainMod .. " + SHIFT + " .. key,       function() moveWindowToWorkspace(id, false) end)
    hl.bind(mainMod .. " + SHIFT + ALT + " .. key, function() moveWindowToWorkspace(id, true) end)
end
