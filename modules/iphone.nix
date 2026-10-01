{ pkgs, ... }:
{
  # iOS devices don't speak USB mass storage; everything goes through
  # usbmuxd, which multiplexes connections to the phone over USB. Without it
  # neither Dolphin's afc:/ worker (kio-extras) nor ifuse can see the device —
  # and it fails as "no device", not as a missing service.
  services.usbmuxd.enable = true;

  # ifuse mounts the phone's media (or an app's documents, with --documents)
  # as a plain directory, for non-KDE apps. It replaces what kio-fuse would
  # have bridged from afc:/ — kio-fuse is masked, see modules/plasma.nix.
  # Unmount (`fusermount -u <dir>`) before unplugging: a FUSE mount whose
  # daemon hangs leaves its readers stuck in D state, and those block suspend.
  #
  # libimobiledevice is the CLI side: `idevicepair pair` when the trust
  # prompt didn't take, `ideviceinfo`, `idevicebackup2` for local backups.
  environment.systemPackages = with pkgs; [
    ifuse
    libimobiledevice
  ];
}
