#!/bin/bash
set -e

# --- 0. Sanitize Environment (CRITICAL FIX) ---
# Ensure Gamescope knows it is the SERVER, not a client.
unset WAYLAND_DISPLAY
unset DISPLAY
unset GDK_BACKEND
unset QT_QPA_PLATFORM

# --- 1. Load Configuration ---
WIDTH=1920
HEIGHT=1080
REFRESH=60
HDR_ENABLED="false"

CONFIG_FILE="/home/steam/.config/display_config"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

echo "--- [Steam Session] Starting ---"
echo "    Resolution: ${WIDTH}x${HEIGHT} @ ${REFRESH} (HDR: $HDR_ENABLED)"

# --- 2. Export Environment Variables ---
export XDG_RUNTIME_DIR=/run/user/1000
export GAMESCOPE_WIDTH="$WIDTH"
export GAMESCOPE_HEIGHT="$HEIGHT"
export WLR_BACKENDS=headless
export UG_MAX_BUFFERS=256

# --- 3. Controller Mappings (Inline) ---
export SDL_GAMECONTROLLERCONFIG="050000004c050000e60c000011810000,PS5 Controller,a:b0,b:b1,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b10,leftshoulder:b4,leftstick:b11,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b12,righttrigger:a5,rightx:a3,righty:a4,start:b9,x:b2,y:b3,platform:Linux,
050000004c050000e60c000000000000,PS5 Controller,a:b0,b:b1,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b10,leftshoulder:b4,leftstick:b11,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b12,righttrigger:a5,rightx:a3,righty:a4,start:b9,x:b2,y:b3,platform:Linux,
030000004c050000e60c000011810000,PS5 Controller,a:b0,b:b1,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b10,leftshoulder:b4,leftstick:b11,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b12,righttrigger:a5,rightx:a3,righty:a4,start:b9,x:b2,y:b3,platform:Linux,
030000004c050000e60c000000000000,PS5 Controller,a:b0,b:b1,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b10,leftshoulder:b4,leftstick:b11,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b12,righttrigger:a5,rightx:a3,righty:a4,start:b9,x:b2,y:b3,platform:Linux,"
echo "    Applied inline controller mapping."

# --- 4. Build Gamescope Arguments ---
GS_ARGS="-e -f -w $WIDTH -h $HEIGHT -W $WIDTH -H $HEIGHT -r $REFRESH --force-grab-cursor"

if [ "$HDR_ENABLED" = "true" ] || [ "$HDR_ENABLED" = "1" ]; then
    GS_ARGS="$GS_ARGS --hdr-enabled --hdr-itm-enable"
else
    GS_ARGS="$GS_ARGS --sdr-gamut-wideness 0"
fi

# --- 5. Execute Gamescope ---
echo "    Executing: gamescope $GS_ARGS"
exec gamescope $GS_ARGS -- steam -gamepadui -noverifyfiles -fulldesktopres
