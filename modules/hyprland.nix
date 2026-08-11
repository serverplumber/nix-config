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
    # what the greeter enumerates. Leaving it off keeps the Hyprland session
    # symmetric with the niri one, which is the whole point of running both.
  };

  # hyprland.cachix.org lives in modules/caches.nix, together with the others,
  # so the installer ISO and the container builder can reuse the same list.
  # Without that cache this input compiles Hyprland and its 13 sub-inputs.

  # Hybrid NVIDIA: Hyprland needs more hand-holding here than niri does.
  # See O-10 — these are the documented starting points, not a verified set.
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1"; # Electron/Chromium apps on Wayland
  };
}
