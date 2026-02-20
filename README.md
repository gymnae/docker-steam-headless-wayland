# Docker Steam Headless (Wayland / Hyprland / CachyOS)

![Status](https://img.shields.io/badge/Status-Stable-green)
![OS](https://img.shields.io/badge/Base-CachyOS-cyan)
![Stack](https://img.shields.io/badge/Tech-Wayland%20%7C%20Hyprland%20%7C%20PipeWire-pink)
![Builder](https://img.shields.io/badge/Coded%20By-AI%20(LLM)-blueviolet)

## ⚠️ The "I Don't Know How To Code" Disclaimer

**Please Read This First:**
I (the repository owner) did not write this code.

This entire repository was architected, debugged, and hallucinated into existence by a Large Language Model (LLM) acting as a sysadmin. We spent hours fighting Linux permissions, audio buffers, Wayland protocols, NVIDIA GBM allocations, and Seatd DRM master permissions so you don't have to.

**This is a highly tuned, "works on my machine" solution.** It is designed specifically for a **Proxmox LXC** environment with a direct **NVIDIA GPU** passthrough and a **Hardware Dummy Plug**.

---

## 🎯 The Goal
To create a next-generation headless gaming container that moves away from the legacy X11/XVFB/VNC stack, using **Hyprland** as a bare-metal Wayland compositor instead of Gamescope.

**Key Advantages:**
* **Rolling Release:** Based on **CachyOS** (Arch Linux) for day-one driver updates and CPU optimizations (x86-64-v3).
* **Hyprland Native:** Uses a highly stripped-down Hyprland/Aquamarine backend for pristine fullscreen window management and instant focus-stealing. No desktop environment bloat.
* **Low Latency:**
    * **Video:** NVENC via KMS (Direct GPU access via Sunshine).
    * **Audio:** PipeWire via shared Unix Sockets.
    * **Input:** Direct Kernel `uinput` injection (No network lag for input).

---

## ⚙️ Strict System Requirements

This container is **not** plug-and-play on a standard desktop Docker install. It relies heavily on direct hardware kernel bridging.

1.  **Host OS:** Proxmox VE (LXC Container) or a Linux host with similar capabilities.
2.  **Container Type:** **Privileged** LXC (Required for direct DRM hardware access).
3.  **Hardware Dummy Plug:** A physical HDMI/DisplayPort dummy plug connected to the GPU.
    * *Why?* Unlike virtual framebuffers or Gamescope, Hyprland **demands** a physical output connector to create the Wayland session.
4.  **Host DRM Modesetting:** Your Proxmox host **MUST** have NVIDIA DRM modesetting enabled.
    * Check: `cat /sys/module/nvidia_drm/parameters/modeset` (Must be `Y`)
    * If `N`, add `nvidia-drm.modeset=1` to your host's GRUB config.
5.  **Kernel Modules:** The host must have `uinput` enabled (`modprobe uinput`).

---

## 🛠️ Architecture: Direct Passthrough (No Toolkit)

Because Docker-in-LXC often breaks the official NVIDIA Container Toolkit (due to Debian/Arch library path mismatches), this container uses **Direct Hardware Passthrough**.

You **MUST** ensure the `nvidia-utils` package installed inside the `Dockerfile` exactly matches the driver version running on your Proxmox Host.

### Setup Instructions:
1. **Find your Host Driver Version:**
   Run `nvidia-smi` on your Proxmox host and note the version (e.g., `550.x` or `535.x`).
2. **Update the `Dockerfile`:**
   Open the `Dockerfile` and change `nvidia-580xx-utils` to match your host (e.g., `nvidia-550xx-utils`).
3. **Create Host Directories & Permissions:**
   Before running docker compose, create the unified Steam directory on your host and assign it to the container's `steam` user (UID 1000):
   ```bash
   mkdir -p ./steam-user
   sudo chown -R 1000:1000 ./steam-user
   ```
4. **Build & Run:**
   ```bash
   docker compose up -d --build
   ```

---

## 🎮 Usage

1.  **Connect:** Open [Moonlight](https://moonlight-stream.org/) on your client device.
2.  **Pair:** Open your browser and go to `https://<YOUR-SERVER-IP>:47990` to pair Sunshine.
3.  **Play:** Launch "Steam Gaming". Hyprland will instantly pop Steam Big Picture onto the screen. Games will automatically steal fullscreen focus when launched.

---

## 🐛 Troubleshooting The NVIDIA/Wayland Pipeline

### 1. Steam Remote Play is a Black Screen / Splash Screen Only
**Status: WONTFIX.**
Steam's built-in Remote Play capture (NVFBC) is fundamentally broken on modern Wayland compositors. **Use Moonlight**. It is faster, handles controllers perfectly, and hooks directly into the KMS pipeline.

### 2. Hyprland crashes instantly: `CBackend::create() failed!`
This means Hyprland's Aquamarine renderer was denied access to your GPU. Check these in order:
* Is your dummy plug actually inserted into the NVIDIA GPU?
* Did you enable `nvidia-drm.modeset=1` on the Proxmox host?
* Does your `Dockerfile` NVIDIA driver version *exactly* match your Proxmox host `nvidia-smi` version?

### 3. Sunshine shows a Black Screen or `GL: [00000502]`
This is an OpenGL `INVALID_OPERATION` error caused by DRM modifiers.
* Ensure `export AQ_NO_MODIFIERS=1` and `export WLR_DRM_NO_MODIFIERS=1` are **NOT** set in `scripts/steam-session.sh`.
* Sunshine requires these to be disabled/removed to capture the screen via DMA-BUF correctly.

### 4. No Audio in Moonlight
1.  Open Steam (Big Picture) -> Settings -> Audio.
2.  Set Output Device to **"Sunshine_Stereo"**.
3.  *Note:* The container runs a background watchdog that forces `pactl set-default-sink` every 5 seconds to ensure audio doesn't drift during game launches.

### 5. Adding Secondary Drives (`/mnt/games`) Fails in Steam
If Steam silently ignores a mapped drive when trying to add a new Storage location:
1.  Ensure the host folder is owned by the `steam` user (UID 1000): `sudo chown -R 1000:1000 /mnt/games`.
2.  Alternatively, bypass the UI entirely by symlinking the folder: 
    ```bash
    ln -s /mnt/games/steamapps ./steam-user/.local/share/Steam/steamapps
    ```
