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

# CHECK: Only restart if something changed
if [ "$REQ_WIDTH" != "$CUR_WIDTH" ] || \
   [ "$REQ_HEIGHT" != "$CUR_HEIGHT" ] || \
   [ "$REQ_REFRESH" != "$CUR_REFRESH" ] || \
   [ "$REQ_HDR" != "$CUR_HDR" ]; then

    echo "    -> Change detected! Updating config and triggering restart." >> $LOGfile
    
    echo "WIDTH=$REQ_WIDTH" > "$CONFIG_FILE"
    echo "HEIGHT=$REQ_HEIGHT" >> "$CONFIG_FILE"
    echo "REFRESH=$REQ_REFRESH" >> "$CONFIG_FILE"
    echo "HDR_ENABLED=$REQ_HDR" >> "$CONFIG_FILE"

    chown steam:steam "$CONFIG_FILE"
    
    # Touch the file to signal entrypoint.sh to restart services
    touch "$TRIGGER_FILE"
else
    echo "    -> Config matches active session. No restart needed." >> $LOGfile
fi
EOF
chmod +x "$SWITCH_SCRIPT"

# 2. Main Config
cat > "$CONF_FILE" <<EOF
[general]
address = 0.0.0.0
upnp = disabled
gamepad = auto
[video]
capture = kms
encoder = nvenc
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
            "detached": [ "$SWITCH_SCRIPT" ],
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
