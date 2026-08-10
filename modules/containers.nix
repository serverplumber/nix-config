{ pkgs, ... }: {
  # Rootless podman. The existing image store lives at
  # ~/.local/share/containers (96 GiB, verified via `podman info`), i.e. on the
  # `home` subvolume — it survives the migration with no action. Do not add a
  # rootful daemon; that would start a second, empty store under /var.
  virtualisation.podman = {
    enable = true;
    dockerCompat = true; # `docker` -> podman shim
    defaultNetwork.settings.dns_enabled = true;
  };

  virtualisation.containers.enable = true;

  environment.systemPackages = with pkgs; [
    podman-compose
    distrobox
  ];

  # No flatpak, no homebrew, no AppImages on this machine. Everything the
  # Bluefin install got from those channels is re-provisioned from nixpkgs —
  # see package-migration.md for the mapping, reviewed separately.

  # Portals are configured once, in modules/desktop.nix — both compositors
  # need them for more than containers, so they don't belong here.
}
