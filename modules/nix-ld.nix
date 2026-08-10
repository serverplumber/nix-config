{ pkgs, ... }: {
  # Recreates /lib64/ld-linux-x86-64.so.2, which NixOS otherwise does not have.
  # Anything Nix did not build — uv's python-build-standalone interpreters, pip
  # wheels with native code, downloaded IDE toolchains — hardcodes that path
  # and simply will not execute without this. See O-13.
  programs.nix-ld.enable = true;

  # ***
  #
  # This list is the part that takes iteration. `enable` gets foreign binaries
  # STARTING; `libraries` is what they can then link against. Expect to add to
  # it — the workflow is: run the thing, read `libfoo.so.N: cannot open shared
  # object file`, find the package shipping that .so, add it here.
  #
  # `nix-index` (installable from home/dev.nix if wanted) is the tool for the
  # "which package has this file" step.
  #
  # Starting set: what native Python wheels reach for most often.
  programs.nix-ld.libraries = with pkgs; [
    stdenv.cc.cc.lib # libstdc++ — the single most common miss
    zlib
    openssl
    curl
    glib
    xz
  ];
  # NB: `libz` also exists in nixpkgs but is a different project from `zlib`.
  # `zlib` is the one you want here; do not add both.

  # ***
  #
  # Worth being honest about: nix-ld deliberately reintroduces the impurity
  # Nix exists to remove. A binary running through it is not reproducible. The
  # trade is accepted because the alternative is giving up uv's Python version
  # management, which is most of why uv is here at all.
}
