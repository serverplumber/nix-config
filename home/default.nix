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
  home.stateVersion = "26.11"; # matches nixpkgs release, verified
  programs.home-manager.enable = true;
}
