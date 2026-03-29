# Docker Steam Headless (Wayland / Hyprland / CachyOS)

![Status](https://img.shields.io/badge/Status-Stable-green)
![OS](https://img.shields.io/badge/Base-CachyOS-cyan)
![Stack](https://img.shields.io/badge/Tech-Wayland%20%7C%20Hyprland%20%7C%20PipeWire-pink)
![Builder](https://img.shields.io/badge/Coded%20By-AI%20(LLM)-blueviolet)

# In a nutshell

This image does the following:

 1. Pass through a GPU to [CachyOS docker image](https://hub.docker.com/r/cachyos/cachyos-v3/tags) running a streamlined Wayland [Hyprland](https://github.com/hyprwm/Hyprland) session
 2. [Sunshine](https://github.com/LizardByte/Sunshine) game stream host transports visual and audio output to remote clients
 3. Scripts adapt the resolution of Hyprland session to the requested resolution by the streaming client
 4. Super low latency for Audio and Input
 5. Supports multiple concurrent Gamepad inputs, Keyboard, and Mouse
 6. Keyboard locale and layout can be adjusted on the fly
 7. Currently optimized for Steam
 8.  Auxiliary tooling is included: Lutris, Proton-GE
 9. Primarily designed to run inside an LXC / Docker environment on Proxmox
10. Integrated [file browser ](https://filebrowser.org/index.html)for directly fiddling with config files and data in the container
11. **Should also work on any Linux Docker Host - see requirements and limitations**

    

# Motivation

* To build a modern alternative to X11 and VNC-based headless streaming solutions
* Enable HDR streaming
* Single-purpose Design: Gaming
* Enable multi-tenant use for GPUs without vGPU support (e.g., NVIDIA GeForce 3000 and newer)
* See how well vibe coding can deal with changing requirements and bleeding-edge stacks

## Requirements

* A dGPU or iGPU
* Linux host with a fairly recent Kernel
* Docker daemon
* Fake screen dongle - see Limitations for the reasons

### Limitations

**Display Dongle or a real display is required**

Given the current status of Hyprland and Wayland, a virtual screen does not work. Not even with black magic EDID injection

In the current state, a Dongle emulating a screen, or a real screen, must present proper EDID data. Screen or dongle control availability of possible client resolutions, refresh rates, or HDR. 

**No NVIDIA container toolkit**

Due to the design for use with LXC on Proxmox, the main branch of this image does not use the NVIDIA Container Toolkit, because passing host modules to a guest OS via a Docker container is a bit too prone to breakage (access rights, etc.). Instead, the GPU is directly attached to the Container. This *may* increase the attack surface, but it requires matching drivers on the host, guest, and Docker image. Since this image uses CachyOS, it may require manual driver updates on the host. It does for Proxmox.

I have created an *untested* branch with the NVIDIA container toolkit. This should work if you want to run this image without the complicated LXC dance on Proxmox.

**Privileged LXC**

During the design phase of this image, I worked in a privileged LXC. The setup may work in an unprivileged container, but it might be more involved regarding [UID and UID mapping](https://blog.pltc.me/proxmox-unprivileged-lxc-id-mapping/), since we require unhindered hardware access to the GPU and input devices. 

# Usage with Proxmox

## Motivation & Background

The main motivation is to pass through an NVIDIA GeForce 3000-class GPU to an LXC without exclusively binding it to a VM.

Since it is counter-indicated to run Docker, or any client-facing workload, on the host itself, a VM or LXC should be used.

Proxmox [advises against](https://pve.proxmox.com/pve-docs/pve-admin-guide.html#chapter_pct) using LXCs for Docker, but it actually works fine if your [setup allows for it](https://github.com/tteck/Proxmox/discussions/1245).

## Setup for Proxmox


1. Spin up a **privileged** LXC with a Linux guest of your choice. I use the latest provided Fedora template *Note*: This step may no longer be required once the [OCI image feature](https://raymii.org/s/tutorials/Finally_run_Docker_containers_natively_in_Proxmox_9.1.html) in Proxmox matures.
2. Install Docker daemon (untested with Podman) on the guest
3. Shut down LXC and manually adjust certain LXC config (`/etc/pve/lxc/xxx.conf`) aspects in an editor according to the following example:

```javascript
# the numbering of the devices is abriratry
# required for virtual input
dev1: /dev/uhid,gid=0,uid=0
# required for NVIDIA
dev2: /dev/nvidia-caps/nvidia-cap1
dev3: /dev/nvidia-caps/nvidia-cap2
# always required for virtual inputs
dev4: /dev/uinput,gid=0,uid=0
# have this match the device IDs of the GPU you want to use
# note: if you have both an iGPU and dGPU, the numbering may change with
# every reboot without manual intervention via module load order
dev5: /dev/dri/renderD128,gid=105,uid=0
dev6: /dev/dri/card1,gid=39,uid=0
features: fuse=1,nesting=1
# add mount points as needed
# I host nvidia drivers on the host and mount them into each LXC
mp2: /srv/drivers,mp=/mnt/drivers,mountoptions=discard
net0: name=eth0,bridge=vmbr0,ip=dhcp,type=veth
# required for proper docker functionality
tty: 2
# required
lxc.mount.entry: /dev/input dev/input none bind,optional,create=dir
lxc.mount.entry: /run/udev mnt/udev none bind,optional,create=dir
# nvidia specific
lxc.mount.entry: /dev/nvidia0 dev/nvidia0 none bind,optional,create=file
lxc.mount.entry: /dev/nvidiactl dev/nvidiactl none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-modeset dev/nvidia-modeset none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uvm dev/nvidia-uvm none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uvm-tools dev/nvidia-uvm-tools none bind,optional,create=file
lxc.mount.entry: /dev/nvram dev/nvram none bind,optional,create=file
# required - ensure these ttys exist on your host
lxc.mount.entry: /dev/tty10 dev/tty8 none bind,optional,create=file
lxc.mount.entry: /dev/tty11 dev/tty0 none bind,optional,create=file
# /dev/tty
lxc.cgroup2.devices.allow: c 4:* rwm
# nvidia0, nvidiactl, nvidia-modeset
lxc.cgroup2.devices.allow: c 195:* rwm
# nvidia-uvm, nvidia-uvm-tools
lxc.cgroup2.devices.allow: c 510:* rwm
# uhid / uinput 
lxc.cgroup2.devices.allow: c 10:* rwm
# mice, keyboard etc
lxc.cgroup2.devices.allow: c 13:* rwm
# nvidia-caps
lxc.cgroup2.devices.allow: c 235:* rwm
# dev/dri
lxc.cgroup2.devices.allow: c 226:* rwm
# for unconfined privileged lxc
lxc.apparmor.profile: unconfined
lxc.cap.drop:
lxc.apparmor.raw: mount
```


1. Start LXC and, if required, install GPU drivers. See the limitations on using NVIDIA hardware with a Proxmox host. 
2. Adapt the provided [docker-compose.yml.repo](https://github.com/gymnae/docker-steam-headless-wayland/blob/hyprland/docker-compose.yml.repo) to your needs and rename it to docker-compose.yml

   
   1. You can build the image locally or pull it from Docker Hub
   2. Please see the commented sections and adapt to your needs
3. Spin up a container

### First-time usage

1. Open a Browser and connect to the Sunshine admin interface: `http:/IPOFYOURLXC:47990`
2. Change the default login and password as required
3. Open a Sunshine client, e.g., Moonlight, in the same network and try to connect to the Sunshine Server
4. Type in the provided connection code into Sunshine
5. You may need to adjust settings in Sunshine, but usually that is not required

### Client usage

* Set your desired resolution and refresh rate, as well as HDR on/off, in your Streaming client
* Select the Sunshine server
* When you change the resolution, refresh rate, or HDR, select "Quit" in your Streaming Client instead of “Connect”. This triggers a restart of the Hyprland session in your Docker container, thereby enabling the adaptation to your client's requirements. This is only needed if you change clients, e.g., Desktop to Steam Deck, or when you connect from a remote location via VPN.

### Access file browser

Since this image is not designed to expose the resulting container to the internet or to malicious local network users, there is minimal friction in using all components. Like the file browser.

* Open your browser and point it to `<http://IPOFYOURLXC:8080>` 
* No login required
* Console mode is also available


## Non-Proxmox use

The steps for setting up  docker-compose.yml, accessing Sunshine, and using the file browser are the same as for Proxmox. Please see the doc above. You need to know the IP address of your Docker host and use that IP in your browser instead


