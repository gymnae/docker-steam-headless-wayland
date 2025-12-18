#!/bin/bash
# /usr/local/bin/steam-session.sh

# Redirect logs
exec > /tmp/session.log 2>&1

# 1. Resolution Negotiation
CLIENT_W="${SUNSHINE_CLIENT_WIDTH:-1920}"
CLIENT_H="${SUNSHINE_CLIENT_HEIGHT:-1080}"
CLIENT_FPS="${SUNSHINE_CLIENT_FPS:-60}"

echo "Starting Session: ${CLIENT_W}x${CLIENT_H} @ ${CLIENT_FPS}Hz"

# 2. Conditional HDR
HDR_ARGS=""
HDR_ENV=""

if [[ "${SUNSHINE_CLIENT_HDR}" == "true" ]]; then
    echo "HDR Requested."
    # --hdr-enabled: Enables HDR on the compositor
    # --hdr-debug-force-output: Useful for headless backends to force metadata
    HDR_ARGS="--hdr-enabled --hdr-debug-force-output"
    HDR_ENV="env DXVK_HDR=1 ENABLE_GAMESCOPE_WSI=1 PROTON_ENABLE_HDR=1"
fi

# 3. Execution
# -W/-H: Sets the virtual resolution to match the client exactly.
# --force-grab-cursor: Essential for remote input injection.
echo "Launching Gamescope..."
exec gamescope \
    -W "$CLIENT_W" -H "$CLIENT_H" \
    -w "$CLIENT_W" -h "$CLIENT_H" \
    -r "$CLIENT_FPS" \
    --force-grab-cursor \
    $HDR_ARGS \
    -- \
    $HDR_ENV \
    steam -noverifyfiles
