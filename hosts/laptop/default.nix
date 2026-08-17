{ pkgs, ... }: {
  # Disks, bootloader and the generated hardware file live in ./machine.nix,
  # which only nixosConfigurations.laptop imports. Everything here is portable
  # enough to boot in a VM — see flake.nix.
  imports = [
    ../../modules/base.nix
    ../../modules/desktop.nix
    ../../modules/niri.nix
    ../../modules/hyprland.nix
    ../../modules/plasma.nix
    ../../modules/noctalia.nix
    ../../modules/audio.nix
    ../../modules/hardware-keys.nix
    ../../modules/nvidia.nix
    ../../modules/obs.nix
    ../../modules/containers.nix
    ../../modules/network.nix
    ../../modules/scanning.nix
    ../../modules/printing.nix
    ../../modules/nix-ld.nix
    ../../modules/backup.nix
    ../../modules/sdbackup.nix
    ../../modules/cuda.nix
    ../../modules/caches.nix
  ];

  services.sdbackup.enable = true;

  networking.hostName = "laptop";
  networking.networkmanager.enable = true;
  time.timeZone = "America/New_York"; # confirmed via timedatectl on Bluefin

  # Bluefin provided zram; NixOS does not by default.
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  # uid/gid are pinned because /home is a pre-existing subvolume whose file
  # ownership is already 1000:1000. Letting NixOS allocate would usually land
  # on 1000 anyway — "usually" is not good enough here.
  users.groups.stablefly.gid = 1000;
  users.users.stablefly = {
    isNormalUser = true;
    uid = 1000;
    group = "stablefly";
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "audio"
      "dialout" # serial: qFlipper, 3D printer
      "scanner" # SANE — see modules/scanning.nix
      "lp" # scanner/printer access
    ];
    shell = pkgs.fish;

    # Bluefin's /etc/subuid and /etc/subgid both read `stablefly:524288:65536`.
    # /etc does not survive the migration, and NixOS's autoSubUidGidRange would
    # allocate from 100000 instead. The 96 GiB rootless podman store on the
    # `home` subvolume has its overlay layers chowned into the 524288 range —
    # a different range means podman cannot read it without a full
    # `podman system migrate` chown pass over all 96 GiB. Pin it. See O-7.
    subUidRanges = [
      {
        startUid = 524288;
        count = 65536;
      }
    ];
    subGidRanges = [
      {
        startGid = 524288;
        count = 65536;
      }
    ];

    # nixos-install prompts for the root password only. Without this, first
    # boot is a greeter prompt with no valid user password.
    # TODO: `passwd stablefly` after first login, then delete this line.
    initialPassword = "changeme";
  };
  programs.fish.enable = true;

  # Laptop firmware updates via LVFS. `fwupdmgr refresh && fwupdmgr update`.
  services.fwupd.enable = true;

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Not deferrable: modules/nvidia.nix is imported unconditionally and
  # nvidiaPackages.stable is unfree, so the flake will not build without this.
  # Which *applications* get unfree treatment is a separate call — O-8.
  nixpkgs.config.allowUnfree = true;

  # Match the release actually installed. Never bump this afterwards.
  # Verified 2026-08-09: `lib.trivial.release` on the pinned nixpkgs is
  # "26.11", and the built derivation is nixos-system-laptop-26.11.20260807.
  # The earlier 26.05 was a guess and was wrong.
  system.stateVersion = "26.11";
}
