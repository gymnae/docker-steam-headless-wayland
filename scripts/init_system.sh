#!/bin/bash
set -e

echo "--- [System] Initializing Core Services ---"

# 1. Users & Groups
if ! id -u rtkit >/dev/null 2>&1; then useradd -r -d /proc -s /sbin/nologin rtkit; fi
usermod -aG video,input,audio,render steam

# 2. Machine ID
if [ ! -f /etc/machine-id ]; then dbus-uuidgen > /etc/machine-id; fi
mkdir -p /var/lib/dbus
dbus-uuidgen > /var/lib/dbus/machine-id

# 1. Grab the numerical GIDs of the mounted devices
HOST_VIDEO_GID=$(stat -c "%g" /dev/dri/card1 2>/dev/null || stat -c "%g" /dev/dri/card0 2>/dev/null || echo "39")
HOST_RENDER_GID=$(stat -c "%g" /dev/dri/renderD128 2>/dev/null || echo "105")

# 2. Create dummy groups with those exact IDs and add the steam user
if [ -n "$HOST_VIDEO_GID" ]; then
    groupadd -g $HOST_VIDEO_GID host_video 2>/dev/null || true
    usermod -aG $HOST_VIDEO_GID steam
fi

if [ -n "$HOST_RENDER_GID" ]; then
    groupadd -g $HOST_RENDER_GID host_render 2>/dev/null || true
    usermod -aG $HOST_RENDER_GID steam
fi

# 3. DBus
mkdir -p /run/dbus
rm -f /run/dbus/pid
dbus-daemon --system --fork
echo "System DBus Started."

# 4. Session DBus
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
su - steam -c "dbus-daemon --session --address=$DBUS_SESSION_BUS_ADDRESS --fork --nopidfile"
sleep 1

# 5. Udev
if [ -x /usr/lib/systemd/systemd-udevd ]; then 
    echo "Starting udevd..."
    /usr/lib/systemd/systemd-udevd --daemon
    udevadm trigger
fi

# 6. Global Permissions (CRITICAL FIX FOR HYPRLAND)
# We must unlock the /dev/nvidia* devices so the user-space driver can talk to the kernel.
chmod 666 /dev/uinput /dev/input/event* /dev/dri/card* /dev/dri/renderD* /dev/nvidia* 2>/dev/null || true
chown root:video /dev/input/event* 2>/dev/null || true

# 7. Localization
if [ -n "$GENERATE_LOCALE" ]; then
    sed -i "s/# $GENERATE_LOCALE/$GENERATE_LOCALE/" /etc/locale.gen
    locale-gen
    export LANG="$GENERATE_LOCALE"
fi

# 8. PAM LIMITS FIX
echo "Applying PAM Limits for steam user..."
cat >> /etc/security/limits.conf <<EOF
steam    soft    rtprio    99
steam    hard    rtprio    99
steam    soft    memlock   unlimited
steam    hard    memlock   unlimited
steam    soft    nice      -20
steam    hard    nice      -20
EOF
echo "session required pam_limits.so" >> /etc/pam.d/su