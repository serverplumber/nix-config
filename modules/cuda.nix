{ ... }: {
  # The CUDA binary cache. Without it, anything built with cudaSupport is
  # compiled locally — torch alone is a multi-hour build. With it, the same
  # derivation is a 215 MB download (measured 2026-08-10).
  #
  # NB the cache MOVED: cuda-maintainers.cachix.org is stale and returns 404
  # for current paths. cache.nixos-cuda.org is the live one.
  nix.settings = {
    extra-substituters = [ "https://cache.nixos-cuda.org" ];
    extra-trusted-public-keys = [
      "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
    ];
  };

  # ***

  # Deliberately NOT setting `nixpkgs.config.cudaSupport = true` here. That is
  # global: it would rebuild ffmpeg, opencv, blender and anything else that
  # takes a cudaSupport flag, most of which is not in the CUDA cache, for zero
  # benefit on a machine that wants GPU acceleration in exactly one program.
  #
  # Instead home/cli.nix instantiates a second nixpkgs with cudaSupport for
  # whisperx alone. See O-12.
  #
  # ***
  #
  # Also deliberately NOT setting `cudaCapabilities = [ "8.9" ]` (Ada, which is
  # what the 4070 is). Narrowing the capability list would cut build size —
  # but it changes every derivation hash, so every cache hit becomes a cache
  # miss and you build the whole tree yourself. Defaults are what the cache
  # was populated with. Leave them alone.
}
