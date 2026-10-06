{ ... }: {
  # Every extra binary cache, in one place, so it can be imported by BOTH the
  # laptop config and the installer ISO — or `nixos-install` compiles Hyprland
  # and CUDA torch from source.
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
