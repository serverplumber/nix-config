{
  config,
  pkgs,
  ...
}:
{
  imports = [
    ./cli.nix
    ./dev.nix
    ./gui.nix
    ./niri.nix
    ./hyprland.nix
    ./noctalia.nix
  ];
  # ***

  # Idle handling. ONE daemon for both sessions: swayidle speaks the generic
  # ext-idle-notify protocol, which niri and Hyprland both implement, so there
  # is no need for hypridle as well — and running both would double every
  # action.
  #
  # Without this nothing ever locks or suspends: noctalia provides the lock
  # screen but nothing triggers it.
  services.swayidle = {
    enable = true;
    timeouts = [
      {
        timeout = 300;
        command = "${config.programs.noctalia.package}/bin/noctalia msg lock";
      }
      {
        timeout = 600;
        command = "${pkgs.systemd}/bin/systemctl suspend";
      }
    ];
    # Attrset keyed by event name — the list-of-attrsets form is deprecated.
    events.before-sleep = "${config.programs.noctalia.package}/bin/noctalia msg lock";
  };

  home.username = "stablefly";
  home.homeDirectory = "/home/stablefly";
  home.stateVersion = "26.11"; # matches nixpkgs release, verified
  programs.home-manager.enable = true;
}
