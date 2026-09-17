---------------------
---- KEYBINDINGS ----
---------------------

local programs = require("programs")

local mainMod = "SUPER" -- Sets "Windows" key as main modifier

-- Laptop lid switch handling. Closing the lid doesn't disconnect the internal
-- panel the way unplugging a monitor does, so Hyprland keeps treating it as a
-- live output even though nothing is visible. systemd-logind's own defaults
-- already do the right thing for suspend (HandleLidSwitch=suspend when
-- undocked, HandleLidSwitchDocked=ignore -- which per `man logind.conf` also
-- covers "more than one display connected", not just an actual docking
-- station -- so a lid close with an external monitor attached doesn't
-- suspend at all); what's missing is Hyprland disabling the now-invisible
-- internal panel in that docked case, so windows/workspaces stop landing on
-- it. Device confirmed present as "Lid Switch" via `hyprctl devices` and the
-- bind syntax verified live via `hyprctl eval` before adding this. Harmless
-- no-op on any machine without a lid switch (desktops).
--
-- Two things this got wrong the first time (confirmed live via journalctl
-- after a real incident -- see git log for this comment's revision): (1) it
-- disabled unconditionally, including the plain undocked case where the
-- panel is the *only* output and the lid close just triggers a real suspend
-- -- if the matching re-enable doesn't survive that suspend/resume cycle,
-- the panel is left disabled with nothing else to show, i.e. permanently
-- black until a reboot. Now the disable only fires when another monitor is
-- actually active (docked). The re-enable stays unconditional on purpose --
-- it's a harmless no-op on an already-enabled panel, whereas guarding it too
-- would risk stranding a genuinely-disabled one forever (e.g. undocking
-- while docked and closed, then opening). (2) it hardcoded "eDP-1" -- common
-- but not universal (older/other laptops use LVDS-1 or DSI-1), so this now
-- detects the internal panel once at load time by connector prefix instead,
-- the same prefix set an earlier, since-reverted monitor-watch.py daemon
-- used for the same purpose.
local function detectInternalPanel()
    for _, m in ipairs(hl.get_monitors()) do
        if m.name:match("^eDP") or m.name:match("^LVDS") or m.name:match("^DSI") then
            return m.name
        end
    end
    return nil -- desktop, or a panel naming scheme this doesn't recognize
end

local INTERNAL_PANEL = detectInternalPanel()

local function otherMonitorActive()
    for _, m in ipairs(hl.get_monitors()) do
        if m.name ~= INTERNAL_PANEL then
            return true
        end
    end
    return false
end

hl.bind("switch:on:Lid Switch", function()
    if INTERNAL_PANEL and otherMonitorActive() then
        hl.monitor({ output = INTERNAL_PANEL, disabled = true })
    end
end)
hl.bind("switch:off:Lid Switch", function()
    if INTERNAL_PANEL then
        hl.monitor({ output = INTERNAL_PANEL, disabled = false })
    end
end)

-- Example binds, see https://wiki.hypr.land/Configuring/Basics/Binds/ for more
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(programs.terminal))
hl.bind(mainMod .. " + SHIFT + Return", hl.dsp.exec_cmd(programs.browser))
local closeWindowBind = hl.bind(mainMod .. " + W", hl.dsp.window.close())
-- closeWindowBind:set_enabled(false)
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(programs.fileManager))
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.exec_cmd(programs.fileManager))
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen({ action = "toggle" }))
hl.bind(mainMod .. " + Z", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true }) -- requires playerctl, see multimedia keys below; locked so it also works from the hyprlock screen
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("hyprlock"))
hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd("quickshell ipc call launcher toggleApps")) -- quickshell launcher: apps only
hl.bind(mainMod .. " + SHIFT + Q", hl.dsp.exec_cmd("quickshell ipc call launcher toggleFull")) -- quickshell launcher: full root menu (Apps/Toggles/Power)
hl.bind(mainMod .. " + SHIFT + H", hl.dsp.exec_cmd("quickshell ipc call hdr toggle")) -- toggle HDR (only on monitors picked in the bar's HDR popup, see HdrSettings.qml)
hl.bind(mainMod .. " + SHIFT + P", hl.dsp.window.pseudo()) -- moved off SUPER+P to free it for the mirror/extend toggle below
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))    -- dwindle only

