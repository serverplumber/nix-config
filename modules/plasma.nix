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

  # Plasma normally brings SDDM. It is deliberately NOT enabled — greetd owns
  # login for all three sessions.
  services.displayManager.sddm.enable = false;

  # noctalia is spawned by the niri and Hyprland configs specifically, never
  # globally, so it does not appear in the Plasma session and there is no
  # panel-on-panel conflict.
}
