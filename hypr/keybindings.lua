---------------------
---- KEYBINDINGS ----
---------------------

local programs = require("programs")

local mainMod = "SUPER" -- Sets "Windows" key as main modifier

-- Laptop lid switch handling. Closing the lid doesn't disconnect eDP-1 (the
-- near-universal kernel name for a built-in panel) the way unplugging a
-- monitor does, so Hyprland keeps treating it as a live output even though
-- nothing is visible. systemd-logind's own defaults already do the right
-- thing for suspend (HandleLidSwitch=suspend when undocked,
-- HandleLidSwitchDocked=ignore -- which per `man logind.conf` also covers
-- "more than one display connected", not just an actual docking station --
-- so a lid close with an external monitor attached doesn't suspend at all);
-- what's missing is Hyprland disabling the now-invisible internal panel in
-- that docked case, so windows/workspaces stop landing on it. Device
-- confirmed present as "Lid Switch" via `hyprctl devices` and the bind
-- syntax verified live via `hyprctl eval` before adding this. Harmless
-- no-op on any machine without a lid switch (desktops).
hl.bind("switch:on:Lid Switch", function()
    hl.monitor({ output = "eDP-1", disabled = true })
end)
hl.bind("switch:off:Lid Switch", function()
    hl.monitor({ output = "eDP-1", disabled = false })
end)

-- Example binds, see https://wiki.hypr.land/Configuring/Basics/Binds/ for more
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(programs.terminal))
hl.bind(mainMod .. " + SHIFT + Return", hl.dsp.exec_cmd(programs.browser))
local closeWindowBind = hl.bind(mainMod .. " + W", hl.dsp.window.close())
-- closeWindowBind:set_enabled(false)
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd("hyprshutdown"))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(programs.fileManager))
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.exec_cmd(programs.fileManager))
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen({ action = "toggle" }))
hl.bind(mainMod .. " + Z", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true }) -- requires playerctl, see multimedia keys below; locked so it also works from the hyprlock screen
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("hyprlock"))
hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd("quickshell ipc call launcher toggleApps")) -- quickshell launcher: apps only
hl.bind(mainMod .. " + SHIFT + Q", hl.dsp.exec_cmd("quickshell ipc call launcher toggleFull")) -- quickshell launcher: full root menu (Apps/Toggles/Power)
hl.bind(mainMod .. " + SHIFT + H", hl.dsp.exec_cmd("quickshell ipc call hdr toggle")) -- toggle HDR (only on monitors picked in the bar's HDR popup, see HdrSettings.qml)
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))    -- dwindle only
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
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true, repeating = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp",  hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"),                  { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown",hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"),                  { locked = true, repeating = true })

-- Requires playerctl
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })
