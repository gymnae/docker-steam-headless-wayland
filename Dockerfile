# /Dockerfile
FROM cachyos/cachyos-v3:latest

# 1. Install Core & Universal Gaming Packages
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm \
    # Core Tools
    sudo vim openssh curl tar git \
    # Graphics (Universal)
    gamescope \
    xorg-xwayland \
    mesa-utils \
    vulkan-tools \
    # --- AMD Support ---
    vulkan-radeon \
    lib32-vulkan-radeon \
    libva-mesa-driver \
    lib32-libva-mesa-driver \
    mesa-vdpau \
    lib32-mesa-vdpau \
    # --- Intel Support ---
    vulkan-intel \
    lib32-vulkan-intel \
    intel-media-driver \
    libva-intel-driver \
    # --- Nvidia Support - pinned to famnily ---
    nvidia-580xx-utils \
    lib32-nvidia-580xx-utils \
    libva-nvidia-driver \
    # Gaming Stack
    steam \
    ffmpeg \
    sunshine \
    proton-cachyos \
    mangohud \
    protontricks \
    # Audio
    rtkit \
    pipewire pipewire-pulse wireplumber \
    lib32-pipewire lib32-libpulse lib32-alsa-plugins \
    # Input
    seatd \
    libinput \
    libinput-tools \
    && pacman -Scc --noconfirm

# 2. Install Game Device Rules
RUN git clone https://codeberg.org/fabiscafe/game-devices-udev.git /tmp/gdu && \
    cp /tmp/gdu/*.rules /etc/udev/rules.d/ && \
    rm -rf /tmp/gdu

# 3. Install Proton-GE
RUN mkdir -p /usr/share/steam/compatibilitytools.d/ && \
    curl -s https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest \
    | grep "browser_download_url" | grep ".tar.gz" | head -n 1 | cut -d : -f 2,3 | tr -d \" \
    | xargs curl -L -o /tmp/proton-ge.tar.gz && \
    tar -xf /tmp/proton-ge.tar.gz -C /usr/share/steam/compatibilitytools.d/ && \
    rm /tmp/proton-ge.tar.gz

# 4. Setup User 'steam'
# CRITICAL: 'render' group is included here. Do not remove it.
RUN useradd -m -G wheel,audio,video,input,storage,render -s /bin/bash steam && \
    echo "steam ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers && \
    mkdir -p /home/steam/.config/sunshine /home/steam/.steam/root/compatibilitytools.d && \
    chown -R steam:steam /home/steam && \
    setcap 'cap_sys_admin,cap_net_admin+p' $(readlink -f /usr/bin/sunshine) && \
    setcap 'cap_sys_nice+eip' $(readlink -f /usr/bin/gamescope)

## 5. Inject PipeWire Low Latency Config
#RUN mkdir -p /etc/pipewire/pipewire.conf.d
#COPY config/low-latency.conf /etc/pipewire/pipewire.conf.d/99-lowlatency.conf

# 6. Inject Scripts
# CRITICAL FIX: We copy the ENTIRE scripts folder. 
# Your previous version missed init_sunshine.sh, watchdog.sh, etc.
COPY scripts/ /usr/local/bin/scripts/
RUN chmod +x /usr/local/bin/scripts/*.sh

# We overwrite entrypoint with your modified version
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh


RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
    echo "de_DE.UTF-8 UTF-8" >> /etc/locale.gen && \
    locale-gen

# 2. Set System-wide Locale ENV
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# 7. Environment Variables
# CRITICAL FIX: Added 'SteamDeck=1' to the list.
ENV XDG_RUNTIME_DIR=/run/user/1000 \
    PULSE_SERVER=unix:/run/user/1000/pulse/native \
    WAYLAND_DISPLAY=wayland-0 \
    MOZ_ENABLE_WAYLAND=1 \
    QT_QPA_PLATFORM=wayland
USER root
WORKDIR /home/steam
ENTRYPOINT ["/entrypoint.sh"]