-- SUPER + P: mirror/extend toggle for every currently-connected monitor
-- other than the internal panel (or, on a desktop with no panel, other than
-- the first monitor Hyprland reports) -- the same "quickly project to a
-- screen" action Windows binds to Win+P. The physical Fn+F7 key sends the
-- XF86DisplayToggle keysym for that exact same Windows feature (see the git
-- history for this file's own investigation of that key), but isn't bound
-- here too: it fires a real SUPER keydown as part of its own hardware chord
-- (confirmed live via `libinput debug-events`), so wiring both triggers to
-- one dispatcher risked them racing each other -- SUPER+P alone is enough.
--
-- Snapshotted once at config load, after monitors.lua (required before this
-- file, see hyprland.lua) has already applied this machine's real layout --
-- restoring from this rather than Hyprland's generic "auto" placement keeps
-- "extend" landing back on the deliberate per-machine layout monitors.lua
-- configured (e.g. this machine's L-shaped 3-monitor arrangement) instead of
-- whatever auto-placement would produce. A monitor hotplugged later (an
-- actual projector plugged in after startup, the real-world case this bind
-- is for) has no snapshot entry, so it falls back to "preferred"/"auto".
--
-- Originally read live `is_mirror` off each monitor instead of tracking this
-- itself, on the theory that would keep this bind from ever getting out of
-- sync with an external hotplug or a manual `hyprctl` change -- confirmed
-- live that `is_mirror` never actually flips true after this bind's own
-- `hl.monitor({ mirror = ... })` call, so that check always read "not
-- currently mirroring" and every press just re-applied mirror (never
-- toggled back to extend). A plain Lua local for the on/off state has its
-- own problem, also confirmed live and already hit once here: `hyprctl
-- reload` -- which is what every file-save-triggered reload in this whole
-- repo is -- calls Hyprland's reinitLuaState(), which lua_close()s and
-- recreates the *entire* Lua VM (see workspaces.lua's own comment on this
-- same fact), wiping any plain local back to whatever this file
-- initializes it to. That's what actually caused DP-2 to get stuck
-- mirrored looking "missing" earlier -- not the toggle logic itself, but
-- state that only lived in memory disagreeing with what monitors.lua had
-- just forced onto the real displays. Persisting to disk like
-- workspaces.lua's own STATE_FILE, and force-applying whatever it says
-- every time this file runs (not just on a keypress), keeps the two from
-- ever disagreeing again.
local STATE_DIR  = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")) .. "/sichos"
local STATE_FILE = STATE_DIR .. "/hypr-displaymode.lua"

local function loadMirrorActive()
    local chunk = loadfile(STATE_FILE)
    local ok, result = false, nil
    if chunk then ok, result = pcall(chunk) end
    if ok and type(result) == "boolean" then return result end
    return false
end

local function saveMirrorActive(active)
    local escapedDir = STATE_DIR:gsub("'", "'\\''")
    os.execute("mkdir -p -- '" .. escapedDir .. "'")
    local f = io.open(STATE_FILE, "w")
    if not f then return end
    f:write("return " .. tostring(active) .. "\n")
    f:close()
end

-- Reads each output's configured mode/position straight out of
-- monitors.lua's own text (same technique workspaces.lua's
-- detectPrimaryOutput() uses, for the same reason) instead of snapshotting
-- live values off hl.get_monitors() -- confirmed live that a monitor mid
-- mode-negotiation right after monitors.lua's own hl.monitor() calls can
-- report width/height/refresh_rate as 0, which this file would otherwise
-- have happily stored and then force-applied back as a literal "0x0@0.00"
-- mode, wedging that output at zero resolution. Parsing the text has no
-- such race and is exactly what the user actually configured, not whatever
-- Hyprland happened to have resolved at the moment this ran.
local function parseMonitorsConfig()
    local layout = {}
    local home = os.getenv("HOME")
    local path = home and (home .. "/.config/hypr/monitors.lua")
    local f = path and io.open(path, "r")
    if not f then return layout end
    local current = nil
    for line in f:lines() do
        local output = line:match('output%s*=%s*"([^"]*)"')
        if output then current = (output ~= "") and output or nil end
        if current then
            local mode = line:match('mode%s*=%s*"([^"]*)"')
            if mode then
                layout[current] = layout[current] or {}
                layout[current].mode = mode
            end
            local position = line:match('position%s*=%s*"([^"]*)"')
            if position then
                layout[current] = layout[current] or {}
                layout[current].position = position
            end
        end
    end
    f:close()
    return layout
