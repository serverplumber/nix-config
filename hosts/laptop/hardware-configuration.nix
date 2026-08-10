throw ''

  hosts/laptop/hardware-configuration.nix is a PLACEHOLDER.

  It cannot be written from the Bluefin side — it has to be generated against
  the real disks from the NixOS ISO, after the mounts in §3 are in place:

      nixos-generate-config --no-filesystems --root /mnt
      cp /mnt/etc/nixos/hardware-configuration.nix \
         <repo>/hosts/laptop/hardware-configuration.nix
      git -C <repo> add -A

  --no-filesystems matters: without it the generated file emits its own
  fileSystems.* and swapDevices attrs that collide with filesystems.nix and
  fail evaluation. If the ISO's nixos-generate-config predates the flag,
  generate normally and delete the fileSystems and swapDevices blocks by hand.

  This file throws on purpose. An empty stub would evaluate cleanly and build
  a system with no initrd modules — i.e. one that does not boot.
''
