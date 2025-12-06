# Docker Steam Headless (Wayland / Gamescope / CachyOS)

![Status](https://img.shields.io/badge/Status-Stable-green)
![OS](https://img.shields.io/badge/Base-CachyOS-cyan)
![Stack](https://img.shields.io/badge/Tech-Wayland%20%7C%20Gamescope%20%7C%20PipeWire-pink)
![Builder](https://img.shields.io/badge/Coded%20By-AI%20(LLM)-blueviolet)

## ⚠️ The "I Don't Know How To Code" Disclaimer

**Please Read This First:**
I (the repository owner) did not write this code.

This entire repository was architected, debugged, and hallucinated into existence by a Large Language Model (LLM) acting as a sysadmin. We spent hours fighting Linux permissions, audio buffers, Wayland protocols, and SDL mappings so you don't have to.

**This is a highly tuned, "works on my machine" solution.** It is designed specifically for a **Proxmox LXC** environment with an **NVIDIA GPU** and a **Hardware Dummy Plug**.

---

## 🎯 The Goal
To create a next-generation headless gaming container that moves away from the legacy X11/XVFB/VNC stack used by other solutions.

**Key Advantages:**
* **Rolling Release:** Based on **CachyOS** (Arch Linux) for day-one driver updates and CPU optimizations (x86-64-v3).
* **Wayland Native:** Uses **Gamescope** as the compositor. No desktop environment (GNOME/KDE) bloat.
* **Low Latency:**
    * **Video:** NVENC via KMS (Direct GPU access).
    * **Audio:** PipeWire via shared Unix Sockets (10ms latency).
    * **Input:** Direct Kernel `uinput` injection (No network lag for input).
* **Auto-Proton:** Automatically installs `proton-cachyos` and downloads the latest `Proton-GE`.

---

## ⚙️ Requirements

This container is **not** plug-and-play on a standard desktop Docker install. It requires specific host preparation.

1.  **Host OS:** Proxmox VE (LXC Container) or a Linux host with similar capabilities.
2.  **Container Type:** **Privileged** LXC (Required for direct hardware access).
3.  **GPU:** NVIDIA GPU passed through to the container (`/dev/dri`, `/dev/nvidia*`).
4.  **Dummy Plug:** A physical HDMI/DisplayPort dummy plug connected to the GPU.
    * *Why?* Gamescope requires a valid connector to output the Wayland session.
5.  **Kernel Modules:** The host must have `uinput` enabled.
    ```bash
    modprobe uinput
    ```

---

## 🛠️ Installation

### 1. Clone the repository
```bash
git clone https://github.com/gymnae/docker-steam-headless-wayland.git
cd docker-steam-headless-wayland
```

### 2. Create Data Directories
You must create these folders on the host and set the permissions to UID 1000 (`steam` user). If you skip this, the container will likely fail to start due to permission errors.

```bash
mkdir -p steam-data steam-config sunshine-conf
# 1000:1000 is the UID:GID of the steam user inside the container
sudo chown -R 1000:1000 steam-data steam-config sunshine-conf
```

### 3. Build & Run
```bash
docker compose up -d --build
```

---

## 🎮 Usage

1.  **Connect:** Open [Moonlight](https://moonlight-stream.org/) on your client device.
2.  **Pair:** Open your browser and go to `https://<YOUR-SERVER-IP>:47990` to pair Sunshine.
    * *Note: If 47990 is unreachable, check 47991 (port conflict fallback).*
3.  **Play:** Launch "Desktop" or "Steam".

---

## 🔧 Configuration

### Resolution & Refresh Rate
Change these in `docker-compose.yml` to match your client display/dummy plug capabilities.

```yaml
environment:
  - DISPLAY_WIDTH=2560
  - DISPLAY_HEIGHT=1440
  - DISPLAY_REFRESH=60
```

### Controller Mapping (DualSense / Xbox)
This container includes a specific **SDL2 Mapping Hack** in `entrypoint.sh` to fix axis swapping issues on Linux virtual controllers.

* It is currently tuned for **DualSense Edge** (`0ce6`) and standard **DualSense** controllers.
* It does **not** interfere with Xbox controllers (Steam handles them natively).
* If your controller inputs feel "wonky" (e.g., Right Stick acts as Triggers), you may need to edit the `SDL_GAMECONTROLLERCONFIG` string in `entrypoint.sh`.

---

## 🐛 Troubleshooting / Known Issues

### 1. Steam Remote Play is Black Screen
**Status:** **WONTFIX.**
Steam's built-in Remote Play capture (NVFBC) is broken on Wayland.
**Solution:** Use **Moonlight**. It is faster, supports HDR, and uses the modern NVENC pipeline configured in this image.

### 2. No Audio
**Solution:**
1.  Ensure your Moonlight client is not muted.
2.  Open Steam (Big Picture) -> Settings -> Audio.
3.  Set Output Device to **"Sunshine_Stereo"**.
4.  *Note:* The container runs a watchdog that attempts to force this every 5 seconds, but Steam sometimes resists.

### 3. Controller Not Working
**Solution:**
1.  Ensure you passed `/dev/input` as a **volume** in `docker-compose.yml`, not just a device.
2.  The container uses a `udevadm trigger` loop to ensure Steam detects hotplugged virtual controllers. Wait 5-10 seconds after connecting.

### 4. Gamescope Crash "Out of Textures"
**Solution:**
Ensure `shm_size: '4gb'` (or higher) is set in your `docker-compose.yml`. Wayland streaming requires significant shared memory.

---

## 📜 Credits
* **Base:** [CachyOS Docker](https://github.com/CachyOS/docker)
* **Tools:** Gamescope, Sunshine, PipeWire
* **Architect:** OpenAI o1/Gemini (via extensive prompt engineering)
