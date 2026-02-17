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


# 1. Detect the GPU Name
# We grep for 'deviceName', remove software renderers, and use sed to strip the label.
# This variable naturally handles spaces because it captures the whole line output.
RAW_GPU_LINE=$(vulkaninfo | grep "deviceName" | grep -v -E "llvmpipe|lavapipe|softpipe" | head -n1)

# 2. Extract just the name (removing "deviceName = ")
# We use quotes around "$RAW_GPU_LINE" to preserve spaces.
GPU_NAME=$(echo "$RAW_GPU_LINE" | sed 's/.*deviceName *= //')

# 3. Check and Export
if [ -n "$GPU_NAME" ]; then
    echo "Universal GPU Detection: Found '$GPU_NAME'"
    # The quotes here are critical!
    export DXVK_FILTER_DEVICE_NAME="$GPU_NAME"
else
    echo "Universal GPU Detection: No hardware GPU found."
    unset DXVK_FILTER_DEVICE_NAME
fi

# --- 2. Export Environment Variables ---
export XDG_RUNTIME_DIR=/run/user/1000
export GAMESCOPE_WIDTH="$WIDTH"
export GAMESCOPE_HEIGHT="$HEIGHT"
export WLR_BACKENDS=drm,libinput
export UG_MAX_BUFFERS=256
export PROTON_NO_ESYNC=1

# --- CRITICAL NVIDIA STABILITY FIXES ---
# 1. Force Linear Memory (Fixes Black Screen / Double Buffer error)
export WLR_DRM_NO_MODIFIERS=1

# 2. Nvidia de-sync issuse 
export __GL_THREADED_OPTIMIZATIONS=0
export __GL_SYNC_TO_VBLANK=0

# 3. Disable WSI (Fixes Launcher Hangs)
export ENABLE_GAMESCOPE_WSI=0

# 4. Enable NVIDIA API for Proton (Stability/Performance)
export PROTON_ENABLE_NVAPI=1
export DXVK_ENABLE_NVAPI=1

# 3. Force Gamescope to use Vulkan Renderer (Stability)
export WLR_RENDERER=vulkan

# 4. Disable WSI (Fixes Launcher Hangs)
export ENABLE_GAMESCOPE_WSI=0

# 5. Disable Steam Overlay (Fixes ld.so errors and render conflicts)
export STEAM_DISABLE_GAME_OVERLAY=1

# --- CRITICAL AUDIO FIXES ---
# Force PulseAudio driver for everything
export SDL_AUDIODRIVER=pulse
export ALSOFT_DRIVERS=pulse
export PULSE_SERVER=unix:${XDG_RUNTIME_DIR}/pulse/native

# Set latency to match the "min-quantum" we set in init_audio.sh
export PIPEWIRE_LATENCY="256/48000"
export PULSE_LATENCY_MSEC=60


# --- 3. Controller Mappings (Inline) ---
export SDL_GAMECONTROLLERCONFIG="050000004c050000e60c000011810000,PS5 Controller,a:b0,b:b1,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b10,leftshoulder:b4,leftstick:b11,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b12,righttrigger:a5,rightx:a3,righty:a4,start:b9,x:b2,y:b3,platform:Linux,
050000004c050000e60c000000000000,PS5 Controller,a:b0,b:b1,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b10,leftshoulder:b4,leftstick:b11,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b12,righttrigger:a5,rightx:a3,righty:a4,start:b9,x:b2,y:b3,platform:Linux,
030000004c050000e60c000011810000,PS5 Controller,a:b0,b:b1,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b10,leftshoulder:b4,leftstick:b11,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b12,righttrigger:a5,rightx:a3,righty:a4,start:b9,x:b2,y:b3,platform:Linux,
030000004c050000e60c000000000000,PS5 Controller,a:b0,b:b1,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b10,leftshoulder:b4,leftstick:b11,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b12,righttrigger:a5,rightx:a3,righty:a4,start:b9,x:b2,y:b3,platform:Linux,"

# --- 4. Build Gamescope Arguments ---
GS_ARGS="-e -f -w $WIDTH -h $HEIGHT -W $WIDTH -H $HEIGHT -r $REFRESH --force-grab-cursor"

if [ "$HDR_ENABLED" = "true" ] || [ "$HDR_ENABLED" = "1" ]; then
    GS_ARGS="$GS_ARGS --hdr-enabled --hdr-itm-enable"
else
    GS_ARGS="$GS_ARGS"
fi

# --- 5. Execute Gamescope ---
echo "    Executing: gamescope $GS_ARGS"
exec gamescope $GS_ARGS -- steam -gamepadui -noverifyfiles -fulldesktopres
