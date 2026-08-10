{ inputs, pkgs, ... }:
let
  hyprPkgs = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  programs.hyprland = {
    enable = true;
    # Take the package from the flake rather than nixpkgs, so it matches the
    # portal below and hits hyprland.cachix.org.
    package = hyprPkgs.hyprland;
    portalPackage = hyprPkgs.xdg-desktop-portal-hyprland;

    # Deliberately NOT using withUWSM. uwsm manages the session as systemd
    # units, which is the opposite of the compositor-autostart model noctalia
    # wants (§7a) — and it changes the wayland-session desktop file, which is
    # what tuigreet enumerates. Leaving it off keeps the Hyprland session
    # symmetric with the niri one, which is the whole point of running both.
  };

  # Must be set BEFORE the hyprland input is first evaluated, or the first
  # build compiles Hyprland and its whole dependency tree locally.
  # `extra-*` is the additive form: plain `substituters` is a definition, not
  # an append, and would put cache.nixos.org at risk.
  nix.settings = {
    extra-substituters = [ "https://hyprland.cachix.org" ];
    extra-trusted-public-keys = [
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
    ];
  };

  # Hybrid NVIDIA: Hyprland needs more hand-holding here than niri does.
  # See O-10 — these are the documented starting points, not a verified set.
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1"; # Electron/Chromium apps on Wayland
  };
}
