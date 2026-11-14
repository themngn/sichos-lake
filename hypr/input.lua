---------------
---- INPUT ----
---------------

-- Pen tablet settings from the Control Center's Pen tablet page
-- (quickshell/modules/TabletSettings.qml, which also applies them live and
-- precomputes the active area, in mm, from the tablet's size -- this side
-- just reads the numbers). No file = Hyprland's defaults: the whole tablet
-- over every monitor.
local tablet = (function()
    local f = io.open(os.getenv("HOME") .. "/.config/quickshell/tablet.json", "r")
    local s = ""
    if f then
        s = f:read("*a") or ""
        f:close()
    end
    local function num(key, default)
        return tonumber(s:match('"' .. key .. '"%s*:%s*(%-?[%d%.]+)')) or default
    end
    local function bool(key)
        return s:match('"' .. key .. '"%s*:%s*true') ~= nil
    end
    local a = {}
    for n in (s:match('"activeArea"%s*:%s*%[([^%]]*)%]') or ""):gmatch("%-?[%d%.]+") do
        a[#a + 1] = tonumber(n)
    end
    if #a ~= 4 then a = { 0, 0, 0, 0 } end
    return {
        output = s:match('"output"%s*:%s*"([%w%-]*)"') or "",
        -- Same numbers as monitor transforms: 1 = 90°, 2 = 180°, 3 = 270°.
        transform = math.floor(num("rotation", 0) / 90) % 4,
        relative = bool("relative"),
        hideCursor = bool("hideCursor"),
        pressureMin = num("pressureMin", 0),
        pressureMax = num("pressureMax", 1),
        area = a,
    }
end)()

hl.config({
    input = {
        kb_layout  = "us,ua",
        kb_variant = "",
        kb_model   = "",
        kb_options = "",
        kb_rules   = "",

        follow_mouse = 1,

        sensitivity = 0, -- -1.0 - 1.0, 0 means no modification.

        touchpad = {
            natural_scroll = true,
        },

        tablet = {
            output               = tablet.output,
            transform            = tablet.transform,
            relative_input       = tablet.relative,
            active_area_size     = { tablet.area[1], tablet.area[2] },
            active_area_position = { tablet.area[3], tablet.area[4] },
        },

        tablettool = {
            pressure_range_min = tablet.pressureMin,
            pressure_range_max = tablet.pressureMax,
        },
    },

    cursor = {
        hide_on_tablet = tablet.hideCursor,
    },
})

hl.gesture({
    fingers = 3,
    direction = "horizontal",
    action = "workspace"
})

-- Example per-device config
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Devices/ for more
hl.device({
    name        = "epic-mouse-v1",
    sensitivity = -0.5,
})
