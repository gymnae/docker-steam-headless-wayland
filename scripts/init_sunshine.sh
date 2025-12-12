#!/bin/bash
set -e

echo "--- [Sunshine] Configuring ---"

mkdir -p /home/steam/.config/sunshine
CONF_FILE="/home/steam/.config/sunshine/sunshine.conf"
APPS_FILE="/home/steam/.config/sunshine/apps.json"

# 1. Main Config
if [ ! -f "$CONF_FILE" ]; then
    cat > "$CONF_FILE" <<EOF
[general]
address = 0.0.0.0
upnp = disabled
gamepad = auto
[video]
capture = kms
encoder = nvenc
EOF
fi
chown steam:steam "$CONF_FILE"

# 2. Applications (The Toggle Logic)
# 'prep-cmd' runs before the stream starts. We use it to switch modes.
# We set 'image-path' to empty for now to force Moonlight to generate a text-based placeholder if no image is found,
# which helps distinguish them if you don't have custom cover art.

cat > "$APPS_FILE" <<EOF
{
    "env": {
        "PATH": "$PATH"
    },
    "apps": [
        {
            "name": "Steam SDR",
            "output": "sunshine-sdr.log",
            "detached": [
                "/bin/bash -c 'echo -n SDR > /home/steam/.config/display_mode && pkill gamescope'"
            ],
            "image-path": ""
        },
        {
            "name": "Steam HDR",
            "output": "sunshine-hdr.log",
            "detached": [
                "/bin/bash -c 'echo -n HDR > /home/steam/.config/display_mode && pkill gamescope'"
            ],
            "image-path": ""
        }
    ]
}
EOF
chown steam:steam "$APPS_FILE"

# 3. Link for Root
rm -rf /root/.config/sunshine
mkdir -p /root/.config
ln -sfn /home/steam/.config/sunshine /root/.config/sunshine

# 4. Pulse Cookie
if [ -f /home/steam/.config/pulse/cookie ]; then
    mkdir -p /root/.config/pulse
    cp /home/steam/.config/pulse/cookie /root/.config/pulse/cookie
fi
