{ config, ... }: {
  # OBS itself is a user package (home/gui.nix). This module exists only for
  # the virtual camera, which needs a kernel module and therefore cannot live
  # in home-manager.
  #
  # ***
  #
  # Without this, OBS starts fine and the "Start Virtual Camera" button is
  # simply absent — which reads as a missing feature rather than a missing
  # module. Screen capture and NVENC need nothing here: capture goes through
  # the pipewire portal (modules/desktop.nix) and encoding through the driver
  # already configured in modules/nvidia.nix.
  boot.extraModulePackages = [ config.boot.kernelPackages.v4l2loopback ];
  boot.kernelModules = [ "v4l2loopback" ];

  # exclusive_caps=1 is what makes the device show up as a real webcam to
  # Chromium/Electron apps — i.e. to Brave, which is where the conferencing
  # profile lives.
  boot.extraModprobeConfig = ''
    options v4l2loopback devices=1 video_nr=9 card_label="OBS Virtual Camera" exclusive_caps=1
  '';
}
