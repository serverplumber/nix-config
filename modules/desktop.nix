{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Compositor-agnostic desktop bits. niri and Hyprland each bring their own
  # module (modules/niri.nix, modules/hyprland.nix) and each installs a
  # wayland-session desktop file; the greeter lists whatever it finds, so the
  # choice happens at the login prompt rather than in this file.

  # Graphical greeter. ReGreet is GTK4/libadwaita and runs inside a cage
  # (a single-window Wayland compositor); the module wires greetd, cage and
  # the session list together, so `services.greetd.settings.default_session`
  # must NOT be set by hand here — the module owns it, and two definitions
  # conflict.
  #
  # ***
  #
  # Replaced tuigreet 2026-08-10. tuigreet is a terminal UI — text only, no
  # chrome — and the maintained NotAShelf fork additionally listed every
  # session twice (8 entries for 4 sessions; the directory contains exactly
  # 4 .desktop files, and dropping --sessions yielded 0 rather than 4, so the
  # duplication was the greeter's own). ReGreet enumerates sessions itself
  # and needs no --sessions plumbing at all.
  services.greetd.enable = true;

  services.displayManager.regreet = {
    enable = true;

    # Cage (the compositor the greeter runs in) has no output-mirroring mode
    # — only "extend" (default) or "last". "extend" treats both monitors as
    # one wide virtual canvas and centers the login box across the combined
    # width, so on a two-screen setup the box straddles the seam between
    # them. "last" confines cage to a single output (the last one it
    # enumerates), which keeps the box whole on one screen instead.
    cageArgs = [
      "-s"
      "-d"
      "-m"
      "last"
    ];

    # ***
    #
    # THEMING NOTES — the two things that trip people up:
    #
    # 1. ReGreet is GTK **4** (4.22.4) and does NOT link libadwaita, so GTK
    #    themes really do apply. But almost everything on gnome-look.org is a
    #    GTK **3** theme, and those have no effect here. GRUB themes are a
    #    different thing again — they theme the bootloader, not this.
    #
    # 2. The greeter runs as the `greeter` user, and /home/stablefly is mode
    #    700. A background at ~/Pictures/foo.jpg will silently fail to load.
    #    The path must be world-readable, which in practice means the nix
    #    store. Hence the wallpaper below coming from a package rather than
    #    a home directory.
    #
    # To use your own image, copy it into the repo and reference it as a
    # store path — `path = "${./assets/wallpaper.jpg}"` — which makes nix
    # copy it in with world-readable permissions. It must be git-tracked.

    font = {
      name = "Inter";
      package = pkgs.inter;
      size = 14;
    };

    cursorTheme = {
      name = "Bibata-Modern-Classic";
      package = pkgs.bibata-cursors;
    };

    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };

    settings = {
      background = {
        path = "${pkgs.nixos-artwork.wallpapers.catppuccin-mocha}/share/backgrounds/nixos/nixos-wallpaper-catppuccin-mocha.png";
        fit = "Cover";
      };

      GTK = {
        application_prefer_dark_theme = true;
        cursor_blink = true;
      };
    };

    # Fine-grained control lives here. GTK4 CSS, applied on top of the theme —
    # this is the reliable lever when a theme does not do what you want.
    extraCss = ''
      window {
        background-color: rgba(30, 30, 46, 0.35);
      }

      /* The login box itself: dark, rounded, slightly translucent so the
         wallpaper reads through. */
      .background,
      box.vertical > grid {
        background-color: rgba(24, 24, 37, 0.85);
        border-radius: 16px;
        padding: 24px;
      }

      entry, button {
        border-radius: 8px;
        min-height: 34px;
      }
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

  # ReGreet stores last-user/last-session state here. The nixpkgs module
  # enables the greeter but does not provision the directory,
  # so regreet aborts at startup and cage is left composing an empty surface
  # which presents as a greeter that renders but ignores all input.
  systemd.tmpfiles.rules = [
    "d /var/lib/regreet 0755 greeter greeter - -X"
    "d /var/cache/regreet 0755 greeter greeter - -X"
  ];
}
