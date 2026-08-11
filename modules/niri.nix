{ inputs, pkgs, ... }: {
  imports = [ inputs.niri.nixosModules.niri ];

  # This module disables the nixpkgs `programs.niri` module on purpose — the
  # two define the same option path. Never enable both.
  programs.niri = {
    enable = true;

    # nixpkgs' build, NOT niri-flake's niri-stable/niri-unstable.
    #
    # Measured 2026-08-09: both of the flake's packages fail to evaluate
    # against the pinned nixpkgs —
    #
    #   error: `libdisplay-info_0_2` has been removed as it was unused in
    #   Nixpkgs. Consider upgrading to `libdisplay-info_0_3` ...
    #
    # niri-flake pins its own nixpkgs for the package derivations, and that
    # pin has drifted from ours. `pkgs.niri` is upstream's documented escape
    # hatch and evaluates cleanly.
    #
    # ***
    #
    # What this costs: niri.cachix.org no longer applies, so niri comes from
    # cache.nixos.org instead. That is fine — it is cached there too. What it
    # keeps: the flake's MODULE, which is the reason for the input at all
    # (typed `programs.niri.settings`, polkit/keyring wiring).
    #
    # Revisit after a `just update`; if the flake catches up, switching back
    # to `pkgs.niri-stable` is a one-line change.
    package = pkgs.niri;
  };

  # ***

  # X11 bridge. niri is Wayland-only and looks for `xwayland-satellite` on
  # PATH at startup; without it the journal shows
  #
  #   error spawning xwayland-satellite at "xwayland-satellite",
  #   disabling integration: No such file or directory
  #
  # and every X11-only application silently fails to start. Found by reading
  # the niri journal in the VM, 2026-08-10. niri-flake locks its own
  # xwayland-satellite inputs but its NixOS module exposes only enable/package,
  # so the binary has to be put on PATH explicitly.
  environment.systemPackages = [ pkgs.xwayland-satellite ];

  # The module also sets up polkit, an auth agent, and the keyring. Those are
  # shared with the Hyprland session; whichever starts first wins and both
  # work, so there is no need to duplicate them in modules/hyprland.nix.
}
