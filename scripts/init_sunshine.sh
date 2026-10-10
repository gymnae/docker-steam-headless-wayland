#!/bin/bash
set -e

echo "--- [Sunshine] Configuring ---"

mkdir -p /home/steam/.config/sunshine
CONF_FILE="/home/steam/.config/sunshine/sunshine.conf"
APPS_FILE="/home/steam/.config/sunshine/apps.json"
SWITCH_SCRIPT="/usr/local/bin/switch_display.sh"

# 1. Smart Switch Script (PREVENTS INFINITE LOOPS)
cat > "$SWITCH_SCRIPT" <<'EOF'
#!/bin/bash
LOGfile="/tmp/sunshine_switch.log"
TRIGGER_FILE="/tmp/trigger_restart"
CONFIG_FILE="/home/steam/.config/display_config"

# Defaults if variables are missing
REQ_WIDTH=${SUNSHINE_CLIENT_WIDTH:-1920}
REQ_HEIGHT=${SUNSHINE_CLIENT_HEIGHT:-1080}
REQ_REFRESH=${SUNSHINE_CLIENT_FPS:-60}
REQ_HDR=${SUNSHINE_CLIENT_HDR:-false}

# Read current config to compare
CUR_WIDTH=0
CUR_HEIGHT=0
CUR_REFRESH=0
CUR_HDR="false"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    CUR_WIDTH=${WIDTH:-0}
    CUR_HEIGHT=${HEIGHT:-0}
    CUR_REFRESH=${REFRESH:-0}
    CUR_HDR=${HDR_ENABLED:-false}
fi

echo "[$(date)] Request: ${REQ_WIDTH}x${REQ_HEIGHT} @ ${REQ_REFRESH} (HDR: $REQ_HDR)" >> $LOGfile

# CHECK: Only restart if config changed OR if Hyprland is currently dead
if [ "$REQ_WIDTH" != "$CUR_WIDTH" ] || \
   [ "$REQ_HEIGHT" != "$CUR_HEIGHT" ] || \
   [ "$REQ_REFRESH" != "$CUR_REFRESH" ] || \
   [ "$REQ_HDR" != "$CUR_HDR" ] || \
   ! pgrep -x "Hyprland" > /dev/null; then

    echo "WIDTH=$REQ_WIDTH" > "$CONFIG_FILE"
    echo "HEIGHT=$REQ_HEIGHT" >> "$CONFIG_FILE"
    echo "REFRESH=$REQ_REFRESH" >> "$CONFIG_FILE"
    echo "HDR_ENABLED=$REQ_HDR" >> "$CONFIG_FILE"

    chown steam:steam "$CONFIG_FILE"

    # Live mode switch: a session restart also kills Sunshine, which drops the
    # client that just connected. Only HDR toggles still need a full restart.
    if [ "$REQ_HDR" = "$CUR_HDR" ] && pgrep -x "Hyprland" > /dev/null; then
        HYPRCTL="runuser -u steam -- env XDG_RUNTIME_DIR=/run/user/1000 hyprctl -i 0"
        MODE="${REQ_WIDTH}x${REQ_HEIGHT}@${REQ_REFRESH}"
        echo "    -> Switching live to $MODE" >> $LOGfile
        $HYPRCTL eval "hl.monitor({ output = \"\", mode = \"$MODE\", position = \"auto\", scale = \"1\" })" >> $LOGfile 2>&1
        sleep 1
        # Refresh is not checked: the dummy plug's EDID may not offer it, and Hyprland picks the nearest
        if $HYPRCTL monitors 2>/dev/null | grep -q "^[[:space:]]*${REQ_WIDTH}x${REQ_HEIGHT}@"; then
            echo "    -> Live switch OK: $($HYPRCTL monitors | grep -o '[0-9]*x[0-9]*@[0-9.]*' | head -n1)" >> $LOGfile
            exit 0
        fi
        echo "    -> Live switch failed, falling back to session restart." >> $LOGfile
    fi

    echo "    -> Change detected or session dead! Triggering start." >> $LOGfile
    # Touch the file to signal the supervisor/entrypoint to execute Script 2
    touch "$TRIGGER_FILE"
else
    echo "    -> Config matches and session is active. No restart needed." >> $LOGfile
fi
EOF
chmod +x "$SWITCH_SCRIPT"

# 1.5 Power-Saving Shutdown Script
STOP_SCRIPT="/usr/local/bin/stop_stream.sh"
cat > "$STOP_SCRIPT" <<'EOF'
#!/bin/bash
echo "[$(date)] Moonlight disconnected. Shutting down Wayland and Steam..." >> /tmp/sunshine_switch.log

# Gracefully ask Steam to exit first to prevent save data/cloud sync corruption
killall -15 steam || true
killall -15 steamwebhelper || true

# Give Steam 3 seconds to sync cloud saves
sleep 3

# Kill the compositor, which releases the Nvidia GPU
killall -15 Hyprland || true
EOF
chmod +x "$STOP_SCRIPT"

# 2. Main Config
cat > "$CONF_FILE" <<EOF
[general]
address = 0.0.0.0
upnp = disabled
# Emulate a DualSense: unlike the Xbox pad it carries gyro, touchpad and rumble, and Steam
# treats it as a full Steam Input controller. "auto" falls back to Xbox whenever the client
# reports an Xbox-style pad, e.g. a Steam Deck with Steam Input enabled for Moonlight.
gamepad = ${SUNSHINE_GAMEPAD:-ds5}
# Keep the pad's MAC stable across sessions so Steam recognizes it and keeps its layouts
ds5_inputtino_randomize_mac = disabled
# Headless: no tray/notification host. Newer Sunshine runs the tray loop on the
# main thread and exits when tray init fails, so it must be disabled.
system_tray = disabled
[video]
capture = kms
encoder = nvenc
# P3: better quality than the default P1 for ~1-2ms extra encode time
nvenc_preset = 3
# Better flat areas/gradients at low bitrates, small encode cost
nvenc_spatial_aq = enabled
EOF
chown steam:steam "$CONF_FILE"

# 3. Apps
cat > "$APPS_FILE" <<EOF
{
    "env": { "PATH": "$PATH" },
    "apps": [
        {
            "name": "Steam Gaming",
            "output": "sunshine.log",
            "prep-cmd": [
                {
                    "do": "$SWITCH_SCRIPT",
                    "undo": "$STOP_SCRIPT"
                }
            ],
            "image-path": ""
        }
    ]
}
EOF
chown steam:steam "$APPS_FILE"

# 4. Permissions
rm -rf /root/.config/sunshine
mkdir -p /root/.config
ln -sfn /home/steam/.config/sunshine /root/.config/sunshine

if [ -f /home/steam/.config/pulse/cookie ]; then
    mkdir -p /root/.config/pulse
    cp /home/steam/.config/pulse/cookie /root/.config/pulse/cookie
fi
