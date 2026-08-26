{ pkgs, ... }:
{
  # Third greeter session, as a known-good fallback. Plasma is the heaviest
  # thing in this config by a wide margin, and that is the point: if niri or
  # Hyprland misbehave on first boot, this is a working desktop to debug from
  # rather than a TTY.
  #
  # It installs its own wayland-session desktop file, so the greeter lists it
  # alongside the other two with no extra wiring (modules/desktop.nix).
  services.desktopManager.plasma6.enable = true;

  # Plasma pulls in a pile of KDE applications by default. Kate is not wanted
  # — helix is the editor here (home/dev.nix).
  environment.plasma6.excludePackages = with pkgs.kdePackages; [ kate ];

  # SDDM is Plasma's own display manager and it DOES own login here, for all
  # three sessions — but it is enabled in modules/desktop.nix rather than
  # from this file, because it greets niri and Hyprland too and is not a
  # Plasma-specific concern. Do not also set it here: two definitions of
  # `services.displayManager.sddm.enable` conflict.
  #
  # (It was pinned to `false` here until 2026-08-25, when greetd + ReGreet
  # owned login instead. See the greeter history in modules/desktop.nix.)

  # noctalia is spawned by the niri and Hyprland configs specifically, never
  # globally, so it does not appear in the Plasma session and there is no
  # panel-on-panel conflict.
}
