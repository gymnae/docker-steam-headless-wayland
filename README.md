Docker Steam Headless (Wayland / Hyprland / CachyOS)
⚠️ The "I Don't Know How To Code" Disclaimer
Please Read This First:
I (the repository owner) did not write this code.

This entire repository was architected, debugged, and hallucinated into existence by a Large Language Model (LLM) acting as a sysadmin. We spent hours fighting Linux permissions, audio buffers, Wayland protocols, NVIDIA GBM allocations, and Seatd DRM master permissions so you don't have to.

This is a highly tuned, "works on my machine" solution. It is designed specifically for a Proxmox LXC environment with a direct NVIDIA GPU passthrough and a Hardware Dummy Plug.

🎯 The Goal
To create a next-generation headless gaming container that moves away from the legacy X11/XVFB/VNC stack, using Hyprland as a bare-metal Wayland compositor instead of Gamescope.

Key Advantages:

Rolling Release: Based on CachyOS (Arch Linux) for day-one driver updates and CPU optimizations (x86-64-v3).

Hyprland Native: Uses a highly stripped-down Hyprland/Aquamarine backend for pristine fullscreen window management and instant focus-stealing. No desktop environment bloat.

Low Latency:

Video: NVENC via KMS (Direct GPU access via Sunshine).

Audio: PipeWire via shared Unix Sockets (10ms latency).

Input: Direct Kernel uinput injection (No network lag for input).

⚙️ Strict System Requirements
This container is not plug-and-play on a standard desktop Docker install. It relies heavily on direct hardware kernel bridging.

Host OS: Proxmox VE (LXC Container) or a Linux host with similar capabilities.

Container Type: Privileged LXC (Required for direct DRM hardware access).

Hardware Dummy Plug: A physical HDMI/DisplayPort dummy plug connected to the GPU.

Why? Unlike virtual framebuffers, Hyprland demands a physical output connector to create the Wayland session.

Host DRM Modesetting: Your Proxmox host MUST have NVIDIA DRM modesetting enabled.

Check: cat /sys/module/nvidia_drm/parameters/modeset (Must be Y)

If N, add nvidia-drm.modeset=1 to your host's GRUB config.

Kernel Modules: The host must have uinput enabled (modprobe uinput).

🛠️ Architecture: Direct Passthrough (No Toolkit)
Because Docker-in-LXC often breaks the official NVIDIA Container Toolkit (due to Debian/Arch library path mismatches), this container uses Direct Hardware Passthrough.

You MUST ensure the nvidia-utils package installed inside the Dockerfile exactly matches the driver version running on your Proxmox Host.

Setup Instructions:
Find your Host Driver Version:
Run nvidia-smi on your Proxmox host and note the version (e.g., 550.x or 535.x).

Update the Dockerfile:
Open the Dockerfile and change nvidia-580xx-utils to match your host (e.g., nvidia-550xx-utils).

Build & Run:

Bash
mkdir -p steam-data steam-config sunshine-conf
sudo chown -R 1000:1000 steam-data steam-config sunshine-conf

docker compose up -d --build
🎮 Usage
Connect: Open Moonlight on your client device.

Pair: Open your browser and go to https://<YOUR-SERVER-IP>:47990 to pair Sunshine.

Play: Launch "Steam Gaming". Hyprland will instantly pop Steam Big Picture onto the screen. Games will automatically steal fullscreen focus when launched.

🐛 Troubleshooting The NVIDIA/Wayland Pipeline
1. Hyprland crashes instantly: CBackend::create() failed!
This means Hyprland's Aquamarine renderer was denied access to your GPU. Check these in order:

Is your dummy plug actually inserted into the NVIDIA GPU?

Did you enable nvidia-drm.modeset=1 on the Proxmox host?

Does your Dockerfile NVIDIA driver version exactly match your Proxmox host nvidia-smi version?

2. Sunshine shows a Black Screen or GL: [00000502]
This is an OpenGL INVALID_OPERATION error caused by DRM modifiers.

Ensure export AQ_NO_MODIFIERS=1 and export WLR_DRM_NO_MODIFIERS=1 are set in scripts/steam-session.sh.

This forces Hyprland to use linear memory, which allows Sunshine's DMA-BUF capture to read the frames correctly.

3. Steam Remote Play is a Black Screen
Status: WONTFIX.
Steam's built-in Remote Play capture (NVFBC) is fundamentally broken on modern Wayland compositors. Use Moonlight. It is faster, handles controllers perfectly, and hooks directly into KMS.

4. No Audio in Moonlight
Open Steam (Big Picture) -> Settings -> Audio.

Set Output Device to "Sunshine_Stereo".

Note: The container runs a background watchdog that forces pactl set-default-sink every 5 seconds to ensure audio doesn't drift during game launches.
