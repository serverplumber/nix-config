{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    brightnessctl # backlight
    ddcutil # external monitor brightness (DDC/CI)
    wireplumber # provides wpctl for volume
    playerctl # MPRIS transport keys
  ];

  # udev rules so a member of the `video` group can set backlight
  # without setuid. User is already in `video` (see hosts/laptop).
  services.udev.packages = [ pkgs.brightnessctl ];

  # External monitors have no backlight device; their brightness is set over
  # DDC/CI (pkgs/monitor-brightness.nix). This loads i2c-dev and gives the
  # `i2c` group the bus nodes — the user is in it (see hosts/laptop).
  hardware.i2c.enable = true;
}
