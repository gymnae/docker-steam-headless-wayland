FROM cachyos/cachyos:latest

# 1. Install Core & Gaming Packages
# We REMOVE 'game-devices-udev' from here because it's not in the official repo.
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm \
    # Core
    sudo vim openssh curl tar git \
    # Graphics & Display
    gamescope \
    xorg-xwayland \
    nvidia-utils \
    lib32-nvidia-utils \
    libva-nvidia-driver \
    rtkit \
    # Gaming Stack
    steam \
    ntsync \
    ffmpeg \
    cuda \
    sunshine \
    proton-cachyos \
    # Audio (64-bit AND 32-bit required for Steam)
    pipewire pipewire-pulse wireplumber \
    lib32-pipewire lib32-libpulse lib32-alsa-plugins \
    # Tools for Input/Auth
    seatd \
    libinput \
    libinput-tools \
    # Cleanup
    && pacman -Scc --noconfirm

# 2. Install Game Device Rules (The Manual Fix)
# We clone the rules directly to where udev expects them.
# This fixes controller detection without needing AUR.
RUN git clone https://codeberg.org/fabiscafe/game-devices-udev.git /tmp/gdu && \
    cp /tmp/gdu/*.rules /etc/udev/rules.d/ && \
    rm -rf /tmp/gdu

# 3. Install Proton-GE (Manual)
# We download the latest GE-Proton tarball and extract it to the system folder
RUN mkdir -p /usr/share/steam/compatibilitytools.d/ && \
    curl -s https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest \
    | grep "browser_download_url" | grep ".tar.gz" | head -n 1 | cut -d : -f 2,3 | tr -d \" \
    | xargs curl -L -o /tmp/proton-ge.tar.gz && \
    tar -xf /tmp/proton-ge.tar.gz -C /usr/share/steam/compatibilitytools.d/ && \
    rm /tmp/proton-ge.tar.gz

# 4. Setup User 'steam'
RUN useradd -m -G wheel,audio,video,input,storage -s /bin/bash steam && \
    echo "steam ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers && \
    mkdir -p /home/steam/.config/sunshine /home/steam/.steam/root/compatibilitytools.d && \
    chown -R steam:steam /home/steam && \
    # Capabilities for Sunshine (Network/Input) and Gamescope (Priority)
    setcap 'cap_sys_admin,cap_net_admin+p' $(readlink -f /usr/bin/sunshine) && \
    setcap 'cap_sys_nice+eip' $(readlink -f /usr/bin/gamescope)

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER root
WORKDIR /home/steam
ENV PROTON_LOG=1

ENTRYPOINT ["/entrypoint.sh"]
