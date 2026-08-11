{ ... }: {
  # System-side support for the noctalia shell. The shell itself is
  # home-manager (home/noctalia.nix); this is only the services its bar and
  # panels read from.
  #
  # Upstream exposes `recommendedServices.enable` on its own NixOS module,
  # which turns on exactly these four. They are spelled out here instead so
  # that nothing about the system config depends on a flake module's defaults
  # changing under us — and so the reason each one exists is visible.

  hardware.bluetooth.enable = true; # bluetooth applet
  services.upower.enable = true; # battery indicator
  services.power-profiles-daemon.enable = true; # power profile switcher
  # networking.networkmanager.enable is already set in hosts/laptop/default.nix

  # `services.tuned.enable` is the alternative to power-profiles-daemon.
  # They conflict — enable exactly one.

  # noctalia.cachix.org lives in modules/caches.nix — see the note there about
  # why the builder needs it separately from the built system.
}
