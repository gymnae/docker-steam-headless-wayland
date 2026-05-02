# /Dockerfile
FROM cachyos/cachyos-v3:latest

RUN printf "\n[lizardbyte-beta]\nSigLevel = Optional\nServer = https://github.com/LizardByte/pacman-repo/releases/download/beta\n" >> /etc/pacman.conf

# 1. Install Core & Universal Gaming Packages
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm \
    # Core Tools
    sudo vim openssh curl tar git paru \
    # Graphics (Universal)
    gamescope \
    xorg-xwayland \
    mesa-utils \
    mesa \
    lib32-mesa \
    vulkan-tools \
    # hyprland
    hyprland \
    xdg-desktop-portal-hyprland \
    polkit \
    egl-wayland \
    vulkan-icd-loader \
    libglvnd \
   # standalone wine & lutris
    wine-cachyos \
    lutris \
    # Radeon
    vulkan-radeon \
    lib32-vulkan-radeon \
    # --- Intel Support  ---
    vulkan-intel \
    lib32-vulkan-intel \
    intel-media-driver \
    libva-intel-driver \
    # --- Nvidia Support ---
    nvidia-utils \
    lib32-nvidia-utils \
    libva-nvidia-driver \
    # Gaming Stack
    steam \
    ffmpeg \
    lizardbyte-beta/sunshine-git \
    proton-cachyos \
    mangohud \
    protontricks \
    cachyos-v3/lib32-zlib-ng-compat \
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
    cp /tmp/gdu/src/*.rules /etc/udev/rules.d/ && \
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

# --- Install File Browser ---
RUN curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash && \
    setcap 'cap_net_bind_service=+ep' /usr/local/bin/filebrowser

# 6. Inject Scripts
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

ENV XDG_RUNTIME_DIR=/run/user/1000 \
    PULSE_SERVER=unix:/run/user/1000/pulse/native \
    MOZ_ENABLE_WAYLAND=1 \
    QT_QPA_PLATFORM=wayland
  #  NVIDIA_VISIBLE_DEVICES=all \
  #  NVIDIA_DRIVER_CAPABILITIES=all
USER root
WORKDIR /home/steam
ENTRYPOINT ["/entrypoint.sh"]
