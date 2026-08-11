{ ... }: {
  # Bare-metal-only configuration. Split out from default.nix so that
  # nixosConfigurations.laptop-vm can reuse everything else without dragging in
  # real disk UUIDs, a real ESP, or the generated hardware file.
  #
  # ***
  #
  # Nothing that is true only of THIS physical machine belongs anywhere but
  # here. If a VM build starts failing on hardware specifics, something leaked
  # out of this file.
  imports = [
    ./hardware-configuration.nix
    ./filesystems.nix
    ./boot.nix
  ];

  # 13th Gen Core i9 laptop wifi (Intel AX-series) needs its firmware blob
  # from linux-firmware to load at all — without this the card doesn't
  # appear as a device, NetworkManager or not.
  hardware.enableRedistributableFirmware = true;
}