end

local extendLayout = parseMonitorsConfig()

-- hl.get_monitors() hides a monitor entirely once it's mirroring another --
-- confirmed live: with DP-1/DP-2 both set to `mirror = "eDP-1"`,
-- hl.get_monitors() returned only eDP-1, the same way `hyprctl monitors`
-- (without "all") hides a mirrored monitor on the CLI side. Two attempts to
-- work around that live-query problem (a growing "known monitors" set, then
-- a version that re-merged on every call) both still ultimately depended on
-- hl.get_monitors() at some point and both still broke: debug logging
-- (temporarily added directly into this function, since `hyprctl eval`
-- turned out to run in its own separate Lua context and couldn't be trusted
-- to reflect what the real running config actually saw) proved live that a
-- single `hyprctl reload` runs this *entire file* through twice, with
-- monitors.lua also re-running each time (both required in hyprland.lua's
-- fixed order) -- pass 1 saw all three monitors and correctly mirrored
-- DP-1/DP-2, but pass 2 landed mid-transition and hl.get_monitors() reported
-- only eDP-1 at that exact instant, so pass 2's own mirror application did
-- nothing while pass 2's monitors.lua had *already* forced plain extend --
-- leaving that as the final result regardless of what pass 1 did or what
-- state was saved.
--
-- Fix: stop asking Hyprland's live monitor state entirely for "which
-- outputs exist" -- extendLayout (parsed from monitors.lua's own text
-- above) is already the authoritative, deterministic list of this machine's
-- configured external outputs, unaffected by mirror-hiding or by which pass
-- of a double reload this happens to be. The only other thing needed is the
-- internal panel's name, which INTERNAL_PANEL already determined once via
-- connector-prefix matching (eDP/LVDS/DSI never get mirrored themselves, so
-- it isn't subject to this same hiding problem). A desktop with no
-- INTERNAL_PANEL and no monitors.lua entries just makes this bind a no-op --
-- "mirror to the laptop panel" doesn't have a meaningful desktop equivalent
-- anyway.
local function otherOutputNames()
    local names = {}
    for name in pairs(extendLayout) do
        if name ~= INTERNAL_PANEL then table.insert(names, name) end
    end
    return names
end

-- Applies (rather than merely records) the given mode to every configured
-- external output -- shared by the keybind below and the force-apply-on-load
-- call right after it, so a saved "mirror" state gets put back onto the
-- actual displays the moment this file runs again, rather than trusting
-- monitors.lua's unconditional extend (already applied by the time this
-- file loads, see hyprland.lua's require order) to have been what the user
-- last chose.
local function applyDisplayMode(active)
    if not INTERNAL_PANEL then return end
    for _, name in ipairs(otherOutputNames()) do
        if active then
            -- `disabled = false` is explicit, not just the implicit default,
            -- for the same reason `mirror = "none"` below is explicit rather
            -- than omitted -- retrainIfWedged() below disables an output
            -- before calling back into this function to recover it, and if
            -- `disabled` turns out to be as sticky as `mirror` already is
            -- (unconfirmed either way, but cheap to guard against), leaving
            -- this field out would strand that output permanently off.
            hl.monitor({ output = name, mirror = INTERNAL_PANEL, disabled = false })
        else
            -- `mirror` is sticky -- confirmed live that a later hl.monitor()
            -- call for the same output with no `mirror` field at all does
            -- NOT clear a previously-set one, it just stays mirrored
            -- forever. "none" is the explicit clear (also confirmed live).
            local saved = extendLayout[name]
            hl.monitor({
                output = name,
                mirror = "none",
                mode = saved.mode,
                position = saved.position,
                disabled = false,
            })
        end
    end
end

local mirrorActive = loadMirrorActive()
applyDisplayMode(mirrorActive)

-- LTTPR link-training recovery: a monitor flapping (disconnect/reconnect)
-- through a dock or long/active DP cable -- see workspaces.lua's own
-- "monitor.added" comment for the amdgpu quirk behind this ("LTTPR count is
-- nonzero but invalid lane count reported" in dmesg) -- can renegotiate down
-- to a 0x0 or tiny fallback mode instead of what monitors.lua/applyDisplayMode
-- actually configured, and just stay there. Confirmed live (2026-09-14): a
-- plain hl.monitor() re-apply of the correct mode -- all a bare `hyprctl
-- reload` does, and all applyDisplayMode() itself does -- left DP-1/DP-2
-- wedged at 0x0 even across several reloads, but disabling the output and
-- re-enabling it with the same mode forced fresh DP link training and
-- recovered both to their real resolution. This automates that fix instead
-- of needing a manual hyprctl/Lua intervention (or a full reboot, which
-- doesn't even reliably clear it, hence the original bug report) every time
-- the dock flaps.
--
-- Skipped entirely while mirroring: hl.get_monitors() hides a mirrored
-- output from its results (see the big comment on otherOutputNames() above),
-- so a 0x0-looking read while mirrorActive is true can't be told apart from
-- "just mirroring" -- there's nothing reliable to check.
--
-- RETRAIN_SETTLE_MS gives Hyprland's own negotiation a moment to finish
-- unaided before checking -- hl.get_monitors() can transiently report 0x0
-- right after a reconnect even when it's about to land correctly on its own
-- (see parseMonitorsConfig's own comment on that same race above), so
-- checking immediately would misfire the retrain on every ordinary
-- reconnect, not just a genuinely wedged one.
local RETRAIN_SETTLE_MS = 1500

-- DISABLE_SETTLE_MS: the gap between disabling the output and re-enabling it
-- has to be real wall-clock time, not just two back-to-back hl.monitor()
-- calls in the same tick. Confirmed live (2026-09-16): calling
-- applyDisplayMode() immediately after disabling (0ms gap, what this used to
-- do) never once produced a working mode -- hyprland.log showed the same
-- "Disabling output DP-1" -> "DP-1 is disabled, releasing crtc" -> "Connector
-- DP-1 disconnected" -> reconnect -> disable again cycle repeating
-- indefinitely, with zero "Modesetting DP-1" lines across the whole session,
-- until it finally settled stuck disabled with no further hotplug to retry
-- it. Manually disabling via `hyprctl eval`, waiting ~5s, then re-enabling
-- with the explicit mode recovered it on the first try. Untested exactly how
-- short a gap still works -- 3s is a middle ground, not a measured minimum.
local DISABLE_SETTLE_MS = 3000

local function retrainIfWedged(name)
    if mirrorActive then return end
    hl.timer(function()
        local m = hl.get_monitor(name)
        local wedged = not m or not m.width or m.width == 0 or not m.height or m.height == 0
        if not wedged then return end -- negotiated fine on its own

        hl.monitor({ output = name, disabled = true })
        hl.timer(function()
            applyDisplayMode(mirrorActive)
        end, { timeout = DISABLE_SETTLE_MS, type = "oneshot" })
    end, { timeout = RETRAIN_SETTLE_MS, type = "oneshot" })
end

-- Covers a dock/monitor already connected at config load (the boot-time
-- case the original bug report hit) in addition to the monitor.added hook
-- below (any later flap, e.g. a dock power-cycle mid-session).
for _, name in ipairs(otherOutputNames()) do
    retrainIfWedged(name)
end

hl.on("monitor.added", function(mon)
    if not extendLayout[mon.name] or mon.name == INTERNAL_PANEL then return end
    retrainIfWedged(mon.name)
end)

hl.bind(mainMod .. " + P", function()
    if not INTERNAL_PANEL then return end
    if #otherOutputNames() == 0 then return end -- nothing to mirror/extend (undocked)

    mirrorActive = not mirrorActive
    saveMirrorActive(mirrorActive)
    applyDisplayMode(mirrorActive)

    -- Windows-11-style transient OSD (DisplayModeOSD.qml), same as the
    -- volume/backlight ones -- there's no PipeWire property or sysfs file to
    -- watch reactively for this, so it's poked directly over IPC instead.
    hl.exec_cmd("quickshell ipc call displaymode pop " .. (mirrorActive and "mirror" or "extend"))
end)

-- locked so it also works from the hyprlock screen (same reasoning as the
-- playerctl bind above) -- hyprlock has no layout-switch bind of its own,
-- but it does listen for the compositor's XKB group-change event and
-- updates its $LAYOUT label / keystroke interpretation from that, so this
-- bind firing while locked is enough to drive it.
hl.bind(mainMod .. " + SPACE", hl.dsp.exec_cmd("hyprctl switchxkblayout current next"), { locked = true }) -- cycle keyboard layout
hl.bind(mainMod .. " + CTRL + SHIFT + R", hl.dsp.exec_cmd("pkill quickshell; quickshell & disown")) -- reload quickshell bar
hl.bind("CTRL + " .. mainMod .. " + I", hl.dsp.exec_cmd("hyprctl dispatch idleinhibit toggle")) -- toggle idle inhibitor
hl.bind(mainMod .. " + C", hl.dsp.exec_cmd("hyprpicker -a")) -- color picker, autocopies hex to clipboard
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd("kitty --class btop -e btop")) -- resource monitor, floated/centered by window_rules.lua
hl.bind(mainMod .. " + SHIFT + V", hl.dsp.exec_cmd("cliphist list | fuzzel --dmenu | cliphist decode | wl-copy")) -- clipboard history picker

-- Screenshots (HyprQuickFrame: https://github.com/Ronin-CK/HyprQuickFrame)
-- -p (explicit path), not -c (named config): our own quickshell config
-- already has a top-level ~/.config/quickshell/shell.qml, and quickshell's
-- own docs say a top-level shell.qml gets registered as the "default"
-- config and disables scanning ANY subdirectories for named configs — -c
-- HyprQuickFrame would never resolve while that file exists. -p bypasses
-- that lookup entirely and just loads the given path directly.
local hqfPath = "$HOME/.config/quickshell/HyprQuickFrame"
hl.bind("Print",         hl.dsp.exec_cmd("quickshell -p " .. hqfPath .. " -n")) -- decides region/window/save/copy on the fly
hl.bind("SHIFT + Print", hl.dsp.exec_cmd("env HQF_MODE=window quickshell -p " .. hqfPath .. " -n"))
hl.bind("CTRL + Print",  hl.dsp.exec_cmd("env HQF_ACTION=temp quickshell -p " .. hqfPath .. " -n")) -- clipboard-only

-- Move focus with mainMod + arrow keys
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

-- Swap active window with adjacent window with mainMod + SHIFT + arrow keys
hl.bind(mainMod .. " + SHIFT + left",  hl.dsp.window.swap({ direction = "left" }))
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.swap({ direction = "right" }))
hl.bind(mainMod .. " + SHIFT + up",    hl.dsp.window.swap({ direction = "up" }))
hl.bind(mainMod .. " + SHIFT + down",  hl.dsp.window.swap({ direction = "down" }))

-- Switch workspaces with mainMod + [1-9, 0], move windows with mainMod +
-- SHIFT(+ALT) + [1-9, 0]: see workspaces.lua, which owns these binds now
-- (dynamic workspace pool -- workspaces.md).

-- Workspace navigation
hl.bind(mainMod .. " + TAB",          hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + SHIFT + TAB",  hl.dsp.focus({ workspace = "e-1" }))
hl.bind(mainMod .. " + CTRL + TAB",   hl.dsp.focus({ workspace = "previous" }))

-- Move current workspace to adjacent monitor
hl.bind(mainMod .. " + SHIFT + ALT + left",  hl.dsp.workspace.move({ monitor = "l" }))
hl.bind(mainMod .. " + SHIFT + ALT + right", hl.dsp.workspace.move({ monitor = "r" }))
hl.bind(mainMod .. " + SHIFT + ALT + up",    hl.dsp.workspace.move({ monitor = "u" }))
hl.bind(mainMod .. " + SHIFT + ALT + down",  hl.dsp.workspace.move({ monitor = "d" }))

-- Focus next / previous monitor
hl.bind("CTRL + ALT + TAB",           hl.dsp.focus({ monitor = "+1" }))
hl.bind("CTRL + ALT + SHIFT + TAB",   hl.dsp.focus({ monitor = "-1" }))

-- Example special workspace (scratchpad)
hl.bind(mainMod .. " + A",         hl.dsp.workspace.toggle_special("A"))
hl.bind(mainMod .. " + SHIFT + A", hl.dsp.window.move({ workspace = "special:A" }))
hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("S"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:S" }))
hl.bind(mainMod .. " + D",         hl.dsp.workspace.toggle_special("D"))
hl.bind(mainMod .. " + SHIFT + D", hl.dsp.window.move({ workspace = "special:D" }))

-- Scroll through existing workspaces with mainMod + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Laptop multimedia keys for volume and LCD brightness
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ 0 && wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true, repeating = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp",  hl.dsp.exec_cmd("brightnessctl -n2 set 5%+"),                      { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown",hl.dsp.exec_cmd("brightnessctl -n2 set 5%-"),                      { locked = true, repeating = true })

-- Requires playerctl
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })
