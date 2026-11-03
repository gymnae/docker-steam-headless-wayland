local width = tonumber(os.getenv("SHW_WIDTH") or "1920") or 1920
local height = tonumber(os.getenv("SHW_HEIGHT") or "1080") or 1080
local refresh = tonumber(os.getenv("SHW_REFRESH") or "60") or 60

local hdrEnabledRaw = (os.getenv("SHW_HDR_ENABLED") or "false"):lower()
local hdrEnabled = hdrEnabledRaw == "true" or hdrEnabledRaw == "1"

local monitorRule = {
    output = "",
    mode = string.format("%dx%d@%d", width, height, refresh),
    position = "auto",
    scale = "1",
}

if hdrEnabled then
    monitorRule.bitdepth = 10
    monitorRule.cm = "hdr"
    monitorRule.sdrbrightness = 1.2
    monitorRule.sdrsaturation = 0.98
end

hl.monitor(monitorRule)

hl.on("hyprland.start", function()
    hl.exec_cmd([[bash -c 'while true; do steam -gamepadui -noverifyfiles -fulldesktopres; sleep 2; pkill -9 -u steam -f "steamwebhelper|steam-runtime"; killall -9 steam steam-runtime-supervisor 2>/dev/null; rm -f /home/steam/.steam/steam.pid /home/steam/.steam/steam.pipe; sleep 2; done']])
    hl.exec_cmd("/usr/local/bin/scripts/steam_guard.sh")
end)

hl.config({
    cursor = {
        no_hardware_cursors = 1,
    },
    input = {
        kb_layout = "us,us,de,de",
        kb_variant = ",euro,,mac",
        kb_options = "grp:alt_shift_toggle",
    },
    general = {
        allow_tearing = true,
        gaps_in = 0,
        gaps_out = 0,
        border_size = 0,
    },
    animations = {
        enabled = false,
    },
    debug = {
        vfr = false,
    },
    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        focus_on_activate = true,
        on_focus_under_fullscreen = 2,
    },
})

-- Steam's on-screen keyboard types into the focused window through XTest, so it must never take
-- focus itself. Steam hides it by moving it, not by closing it, so Hyprland must not place it either.
hl.window_rule({
    name = "steam-keyboard",
    match = {
        title = "^(Steam Keyboard)$",
    },
    float = true,
    no_initial_focus = true,
    pin = true,
})

-- Big Picture stays open, tiled behind the fullscreen game. When the in-game keyboard or overlay
-- is used, Steam activates that window; with misc.focus_on_activate it then takes keyboard focus
-- from the game, so clicks and keyboard text end up in Steam instead of the game.
hl.window_rule({
    name = "steam-no-focus-steal",
    match = {
        class = "^(steam)$",
        title = "^(Steam Big Picture Mode)$",
    },
    focus_on_activate = false,
})

hl.window_rule({
    name = "steam-overlay-float",
    match = {
        class = "^(steamwebhelper)$",
        title = "^(Steam)$",
    },
    float = true,
})

hl.window_rule({
    name = "immediate-for-all-windows",
    match = {
        class = "^(.*)$",
    },
    immediate = true,
})
