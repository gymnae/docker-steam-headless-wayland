FROM cachyos/cachyos-v4:latest

# 1. Update & Install EVERYTHING from official Repos
# CachyOS provides all these packages natively (no compiling).
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm \
    # Core Tools
    sudo vim openssh \
    # Graphics (Optimized CachyOS builds)
    gamescope \
    xorg-xwayland \
    nvidia-utils \
    lib32-nvidia-utils \
    # Gaming Stack
    steam \
    sunshine \
    cachyos-gaming-meta \
    protontricks \
    # Audio & Fonts
    pipewire pipewire-pulse wireplumber \
    ttf-liberation \
    libcap \
    # Cleanup: Remove cache to keep image tiny
    && pacman -Scc --noconfirm

# 2. Setup User 'steam'
RUN useradd -m -G wheel,audio,video,input,storage -s /bin/bash steam && \
    echo "steam ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers && \
    # Create Config Dirs
    mkdir -p /home/steam/.config/sunshine /home/steam/.steam && \
    chown -R steam:steam /home/steam && \
    # Grant Capabilities (Required for Sunshine/Gamescope to access GPU/Inputs)
    setcap 'cap_sys_admin+p' /usr/bin/sunshine && \
    setcap 'cap_sys_nice+eip' /usr/bin/gamescope

# 3. Copy Entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER steam
WORKDIR /home/steam
ENV PROTON_LOG=1

ENTRYPOINT ["/entrypoint.sh"]
