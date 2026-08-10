{ pkgs, ... }: {
  # User CLI only — things you would want on a machine you never wrote code on.
  # helix, uv and mdformat moved to ./dev.nix when the buckets in
  # package-migration.md were applied. Nothing was dropped, only relocated.

  programs.starship = {
    enable = true;
    enableFishIntegration = true;
  };

  programs.eza = {
    enable = true;
    enableFishIntegration = true;
    icons = "auto"; # boolean form is deprecated upstream
  };

  programs.yazi = {
    enable = true;
    enableFishIntegration = true;
  };

  home.packages = with pkgs; [
    vim
    glow

    ### search / navigate
    bat
    fd
    ripgrep
    ugrep # overlaps ripgrep; kept for its extra modes
    television
    dysk
    tealdeer

    ### An extra shell, NOT the login shell — that stays fish
    ### (users.users.stablefly.shell in hosts/laptop/default.nix).
    nushell

    # Packaged in nixpkgs (3.8.6) — no uv tool, no nix-ld needed.
    # ⚠️ GPU acceleration depends on the deferred CUDA decision (O-12). This
    # build runs, but expect CPU inference until that is resolved.
    whisperx
  ];

  # §1a is now complete. zoxide, atuin, trash-cli, uutils-coreutils and
  # stress-ng were dropped by decision, not overlooked.
}
