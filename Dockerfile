FROM cachyos/cachyos:latest

# 1. Install CachyOS Meta + Drivers + Sunshine
# - cachyos-gaming-meta: The base optimized stack (includes proton-cachyos)
# - gamescope/xorg-xwayland: The Wayland Compositor stack
# - nvidia-utils: Proprietary drivers (Meta packages usually don't assume GPU vendor)
# - sunshine: Streaming host
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm \
    cachyos-gaming-meta \
    gamescope \
    xorg-xwayland \
    nvidia-utils \
    lib32-nvidia-utils \
    sunshine \
    pipewire pipewire-pulse wireplumber \
    openssh sudo vim curl tar python libcap \
    && pacman -Scc --noconfirm

# 2. Install Proton-GE (Direct from GitHub)
# We install this alongside the system's proton-cachyos
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
    # Capabilities for Wayland/Sunshine
    setcap 'cap_sys_admin+p' /usr/bin/sunshine && \
    setcap 'cap_sys_nice+eip' /usr/bin/gamescope

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER steam
WORKDIR /home/steam
ENV PROTON_LOG=1

ENTRYPOINT ["/entrypoint.sh"]
