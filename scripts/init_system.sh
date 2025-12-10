#!/bin/bash
set -e

echo "--- [System] Initializing Core Services ---"

# 1. RTKit User
if ! id -u rtkit >/dev/null 2>&1; then
    useradd -r -d /proc -s /sbin/nologin rtkit
fi

# 2. Machine ID (Required for DBus)
if [ ! -f /etc/machine-id ]; then
    dbus-uuidgen > /etc/machine-id
fi
mkdir -p /var/lib/dbus
dbus-uuidgen > /var/lib/dbus/machine-id

# 3. DBus
mkdir -p /run/dbus
rm -f /run/dbus/pid
dbus-daemon --system --fork
echo "System DBus Started."

# 4. Session DBus
echo "Starting Session DBus..."
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
su - steam -c "dbus-daemon --session --address=$DBUS_SESSION_BUS_ADDRESS --fork --nopidfile"
sleep 1

# 5. RTKit Daemon
echo "Starting RTKit..."
if [ -x /usr/lib/rtkit-daemon ]; then
    /usr/lib/rtkit-daemon --our-realtime-priority=90 --max-realtime-priority=85 &
fi

# 6. UDev
if [ -x /usr/lib/systemd/systemd-udevd ]; then
    echo "Starting udevd..."
    /usr/lib/systemd/systemd-udevd --daemon
    udevadm trigger
fi

# 7. Seatd
echo "Starting seatd..."
seatd & 
export LIBSEAT_BACKEND=seatd
sleep 1
chmod 777 /run/seatd.sock

# 8. Localization (NEW)
if [ -n "$GENERATE_LOCALE" ]; then
    echo "Generating Locale: $GENERATE_LOCALE"
    sed -i "s/# $GENERATE_LOCALE/$GENERATE_LOCALE/" /etc/locale.gen
    locale-gen
    export LANG="$GENERATE_LOCALE"
    export LC_ALL="$GENERATE_LOCALE"
fi

if [ -n "$KEYBOARD_LAYOUT" ]; then
    echo "Setting Keyboard Layout: $KEYBOARD_LAYOUT"
    export XKB_DEFAULT_LAYOUT="$KEYBOARD_LAYOUT"
    export XKB_DEFAULT_VARIANT="${KEYBOARD_VARIANT:-}"
fi
