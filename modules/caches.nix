{ ... }: {
  # Every extra binary cache, in one place, so it can be imported by BOTH the
  # laptop config and the installer ISO.
  #
  # ***
  #
  # The distinction that makes this module necessary: `nix.settings` here
  # configures the machine being *built*, not the machine doing the
  # *building*. Three separate contexts need these caches and each gets them
  # differently:
  #
  #   1. the installed laptop      -> hosts/laptop imports this module
  #   2. the live installer ISO    -> flake.nix's `installer` imports it too,
  #                                   or `nixos-install` compiles Hyprland and
  #                                   CUDA torch during the migration itself
  #   3. the container builder on  -> ../.nix-config, which is a plain
  #      Bluefin (`just vm`/`iso`)    nix.conf and knows nothing about this
  #
  # Adding a cache means touching this file AND ../.nix-config. They cannot be
  # shared — one is a NixOS module, the other is read by a bare nix binary.
  nix.settings = {
    extra-substituters = [
      "https://hyprland.cachix.org"
      "https://noctalia.cachix.org"
      "https://cache.nixos-cuda.org"
    ];
    extra-trusted-public-keys = [
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
      "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
    ];
  };

  # ***
  #
  # niri.cachix.org is deliberately absent. modules/niri.nix uses `pkgs.niri`
  # rather than niri-flake's packages (they fail against our nixpkgs pin), and
  # nixpkgs' build comes from cache.nixos.org. Adding the flake's cache would
  # be dead weight.
}
