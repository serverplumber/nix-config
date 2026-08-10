{ config, pkgs, ... }: {
  # Compositor-agnostic desktop bits. niri and Hyprland each bring their own
  # module (modules/niri.nix, modules/hyprland.nix) and each installs a
  # wayland-session desktop file; tuigreet lists whatever it finds, so the
  # choice happens at the login prompt rather than in this file.

  services.greetd = {
    enable = true;
    settings.default_session.command = ''
      ${pkgs.tuigreet}/bin/tuigreet \
        --time \
        --remember \
        --remember-user-session \
        --sessions ${config.services.displayManager.sessionData.desktops}/share/wayland-sessions
    '';
  };

  environment.systemPackages = with pkgs; [
    foot # terminal
    wl-clipboard
  ];
  # No wmenu, no swaybg: noctalia supplies the launcher and the wallpaper.

  fonts.enableDefaultPackages = true;

  # Both compositors want a portal. niri-flake and programs.hyprland each wire
  # their own wlr/hyprland portal; the gtk one is what GTK file pickers and
  # dark-theme preference actually go through, and nothing else provides it.
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };
}
