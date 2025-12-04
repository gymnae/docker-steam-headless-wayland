FROM archlinux:latest

# 1. Initialize Arch, Multilib, and Chaotic-AUR
# We install the Chaotic-AUR keyring and mirrorlist so we can pull 'sunshine' as a binary.
RUN echo "[multilib]" >> /etc/pacman.conf && \
    echo "Include = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf && \
    pacman-key --init && \
    pacman-key --populate archlinux && \
    pacman -Syu --noconfirm --needed base-devel git sudo && \
    # Install Chaotic-AUR Keyring
    pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com && \
    pacman-key --lsign-key 3056513887B78AEB && \
    pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
                          'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst' && \
    # Add Chaotic-AUR to pacman.conf
    echo "[chaotic-aur]" >> /etc/pacman.conf && \
    echo "Include = /etc/pacman.d/chaotic-mirrorlist" >> /etc/pacman.conf && \
    # Update database to see the new repo
    pacman -Syu --noconfirm

# 2. Install Wayland, Gamescope, and Drivers
RUN pacman -S --noconfirm \
    gamescope \
    xorg-xwayland \
    nvidia-utils \
    lib32-nvidia-utils \
    steam \
    sunshine \
    ttf-liberation \
    pipewire pipewire-pulse wireplumber \
    libcap \
    --needed

# 3. Setup User
RUN useradd -m -G wheel,audio,video,input -s /bin/bash steam && \
    echo "steam ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# 4. Grant Capabilities
# Sunshine needs CAP_SYS_ADMIN to capture the screen via KMS (NVIDIA)
# Gamescope needs CAP_SYS_NICE for realtime scheduling
RUN setcap 'cap_sys_admin+p' /usr/bin/sunshine && \
    setcap 'cap_sys_nice+eip' /usr/bin/gamescope

# 5. Directories
RUN mkdir -p /home/steam/.config/sunshine /home/steam/.steam && \
    chown -R steam:steam /home/steam

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER steam
WORKDIR /home/steam
ENV PROTON_LOG=1

ENTRYPOINT ["/entrypoint.sh"]
