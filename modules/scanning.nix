{ pkgs, ... }: {
  # Skanpage is a frontend. Without SANE underneath it launches fine and finds
  # zero scanners, which reads as a broken app rather than a missing service.
  hardware.sane = {
    enable = true;

    # Driverless scanning over eSCL/WSD. Covers most scanners made in roughly
    # the last decade, including network ones, without hunting for a vendor
    # backend. If the scanner still isn't found, it likely needs a specific
    # backend here — `utsushi` for Epson is the usual next guess.
    extraBackends = [ pkgs.sane-airscan ];
  };

  # ***

  # SANE needs group membership to reach the device; `scanner` and `lp` are
  # added to users.users.stablefly.extraGroups in hosts/laptop/default.nix.
  # Group changes only take effect on a fresh login — a `nixos-rebuild switch`
  # is not enough.
}
