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

-- Frosted-glass quickshell menus (see look_and_feel.lua's blur block and
-- quickshell/modules/Theme.qml's glassAlpha). Blur is on globally only for
-- these: no application window is ever blurred.
hl.window_rule({
    name    = "no-window-blur",
    match   = { class = ".*" },
    no_blur = true,
})

-- Launcher, notification center, toasts and OSDs (quickshell sets
-- WlrLayershell.namespace "sichos-glass" on each). These are mostly fully
-- transparent windows with a translucent card in them -- the launcher and
-- notification center are whole-screen with a 0.35-alpha dimmed backdrop --
-- so ignore_alpha limits the blur to pixels at least this opaque: the cards
-- (Theme.glassAlpha, 0.55), not the backdrop or the empty window around a
-- card. blur_popups covers the launcher's own popup children.
hl.layer_rule({
    name         = "sichos-glass-blur",
    match        = { namespace = "^sichos-glass$" },
    blur         = true,
    blur_popups  = true,
    ignore_alpha = 0.45,
})

-- hyprshutdown's whole-screen backdrop (hyprtoolkit.conf's translucent
-- `background`): frosted like the cards above. Its app list draws straight
-- on that backdrop with no fill of its own, so without blur the windows
-- behind bleed through the text.
hl.layer_rule({
    name  = "hyprshutdown-blur",
    match = { namespace = "^hyprshutdown$" },
    blur  = true,
})

-- The bar itself is never blurred (it's either fully transparent or the
-- 0.8/1.0 solid it's always been), but its popups -- every bar menu,
-- the workspace menu, tooltips -- are, same frosted cards as above.
hl.layer_rule({
    name         = "sichos-bar-popups-blur",
    match        = { namespace = "^sichos-bar$" },
    blur_popups  = true,
    ignore_alpha = 0.45,
})

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

-- The terminal (programs.terminal) only fades in and out, no pop-in scaling:
-- "popin 100%" starts and ends at full size, leaving just fadeIn/fadeOut.
-- Plain kitty only -- the btop/sichos-info kitty windows have their own
-- classes and keep the default animation.
hl.window_rule({
    name  = "terminal-fade-only",
    match = { class = "^kitty$" },

    animation = "popin 100%",
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

-- Float and center the "Update All" console (System Update widget's popup,
-- quickshell/modules/SystemUpdate.qml), same treatment as wlctl above.
hl.window_rule({
    name  = "float-center-update-console",
    match = { class = "sichos-update-console" },

    float  = true,
    center = true,
    size   = "monitor_w*0.8 monitor_h*0.8",
})

-- Float Telegram's media viewer (opened by clicking a photo/video) instead
-- of letting it tile. Confirmed via `hyprctl clients -j` it's a genuine
-- separate toplevel (class "org.telegram.desktop", title "Media viewer") —
-- it does request native fullscreen on its own (fullscreen:2), but while
-- tiled Hyprland still reserves its tile slot underneath that, which is why
-- the main Telegram window visibly shrank/reflowed (1280x1410 -> 1280x705)
-- the instant the viewer opened, and reflows back on close. Floating removes
-- it from the tiling grid entirely; size+center below make it cover the
-- whole monitor so it still reads as fullscreen, and no_shadow drops the
-- floating-window shadow that would otherwise ring it. (No "no_border" field
-- exists on this Lua binding — confirmed against /usr/bin/Hyprland's own
-- rule-field table; only no_shadow/no_blur/no_dim etc. are real.)
hl.window_rule({
    name  = "float-fullscreen-telegram-media-viewer",
    match = { class = "org.telegram.desktop", title = "^Media viewer$" },

    float     = true,
    center    = true,
    size      = "monitor_w monitor_h",
    no_shadow = true,
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

