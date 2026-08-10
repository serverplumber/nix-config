{ config, pkgs, ... }: {
  # Hybrid graphics, observed on Bluefin via lspci:
  #   00:02.0  Intel Raptor Lake-P [Iris Xe]        -> PCI:0:2:0
  #   01:00.0  NVIDIA AD106M [RTX 4070 Laptop]      -> PCI:1:0:0
  #
  # The Bluefin image was bluefin-dx-nvidia (driver 580.95.05), so the
  # proprietary stack is what this machine has been running. Nothing in §5–§8
  # of the runbook covered graphics at all — see O-6.

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # Still the correct option name on a Wayland-only system: it is what selects
  # the NVIDIA kernel/driver stack, not just an Xorg driver list.
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    # Required for any Wayland compositor to get a working DRM device.
    # niri is Smithay-based, Hyprland is wlroots-derived; both need this.
    modesetting.enable = true;

    # AD106M is Ada — well inside the Turing+ range where the open kernel
    # modules are the upstream-recommended default.
    open = true;

    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;

    powerManagement = {
      enable = true;
      # Lets the dGPU fully power down when no offloaded client is running.
      # Only valid alongside prime.offload; drop it if you switch to sync mode.
      finegrained = true;
    };

    prime = {
      offload = {
        enable = true;
        enableOffloadCmd = true; # provides `nvidia-offload <cmd>`
      };
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };

  # CUDA / compute.
  #
  # `nvidia-offload` is a GRAPHICS wrapper — it sets __NV_PRIME_RENDER_OFFLOAD
  # and __GLX_VENDOR_LIBRARY_NAME so GL/Vulkan pick the dGPU. CUDA does not go
  # through GLX and needs none of it: a CUDA process opens the driver directly
  # and runtime PM resumes the suspended dGPU on device open. So `python
  # train.py` and `nvidia-smi` work with no prefix, docked or not — the only
  # cost undocked is a wake latency on the first call.
  #
  # Corollary worth knowing: ANY nvidia-smi call wakes the GPU. Do not put a
  # GPU widget that polls it in the status bar, or the dGPU never suspends and
  # O-10a's whole power argument evaporates.
  #
  # ***
  #
  # Required before the CUDA container images can see the GPU. Generates
  # /var/run/cdi/nvidia-container-toolkit.json, which podman consumes via
  # `--device nvidia.com/gpu=all`. CDI is also what makes this work under
  # ROOTLESS podman — which is the only kind configured here (O-7).
  hardware.nvidia-container-toolkit.enable = true;
}
