# ... (rest of script) ...

# --- 7. Start Sunshine (ROOT MODE) ---
# ... (existing sunshine config logic) ...

# --- 7.4 START UDEV DAEMON (The Input Fix) ---
# We need a local udevd to tag the virtual devices Sunshine creates.
# Without this, libinput sees the files but ignores them.
if [ -x /usr/lib/systemd/systemd-udevd ]; then
    echo "Starting udevd..."
    /usr/lib/systemd/systemd-udevd --daemon
    # Trigger a full rescan so the DB populates
    udevadm trigger --action=add
    udevadm settle
fi

# --- WATCHDOG ---
(
    while true; do
        # 1. Trigger udev (keeps the DB alive for new devices)
        udevadm trigger --action=change --subsystem-match=input
        
        # 2. Force permissions
        chmod 666 /dev/input/event* 2>/dev/null
        chmod 666 /dev/input/js* 2>/dev/null
        
        # ... (rest of watchdog) ...
    done
) &

# ... (rest of script) ...
