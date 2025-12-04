# ==========================================
# STAGE 1: The Builder (Disposed of later)
# ==========================================
FROM archlinux:latest AS builder

# 1. Setup Build Environment
RUN echo "[multilib]" >> /etc/pacman.conf && \
    echo "Include = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf && \
    pacman -Syu --noconfirm base-devel git sudo

# 2. Setup Build User
RUN useradd -m builder && \
    echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# 3. Build yay, Sunshine, Proton-GE, and Protontricks
# We switch to the user 'builder' to run makepkg
USER builder
WORKDIR /home/builder

# Script to clone and build a package, moving the result to /output
RUN mkdir /home/builder/output && \
    # --- Function to build AUR package ---
    build_aur() { \
        git clone "https://aur.archlinux.org/$1.git" && \
        cd "$1" && \
        makepkg -s --noconfirm && \
        cp *.pkg.tar.zst /home/builder/output/ && \
        cd .. ; \
    } && \
    # --- Build the packages ---
    # We build yay-bin first (though technically we could just build the others manually)
    # Actually, for pure optimization, we don't need 'yay'. We can just git clone the binaries directly.
    # This is safer and removes the 'yay' dependency entirely.
    build_aur "sunshine-bin" && \
    build_aur "proton-ge-custom-bin" && \
    build_aur "protontricks"

# ==========================================
# STAGE 2: The Final Image (Tiny & Clean)
# ==========================================
FROM archlinux:latest

# 1. Initialize Arch & Multilib
RUN echo "[multilib]" >> /etc/pacman.conf && \
    echo "Include = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf && \
    pacman -Syu --noconfirm

# 2. Install Runtime Dependencies (No compilers!)
# Note: We group them all to minimize layers
RUN pacman -S --noconfirm \
    # Core Tools
    sudo vim openssh \
    # Graphics & Drivers
    gamescope xorg-xwayland nvidia-utils lib32-nvidia-utils \
    # Audio
    pipewire pipewire-pulse wireplumber \
    # Gaming
    steam ttf-liberation libcap \
    # Dependencies often needed by Proton/Sunshine
    python avahi && \
    # Clean cache immediately to keep layer small
    pacman -Scc --noconfirm

# 3. Copy Built Packages from Stage 1
COPY --from=builder /home/builder/output/*.pkg.tar.zst /tmp/

# 4. Install AUR Packages & Delete Artifacts
RUN pacman -U --noconfirm /tmp/*.pkg.tar.zst && \
    rm /tmp/*.pkg.tar.zst && \
    # Secondary cleanup
    pacman -Scc --noconfirm

# 5. Setup User 'steam'
RUN useradd -m -G wheel,audio,video,input,storage -s /bin/bash steam && \
    echo "steam ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers && \
    mkdir -p /home/steam/.config/sunshine /home/steam/.steam && \
    chown -R steam:steam /home/steam && \
    # Capabilities
    setcap 'cap_sys_admin+p' /usr/bin/sunshine && \
    setcap 'cap_sys_nice+eip' /usr/bin/gamescope

# 6. Final Configs
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER steam
WORKDIR /home/steam
ENV PROTON_LOG=1

ENTRYPOINT ["/entrypoint.sh"]
