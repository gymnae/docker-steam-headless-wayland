FROM archlinux:latest

# 1. Enable Multilib (Steam) & Update
RUN echo "[multilib]" >> /etc/pacman.conf && \
    echo "Include = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf && \
    pacman -Syu --noconfirm

# 2. Install Wayland, Gamescope, and Drivers
RUN pacman -S --noconfirm \
    base-devel git sudo vim \
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
