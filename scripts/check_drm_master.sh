#!/bin/bash
# Warn when another process (in this container, the LXC or on the host) already holds DRM master
# on the GPU Hyprland will drive. Hyprland then cannot set any display mode: every commit fails with
# "Permission denied", the output stays at 0x0 and Hyprland aborts in CMonitorResources::initFB
# (black screen). Seen with kmscon, which Fedora 45 enables on tty1, running in the LXC.
#
# Opening a card node with no master makes the opener master, so DRM_IOCTL_SET_MASTER succeeds.
# If someone else is master it fails. Closing the node releases master again right away.

# Same card selection as steam-session.sh: the NVIDIA card if there is one, otherwise all cards
NVIDIA_CARD=$(grep -l "0x10de" /sys/class/drm/card*/device/vendor 2>/dev/null | cut -d '/' -f 5 | head -n 1 || true)
if [ -n "$NVIDIA_CARD" ]; then
    CARDS="/dev/dri/$NVIDIA_CARD"
else
    CARDS=$(ls /dev/dri/card* 2>/dev/null)
fi

for card in $CARDS; do
    [ -e "$card" ] || continue
    result=$(python3 -I - "$card" 2>&1 <<'EOF'
import errno, fcntl, os, sys
DRM_IOCTL_SET_MASTER = 0x641e  # _IO('d', 0x1e)
fd = os.open(sys.argv[1], os.O_RDWR | os.O_CLOEXEC)
try:
    fcntl.ioctl(fd, DRM_IOCTL_SET_MASTER)
    print("free")
except OSError as e:
    name = errno.errorcode.get(e.errno, str(e.errno))
    print(("busy " if e.errno == errno.EBUSY else "error ") + name)
finally:
    os.close(fd)
EOF
)
    case "$result" in
        free) echo "    [DRM Check] $card: display control is free." ;;
        busy*)
            echo "    [DRM Check] WARNING: another process already controls the display on $card."
            echo "    [DRM Check] Hyprland will not be able to set a mode: expect a black screen or a crash in initFB."
            echo "    [DRM Check] Usual causes: kmscon or a getty/display manager in the LXC or on the host."
            echo "    [DRM Check] Find it on the Proxmox host: awk '\$4==\"y\"' /sys/kernel/debug/dri/*/clients"
            echo "    [DRM Check] Then disable it there, e.g.: systemctl disable --now kmsconvt@tty1.service && systemctl mask kmsconvt@.service"
            ;;
        *) echo "    [DRM Check] Could not test $card: $result" ;;
    esac
done
exit 0
