#!/bin/bash
set -e

# --- 0. Sanitize Environment ---
unset WAYLAND_DISPLAY
unset DISPLAY
unset GDK_BACKEND
unset QT_QPA_PLATFOR

export HOME=/home/steam
# --- 1. Load Configuration ---
WIDTH=1920
HEIGHT=1080
REFRESH=60
HDR_ENABLED="false"

CONFIG_FILE="/home/steam/.config/display_config"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

echo "--- [Steam Session] Starting Hyprland Compositor ---"
echo "    Target Resolution: ${WIDTH}x${HEIGHT} @ ${REFRESH} (HDR: $HDR_ENABLED)"

# --- 2. Universal GPU Detection ---
RAW_GPU_LINE=$(vulkaninfo 2>/dev/null | grep "deviceName" | grep -v -E "llvmpipe|lavapipe|softpipe" | head -n1 || true)
GPU_NAME=$(echo "$RAW_GPU_LINE" | sed 's/.*deviceName *= //' || true)

if [ -n "$GPU_NAME" ]; then
    echo "    Universal GPU Detection: Found '$GPU_NAME'"
    export DXVK_FILTER_DEVICE_NAME="$GPU_NAME"
else
    echo "    Universal GPU Detection: No hardware GPU found."
    unset DXVK_FILTER_DEVICE_NAME
fi

# DUAL GPU FIX: Force NVIDIA for Hyprland (Prevents Intel iGPU from crashing the compositor)
NVIDIA_CARD=$(grep -l "0x10de" /sys/class/drm/card*/device/vendor 2>/dev/null | cut -d '/' -f 5 | head -n 1 || true)
if [ -n "$NVIDIA_CARD" ]; then
    echo "    Multi-GPU Fix: Forcing Compositor to use NVIDIA (/dev/dri/$NVIDIA_CARD)"
    export AQ_DRM_DEVICES="/dev/dri/$NVIDIA_CARD"
    export WLR_DRM_DEVICES="/dev/dri/$NVIDIA_CARD"
fi

# --- 3. Environment Variables ---
export XDG_RUNTIME_DIR=/run/user/1000
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=Hyprland

export LIBSEAT_BACKEND=seatd
export XDG_SEAT=seat0

# NVIDIA Environment Variables
export GBM_BACKEND=nvidia-drm
export LIBVA_DRIVER_NAME=nvidia
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export WLR_NO_HARDWARE_CURSORS=1
export PROTON_ENABLE_NVAPI=1
export DXVK_ENABLE_NVAPI=1

# --- 3. Controller Mappings (Inline) ---
export SDL_GAMECONTROLLERCONFIG="050000004c050000e60c000011810000,PS5 Controller,a:b0,b:b1,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b10,leftshoulder:b4,leftstick:b11,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b12,righttrigger:a5,rightx:a3,righty:a4,start:b9,x:b2,y:b3,platform:Linux,
050000004c050000e60c000000000000,PS5 Controller,a:b0,b:b1,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b10,leftshoulder:b4,leftstick:b11,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b12,righttrigger:a5,rightx:a3,righty:a4,start:b9,x:b2,y:b3,platform:Linux,
030000004c050000e60c000011810000,PS5 Controller,a:b0,b:b1,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b10,leftshoulder:b4,leftstick:b11,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b12,righttrigger:a5,rightx:a3,righty:a4,start:b9,x:b2,y:b3,platform:Linux,
030000004c050000e60c000000000000,PS5 Controller,a:b0,b:b1,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b10,leftshoulder:b4,leftstick:b11,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b12,righttrigger:a5,rightx:a3,righty:a4,start:b9,x:b2,y:b3,platform:Linux,"

# --- 5. Generate Hyprland Monitor Config ---
mkdir -p /home/steam/.config/hypr

if [ "$HDR_ENABLED" = "true" ] || [ "$HDR_ENABLED" = "1" ]; then
    echo "monitor=,${WIDTH}x${HEIGHT}@${REFRESH},auto,1,bitdepth,10,cm, hdr, sdrbrightness, 1.2, sdrsaturation, 0.98" > /home/steam/.config/hypr/monitor.conf
else
    echo "monitor=,${WIDTH}x${HEIGHT}@${REFRESH},auto,1" > /home/steam/.config/hypr/monitor.conf
fi

if [ -f "/usr/local/bin/scripts/hyprland.conf" ]; then
    cp /usr/local/bin/scripts/hyprland.conf /home/steam/.config/hypr/hyprland.conf
fi

# --- 6. Execute Hyprland ---
exec start-hyprland -c /home/steam/.config/hypr/hyprland.conf
