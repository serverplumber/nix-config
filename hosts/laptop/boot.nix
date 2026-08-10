{ ... }: {
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    device = "nodev"; # EFI install, no MBR target

    # Windows gets reached via the firmware boot picker (F-key at POST), not a
    # GRUB entry. Decided 2026-08-09: Windows has not been booted in a year,
    # so the cost is one keypress a year and the benefit is that invariant 1
    # holds without an exception — os-prober is the only thing in this whole
    # procedure that would touch nvme0n1, and now nothing does. It also drops
    # a Windows-disk mount from every single nixos-rebuild. See O-1.
    useOSProber = false;

    # ESP is 599 MiB with 587 MiB free, and copyKernels puts each generation's
    # kernel and initrd on it. 587 / 10 would leave ~58 MiB per generation,
    # which is tight for a modern kernel plus a full initrd on an NVIDIA box.
    # Start conservative and raise after measuring `df -h /boot`. See O-2.
    configurationLimit = 5;

    # /boot (vfat ESP) is a different filesystem from /nix (btrfs+zstd).
    # Copying kernels avoids relying on GRUB's btrfs+compression support.
    copyKernels = true;
  };

  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.efi.efiSysMountPoint = "/boot";
}
