{ inputs, pkgs, ... }: {
  imports = [ inputs.niri.nixosModules.niri ];

  # This module disables the nixpkgs `programs.niri` module on purpose — the
  # two define the same option path. Never enable both.
  programs.niri = {
    enable = true;
    package = pkgs.niri-stable; # niri-unstable = latest main, don't
  };

  # niri-flake enables niri.cachix.org by default, so niri is fetched rather
  # than compiled. If you ever want to opt out of the cache, set
  # `programs.niri.package = pkgs.niri;` to take nixpkgs' build instead.

  # The module also sets up polkit, an auth agent, and the keyring. Those are
  # shared with the Hyprland session; whichever starts first wins and both
  # work, so there is no need to duplicate them in modules/hyprland.nix.
}
