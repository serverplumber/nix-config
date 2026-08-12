let
  # Read from /dev/disk/by-uuid on the running Bluefin system. Nothing in the
  # procedure reformats either filesystem, so these are the same values the
  # ISO will see — re-confirm with `blkid` per §2.3 anyway.
  btrfsUUID = "6f8449a5-f6b6-4f60-adb1-c9b6c58cac3a"; # nvme1n1p3
  espUUID = "49A3-D385"; # nvme1n1p1

  # Reminder: btrfs applies these filesystem-wide, first mount wins.
  # Listing them per-entry is cosmetic consistency, not per-subvolume config.
  btrfsOpts = [
    "compress=zstd"
    "noatime"
  ];
in
{
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/${btrfsUUID}";
    fsType = "btrfs";
    options = btrfsOpts ++ [ "subvol=nixos" ];
  };

  # Pre-existing subvolume carried over from Bluefin. Never formatted.
  fileSystems."/home" = {
    device = "/dev/disk/by-uuid/${btrfsUUID}";
    fsType = "btrfs";
    options = btrfsOpts ++ [ "subvol=home" ];
  };

  # /nix is a separate subvolume — NOT optional. It is in pathsNeededForBoot,
  # so if §3 does not create it, this fails in stage 1 rather than at a prompt.
  # Create it and declare it, or do neither. Do not mix.
  fileSystems."/nix" = {
    device = "/dev/disk/by-uuid/${btrfsUUID}";
    fsType = "btrfs";
    options = btrfsOpts ++ [ "subvol=nix" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/1f942a43-9b8a-4299-b1bc-283c264309ec";
    fsType = "ext4";
  };

  fileSystems."/boot/efi" = {
    device = "/dev/disk/by-uuid/${espUUID}";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  swapDevices = [ ]; # zram only
}
