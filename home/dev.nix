{ pkgs, ... }: {
  # Language-AGNOSTIC tooling. The distinction that matters: everything here
  # is wanted on $PATH in every project, which is exactly what disqualifies
  # the compilers and runtimes in package-migration.md §3 — those belong in
  # per-project devShells, not here.

  # The keystone. Without direnv the §3 plan (no global toolchains) is just an
  # inconvenience; with it, cd'ing into a repo is the whole workflow.
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    enableFishIntegration = true;
  };

  programs.helix.enable = true;

  home.packages = with pkgs; [
    ### forges
    gh
    glab

    ### linters / formatters — language-specific but small and always wanted
    shellcheck
    ruff
    mdformat
    markdown-oxide # markdown LSP, pairs with helix

    ### task runner — this repo and krump both use it
    just

    ### data wrangling
    yq-go # NB: nixpkgs `yq` is the python jq wrapper; this is mikefarah's Go one

    ### per-project python lives in devShells; uv is the tool that manages it,
    ### which makes uv itself a dev tool rather than a toolchain
    uv

    # ***

    ### JetBrains. All three are the UNIFIED distributions — JetBrains merged
    ### the Community/Ultimate split in mid-2025, so there is one package per
    ### IDE and you activate it with your licence. The `-ultimate`,
    ### `-community` and `-professional` variants all throw on eval now.
    ###
    ### RubyMine deliberately absent — not writing Ruby.
    jetbrains.idea # 2026.2.0.1 — Ultimate via licence
    jetbrains.goland # 2026.2.0.1
    jetbrains.pycharm # 2026.2

    ### These are large and unfree. allowUnfree is already set for the NVIDIA
    ### driver, so nothing extra is needed — but if a downloaded IDE plugin or
    ### bundled toolchain refuses to run, that is the nix-ld question in O-13,
    ### not a packaging problem.
  ];
}
