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

    # Deliberately NOT using withUWSM. The two things uwsm is usually wanted
    # for are already covered: it runs the compositor as a systemd user unit
    # and exports the session environment, and we get both from
    # hyprland-session.target plus home-manager's `systemd.enable` (left at
    # its default in home/hyprland.nix). niri.service does the same upstream
    # in the other session.
    #
    # What is left is per-app systemd scopes, and those only exist for apps
    # started through `uwsm app --`. noctalia's launcher execs .desktop
    # entries itself, so it would not use the wrapper — and a session where
    # some apps have scopes and some do not gives a resource view that is
    # confidently wrong. Partial coverage here is worse than none.
    #
    # It also changes the wayland-session desktop file, which is what the
    # greeter enumerates — the exact surface three greeters have already
    # broken on (see the history in modules/desktop.nix). And leaving it off
    # keeps this session symmetric with the niri one, which is the whole
    # point of running both.
    #
    # docs/session-architecture.md has the full comparison, and the one piece
    # of uwsm that is worth taking on its own: `systemd-run --user --scope`
    # at a single launch point, for an agent that outlives its window.
    #
    # Unrelated to this option: the Hyprland package ships
    # hyprland-uwsm.desktop either way. Without uwsm on PATH it is inert
    # (TryExec=uwsm) and the greeter should hide it — seeing it listed is not
    # evidence that this setting drifted.
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
