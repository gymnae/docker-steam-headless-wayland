#!/bin/bash
set -e

# --- 1. User & Group Configuration ---
USER_ID=${PUID:-1000}
GROUP_ID=${PGID:-1000}
USER_NAME="steam"

echo "⚙️ Configuring user ${USER_NAME}..."
if [ $(getent group ${USER_NAME} | cut -d: -f3) != ${GROUP_ID} ]; then
    groupmod -g ${GROUP_ID} ${USER_NAME}
fi
if [ $(id -u ${USER_NAME}) != ${USER_ID} ]; then
    usermod -u ${USER_ID} -g ${GROUP_ID} ${USER_NAME}
fi

# Permissions
chown -R ${USER_NAME}:${USER_NAME} /home/steam
mkdir -p /run/user/${USER_ID} && chown -R ${USER_NAME}:${USER_NAME} /run/user/${USER_ID}
chmod 700 /run/user/${USER_ID}

# --- 2. Hardware Setup ---

# A. Start udevd (Input Hotplug)
echo "🔌 Starting udev daemon..."
if [ -x /usr/lib/systemd/systemd-udevd ]; then
    /usr/lib/systemd/systemd-udevd --daemon
    udevadm trigger
fi

# B. Start seatd (GPU/Input Access)
# Create dummy TTY to satisfy seatd
if [ ! -e /dev/tty1 ]; then
    echo "🔧 Creating dummy /dev/tty1 for seatd..."
    mknod -m 666 /dev/tty1 c 4 1
fi

echo "💺 Starting seatd..."
seatd -g video &
sleep 1

# C. Permissions
if [ -e /dev/uinput ]; then chmod 666 /dev/uinput; fi
if [ -d /dev/input ]; then chmod -R 777 /dev/input; fi
if [ -d /dev/dri ]; then
    chown -R root:video /dev/dri
    chmod -R 775 /dev/dri
    usermod -aG video,render,input ${USER_NAME} || true
fi

# --- 3. Environment Variables (Includes HDR) ---
export XDG_RUNTIME_DIR="/run/user/${USER_ID}"
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=sway
export LIBSEAT_BACKEND=seatd
export WLR_BACKENDS=headless,libinput
export DISPLAY=:0
export WAYLAND_DISPLAY=wayland-1
export STEAM_REMOTE_PLAY=1
export PROTON_ENABLE_WAYLAND=1
export SDL_VIDEODRIVER=wayland

## HDR Environment Variables
# broken for now
#export WLR_RENDERER=vulkan
#export DXVK_HDR=1
#export ENABLE_GAMESCOPE_WSI=1

# --- 4. Generate Sway Config (ROBUST GAME RULES) ---
mkdir -p /home/steam/.config/sway
cat <<EOF > "/home/steam/.config/sway/config"
# 1. Output Configuration (10-bit HDR attempt)
output HEADLESS-1 {
    mode 1920x1080@60Hz
    bg #000000 solid_color
    render_bit_depth 10
}

# 2. Input Configuration (Allow all devices)
input * {
    xkb_layout "us"
}

# 3. Visuals (No Borders)
default_border none
default_floating_border none
font pango:monospace 1

# 4. CRITICAL: Window Rules for Games & Popups

# A. Steam Big Picture (Force Fullscreen)
for_window [class="^Steam$" title="^Steam$"] fullscreen enable inhibit_idle open

# B. Games (Force Fullscreen & Focus)
# Matches native games and most Proton wrappers
for_window [class="^steam_app_"] fullscreen enable focus inhibit_idle open

# C. Wine/Proton Edge Cases
# Some launchers show up as "wine" or "explorer.exe". We force them fullscreen.
for_window [class="(?i)wine"] fullscreen enable focus
for_window [class="(?i)explorer.exe"] fullscreen enable focus
for_window [class="(?i)proton"] fullscreen enable focus

# D. Popups & Dialogs (Force Floating)
# Prevents install dialogs from splitting the screen
for_window [window_role="pop-up"] floating enable
for_window [window_role="bubble"] floating enable
for_window [window_role="dialog"] floating enable
for_window [title="^Steam - Self Updater$"] floating enable
for_window [class="^steam_proton_wrapper"] floating enable

# E. Focus Behavior
# Ensure new windows (launchers) steal focus from Big Picture
focus_on_window_activation focus

# 5. Auto-Start Apps
exec steam -gamepadui -noverifyfiles
exec sunshine
EOF
chown -R ${USER_NAME}:${USER_NAME} /home/steam/.config

# --- 5. Service Launch Sequence ---

DBUS_ADDR="unix:path=/run/user/${USER_ID}/bus"
run_services() {
    su - ${USER_NAME} -c "export XDG_RUNTIME_DIR=/run/user/${USER_ID}; export DBUS_SESSION_BUS_ADDRESS=${DBUS_ADDR}; $@"
}

echo "🚀 Starting Services..."

# A. Start SYSTEM DBus (Audio Latency)
echo "🚌 Starting System DBus..."
mkdir -p /var/run/dbus && rm -f /var/run/dbus/pid
dbus-daemon --system --fork

# B. Start USER DBus (Steam IPC)
echo "👤 Starting User DBus..."
run_services "dbus-daemon --session --address=${DBUS_ADDR} --nofork --print-address &"
sleep 1

# C. Start Audio Stack
echo "🔊 Starting Audio Stack..."
run_services "pipewire &"
run_services "pipewire-pulse &"
run_services "wireplumber &"

# --- 6. Start Sway ---
echo "🖥️  Starting Sway..."
exec su - ${USER_NAME} -c "
    export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR
    export DBUS_SESSION_BUS_ADDRESS=${DBUS_ADDR}
    export LIBSEAT_BACKEND=$LIBSEAT_BACKEND
    export WLR_BACKENDS=$WLR_BACKENDS
    export WLR_RENDERER=$WLR_RENDERER
    exec sway
"
