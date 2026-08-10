{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    brightnessctl # backlight
    wireplumber # provides wpctl for volume
    playerctl # MPRIS transport keys
  ];

  # udev rules so a member of the `video` group can set backlight
  # without setuid. User is already in `video` (see hosts/laptop).
  services.udev.packages = [ pkgs.brightnessctl ];
}
