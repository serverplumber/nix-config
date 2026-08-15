{ pkgs, ... }:
let
  # See the JetBrains package comment below for what this works around.
  # Has to run as a postFixupHooks entry, not a plain postFixup string:
  # genericBuild's runHook invokes the postFixup *variable* before the
  # postFixupHooks *array* (autoPatchelfHook registers itself into that
  # array) — a plain postFixup patch gets silently clobbered when
  # autoPatchelf runs its own pass afterwards and re-derives the same bad
  # rpath. Appending to the array from preFixup (which does run first)
  # guarantees this runs last instead. Verified 2026-08-15 by rebuilding
  # both ways and diffing the resulting RUNPATH.
  jetbrainsFixDeadRpath =
    pkg:
    pkg.overrideAttrs (old: {
      preFixup = ''
        ${old.preFixup or ""}
        _fixDeadSelfcontainedRpath() {
          local goodLibs="${
            pkgs.lib.makeLibraryPath [
              pkgs.libGL
              pkgs.libx11
              pkgs.fontconfig
              pkgs.stdenv.cc.cc.lib
              pkgs.zlib
            ]
          }"
          local rel
          for rel in \
            lib/skiko-awt-runtime-all/libskiko-linux-x64.so \
            plugins/code-provenance/lib/chatter-native/linux-x86_64/chatter \
            plugins/python-ce/helpers/pydev/pydevd_attach_to_process/attach_linux_amd64.so
          do
            local f="$out/${pkg.pname}/$rel"
            if [ -f "$f" ]; then
              patchelf --set-rpath "$goodLibs" "$f"
            fi
          done
        }
        postFixupHooks+=(_fixDeadSelfcontainedRpath)
      '';
    });
in
{
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
    ###
    ### jetbrainsFixDeadRpath works around a nixpkgs packaging gap shared by
    ### all three 2026.2 builds. The shared JetBrains linux builder
    ### (`rm -rf $out/$pname/plugins/remote-dev-server/selfcontained/` in its
    ### installPhase) deletes a directory of vendored libGL/libX11/
    ### fontconfig/libstdc++/zlib copies from $out — but that's *after*
    ### autoPatchelfHook has already indexed it from the still-present build
    ### sandbox copy at /build/<ide>-<version>/plugins/remote-dev-server/
    ### selfcontained/lib, so any bundled .so whose deps only resolve there
    ### gets an RPATH pointing at a directory that no longer exists once the
    ### sandbox is torn down — even though libGL, libx11, fontconfig and
    ### stdenv.cc.cc are already in this builder's own buildInputs and would
    ### resolve correctly if autoPatchelf preferred them instead.
    ###
    ### First noticed 2026-08-15 as PyCharm's first-ever launch on this
    ### machine appearing to hang on network: lib/skiko-awt-runtime-all/
    ### libskiko-linux-x64.so backs a Compose-rendered UI piece under the
    ### new remote-dev-server backend/frontend split, its RPATH was made up
    ### *entirely* of the dead path, and every native call into it threw
    ### UnsatisfiedLinkError on RenderNodeContext_nMake instead of the UI
    ### element it was drawing ever completing. Auditing the rest of the
    ### tree while tracking that down turned up two more files with the
    ### identical dead-RPATH problem: code-provenance's `chatter` helper
    ### (needs libz) and PyCharm-only pydevd's `attach_linux_amd64.so`
    ### (Attach to Process debugging, needs libstdc++). Same bug, same fix,
    ### applied wherever each file actually exists — the plugin set differs
    ### per IDE (`chatter` ships with idea but not goland; pydevd's
    ### attach-to-process helper only ships with pycharm).
    (jetbrainsFixDeadRpath jetbrains.idea) # 2026.2.0.1 — Ultimate via licence
    (jetbrainsFixDeadRpath jetbrains.goland) # 2026.2.0.1
    (jetbrainsFixDeadRpath jetbrains.pycharm) # 2026.2

    ### These are large and unfree. allowUnfree is already set for the NVIDIA
    ### driver, so nothing extra is needed — but if a downloaded IDE plugin or
    ### bundled toolchain refuses to run, that is the nix-ld question in O-13,
    ### not a packaging problem.
  ];
}
