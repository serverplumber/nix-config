{
  inputs,
  pkgs,
  ...
}:
let
  # A second nixpkgs instance with CUDA on, used for exactly one package.
  # Instantiating nixpkgs twice costs eval time and memory, but it keeps
  # cudaSupport off the other ~1500 packages in this closure — see
  # modules/cuda.nix for why global cudaSupport is the wrong tool.
  #
  # Everything downstream of this (torch, ctranslate2 via faster-whisper) is
  # rebuilt against CUDA, and cache.nixos-cuda.org has the expensive parts
  # prebuilt.
  cudaPkgs = import inputs.nixpkgs {
    inherit (pkgs.stdenv.hostPlatform) system;
    config = {
      allowUnfree = true;
      cudaSupport = true;
    };
  };

  # Anthropic's `ant` (Claude Developer Platform CLI) — not in nixpkgs, and
  # pkgs.ant is a different program (Apache Ant). See pkgs/ant-cli.nix.
  ant-cli = pkgs.callPackage ../pkgs/ant-cli.nix { };
in
{
  # User CLI only — things you would want on a machine you never wrote code on.
  # helix, uv and mdformat moved to ./dev.nix when the buckets in
  # package-migration.md were applied. Nothing was dropped, only relocated.

  # This is NOT redundant with hosts/laptop/default.nix's
  # `programs.fish.enable` — that's the NixOS module, which only installs the
  # package and registers /etc/shells. Home-manager's `programs.fish` is a
  # separate option namespace that owns ~/.config/fish/config.fish, and every
  # `enableFishIntegration = true` below (and direnv's in dev.nix) is silently
  # a no-op without it: home-manager's fish module gates its entire config
  # generation behind `mkIf cfg.enable`, so nothing was ever written.
  programs.fish.enable = true;

  # Was fisher-managed (jorgebucaran/fisher + danhper/fish-ssh-agent) under
  # Bluefin — reimplemented declaratively here so it survives a rebuild.
  # No upstream releases/tags, so pinned to a commit.
  programs.fish.plugins = [
    {
      name = "fish-ssh-agent";
      src = pkgs.fetchFromGitHub {
        owner = "danhper";
        repo = "fish-ssh-agent";
        rev = "f10d95775352931796fd17f54e6bf2f910163d1b";
        hash = "sha256-cFroQ7PSBZ5BhXzZEKTKHnEAuEu8W9rFrGZAb8vTgIE=";
      };
    }
  ];

  # Carried over from the hand-written Bluefin config.fish; coursier itself
  # isn't packaged here; it installs itself to this path directly.
  home.sessionPath = [ "$HOME/.local/share/coursier/bin" ];

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

  home.packages =
    with pkgs;
    [
      vim
      glow
      claude-code
      ant-cli

      ### search / navigate
      bat
      fd
      ripgrep
      ugrep # overlaps ripgrep; kept for its extra modes
      television
      dysk
      tealdeer

      # Also what lets `mpv <url>` play a stream directly — mpv shells out to
      # yt-dlp when handed a URL, so both must be on the same PATH.
      yt-dlp

      ### An extra shell, NOT the login shell — that stays fish
      ### (users.users.stablefly.shell in hosts/laptop/default.nix).
      nushell

    ]
    ++ [
      # GPU-accelerated. The default pkgs.whisperx links a CPU-only torch;
      # this one comes from the cudaSupport instance above, so faster-whisper's
      # ctranslate2 backend and the pyannote diarisation both reach the 4070.
      #
      # Verify after first boot with:
      #   python -c 'import torch; print(torch.cuda.is_available())'
      #   whisperx --device cuda <file>
      #
      # Undocked this wakes the dGPU on first use and it suspends again after —
      # that is O-10a working, not a fault.
      cudaPkgs.whisperx
    ];

  # §1a is now complete. zoxide, atuin, trash-cli, uutils-coreutils and
  # stress-ng were dropped by decision, not overlooked.
}
