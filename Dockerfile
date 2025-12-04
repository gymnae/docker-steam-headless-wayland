FROM archlinux:latest

# 1. Initialize Arch & Enable Multilib
RUN echo "[multilib]" >> /etc/pacman.conf && \
    echo "Include = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf && \
    pacman -Syu --noconfirm

# 2. Install Base Dependencies & Build Tools
# We need 'base-devel' and 'git' to build AUR packages
RUN pacman -S --noconfirm \
    base-devel \
    git \
    sudo \
    vim \
    openssh \
    # Official Gaming Packages
    gamescope \
    xorg-xwayland \
    nvidia-utils \
    lib32-nvidia-utils \
    steam \
    ttf-liberation \
    pipewire pipewire-pulse wireplumber \
    libcap \
    --needed

# 3. Setup a 'builder' user for AUR (Cannot build as root)
RUN useradd -m builder && \
    echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# 4. Install 'yay' (AUR Helper)
USER builder
WORKDIR /home/builder
RUN git clone https://aur.archlinux.org/yay-bin.git && \
    cd yay-bin && \
    makepkg -si --noconfirm

# 5. Install Sunshine & Proton-GE (Binary Versions)
# We use '-bin' versions to download pre-compiled releases (Fast Install!)
RUN yay -S --noconfirm \
    sunshine-bin \
    proton-ge-custom-bin \
    protontricks

# 6. Finalize User Setup (Switch back to root to finish)
USER root
# Create the 'steam' user
RUN useradd -m -G wheel,audio,video,input,storage -s /bin/bash steam && \
    echo "steam ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers && \
    # Cleanup builder (Optional, saves space)
    userdel -r builder && \
    # Create Steam/Sunshine config dirs
    mkdir -p /home/steam/.config/sunshine /home/steam/.steam && \
    chown -R steam:steam /home/steam && \
    # Grant Capabilities (Critical for Sunshine/Gamescope)
    setcap 'cap_sys_admin+p' /usr/bin/sunshine && \
    setcap 'cap_sys_nice+eip' /usr/bin/gamescope

# 7. Copy Scripts
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 8. Environment
USER steam
WORKDIR /home/steam
ENV PROTON_LOG=1

ENTRYPOINT ["/entrypoint.sh"]
