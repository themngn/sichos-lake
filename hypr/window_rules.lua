--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------

-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/
-- and https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/

-- Example window rules that are useful

local suppressMaximizeRule = hl.window_rule({
    -- Ignore maximize requests from all apps. You'll probably like this.
    name  = "suppress-maximize-events",
    match = { class = ".*" },

    suppress_event = "maximize",
})
-- suppressMaximizeRule:set_enabled(false)

hl.window_rule({
    -- Fix some dragging issues with XWayland
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },

    no_focus = true,
})

-- Layer rules also return a handle.
-- local overlayLayerRule = hl.layer_rule({
--     name  = "no-anim-overlay",
--     match = { namespace = "^my-overlay$" },
--     no_anim = true,
-- })
-- overlayLayerRule:set_enabled(false)

-- Hyprland-run windowrule
hl.window_rule({
    name  = "move-hyprland-run",
    match = { class = "hyprland-run" },

    move  = "20 monitor_h-120",
    float = true,
})

-- Float and center the impala wifi TUI (launched from the quickshell bar)
hl.window_rule({
    name  = "float-center-wlctl",
    match = { class = "wlctl" },

    float  = true,
    center = true,
    -- Percent strings ("80% 80%") are silently ignored by this rule engine's
    -- size field; monitor_w/monitor_h arithmetic (as used by move= elsewhere
    -- in this file) is what actually resizes the window.
    size   = "monitor_w*0.8 monitor_h*0.8",
})

-- Float and center pavucontrol (opened by right-clicking the volume module
-- in the quickshell bar), same size/position treatment as wlctl above.
hl.window_rule({
    name  = "float-center-pavucontrol",
    match = { class = "org.pulseaudio.pavucontrol" },

    float  = true,
    center = true,
    size   = "monitor_w*0.8 monitor_h*0.8",
})

-- Float and center the fastfetch "Info" kitty window (launcher root menu),
-- same treatment as wlctl above.
hl.window_rule({
    name  = "float-center-info",
    match = { class = "sichos-info" },

    float  = true,
    center = true,
    size   = "monitor_w*0.8 monitor_h*0.8",
})

-- Float and center the btop resource monitor (SUPER+B), same treatment as wlctl above.
hl.window_rule({
    name  = "float-center-btop",
    match = { class = "btop" },

    float  = true,
    center = true,
    size   = "monitor_w*0.8 monitor_h*0.8",
})

-- Float, pin (stays visible across every workspace), and corner-position
-- Firefox's video Picture-in-Picture popup, top-right with a small margin.
hl.window_rule({
    name  = "float-pin-firefox-pip",
    -- This Fedora build's Firefox reports class "org.mozilla.firefox", not
    -- the plain "firefox" other distros/flatpaks use — confirmed via
    -- `hyprctl clients -j` (matching on the older name silently never fired).
    -- Plain "-" here, not Lua-pattern-escaped "%-": this match string goes
    -- to Hyprland's own regex matcher, where "-" is a literal character
    -- outside brackets — the "%-" was being read as a literal percent sign
    -- instead, so the title never matched at all.
    match = { class = "org.mozilla.firefox", title = "^Picture-in-Picture$" },

    float = true,
    pin   = true,
    size  = "500 281",          -- 400x225 + 25%, still ~16:9
    move  = "monitor_w-540 40", -- 500 + 40 margin from the right; 40 down from the top
})

