FROM cachyos/cachyos:latest

# 1. Install ONLY Essential Gaming Components
# - proton-cachyos: The optimized CachyOS build (Repo)
# - gamescope/xorg-xwayland: The Compositor
# - steam/sunshine: The Core Apps
# - nvidia-utils/lib32-nvidia-utils: Drivers
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm \
    # The Core Stack
    steam \
    gamescope \
    xorg-xwayland \
    sunshine \
    seatd \
    # The Proton You Requested
    proton-cachyos \
    # Drivers (Required for 32-bit games too)
    nvidia-utils \
    lib32-nvidia-utils \
    # Audio
    pipewire pipewire-pulse wireplumber \
    lib32-pipewire \
    lib32-libpulse \
    lib32-alsa-plugins \
    # Minimal Tools needed for setup/scripts
    openssh sudo vim curl tar python libcap \
    # Fonts (Required for Steam UI text)
    ttf-liberation \
    # Cleanup Cache (Reduces image size significantly)
    && pacman -Scc --noconfirm

# 2. Install Proton-GE (Direct from GitHub)
# We download this manually to avoid installing AUR helpers or build tools.
RUN mkdir -p /usr/share/steam/compatibilitytools.d/ && \
    curl -s https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest \
    | grep "browser_download_url" | grep ".tar.gz" | head -n 1 | cut -d : -f 2,3 | tr -d \" \
    | xargs curl -L -o /tmp/proton-ge.tar.gz && \
    tar -xf /tmp/proton-ge.tar.gz -C /usr/share/steam/compatibilitytools.d/ && \
    rm /tmp/proton-ge.tar.gz

# 3. Setup User 'steam'
RUN useradd -m -G wheel,audio,video,input,storage -s /bin/bash steam && \
    echo "steam ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers && \
    mkdir -p /home/steam/.config/sunshine /home/steam/.steam/root/compatibilitytools.d && \
    chown -R steam:steam /home/steam && \
    # CAPABILITIES FIX:
    # cap_sys_admin+p = Required for KMS screen capture (NVIDIA)
    # cap_net_admin+p = Required for some network features
    # Note: uinput access usually requires just correct file permissions, 
    # but running as non-root is safer.
    setcap 'cap_sys_admin,cap_net_admin+p' $(readlink -f /usr/bin/sunshine) && \
    setcap 'cap_sys_nice+eip' $(readlink -f /usr/bin/gamescope)

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# CHANGE: Stay as root so entrypoint can fix permissions
USER root
WORKDIR /home/steam
ENV PROTON_LOG=1

ENTRYPOINT ["/entrypoint.sh"]
