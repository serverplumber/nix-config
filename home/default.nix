{ ... }: {
  imports = [
    ./cli.nix
    ./dev.nix
    ./gui.nix
    ./niri.nix
    ./hyprland.nix
    ./noctalia.nix
  ];
  home.username = "stablefly";
  home.homeDirectory = "/home/stablefly";
  home.stateVersion = "26.05";
  programs.home-manager.enable = true;
}
