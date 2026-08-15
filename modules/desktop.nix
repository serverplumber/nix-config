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
  # their own wlr/hyprland portal; kde and gtk cover the rest between them —
  # see the xdg.portal.config comment below for how those two are split.
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

    # niri ships its own portal priority file (niri-26.04's
    # share/xdg-desktop-portal/niri-portals.conf) that prefers
    # `gnome;gtk` for every interface it doesn't list explicitly —
    # including FileChooser. There is no gnome-shell running under niri
    # (or Hyprland), so xdg-desktop-portal-gnome can't actually delegate
    # those calls; it fails with "Delegated FileChooser call failed: The
    # name is not activatable" and, because that failure isn't surfaced
    # as an error back to the caller, the requesting app just hangs
    # waiting on the portal forever — reproduced with Okular under niri,
    # 2026-08-14: launched fine, then any Open dialog froze the whole
    # window. `xdg.portal.config` takes priority over the package's own
    # niri-portals.conf (see nixos/modules/config/xdg/portal.nix), so
    # this replaces it outright rather than patching around it. Applied
    # to both niri and Hyprland for the parity noctalia already gives
    # them; Hyprland ships no portal config of its own to conflict with.
    #
    # Plasma is the other real desktop on this machine (modules/plasma.nix),
    # so kde leads `default` — Okular and other KDE apps get their native
    # Breeze dialogs (Access, FileChooser, Print, Settings, ...) instead of
    # GTK-styled ones. Two interfaces are pinned to gtk instead of trusting
    # the kde-first default:
    #   - Notification: xdg-desktop-portal-kde doesn't implement it at all
    #     (see its .portal file's Interfaces= list) — pinned explicitly
    #     rather than relying on the fallback silently doing the right thing.
    #   - Settings: kde *does* implement this (dark/light + accent color),
    #     but it reads kdeglobals — Plasma's own theme state, which is just
    #     a fallback session here, not what home-manager's GTK dark-mode
    #     config actually manages. Defaulting it to kde would make GTK apps
    #     under niri/Hyprland follow whatever Plasma happens to be set to
    #     instead of the GTK theme this repo configures.
    # gnome-keyring stays as the Secret backend regardless — that one
    # actually runs and is what noctalia's PAM stack already unlocks on
    # login; neither kde nor gtk implement Secret at all.
    config = {
      niri = {
        default = [
          "kde"
          "gtk"
        ];
        "org.freedesktop.impl.portal.Notification" = [ "gtk" ];
        "org.freedesktop.impl.portal.Settings" = [ "gtk" ];
        "org.freedesktop.impl.portal.Secret" = [ "gnome-keyring" ];
      };
      Hyprland = {
        default = [
          "kde"
          "gtk"
        ];
        "org.freedesktop.impl.portal.Notification" = [ "gtk" ];
        "org.freedesktop.impl.portal.Settings" = [ "gtk" ];
        "org.freedesktop.impl.portal.Secret" = [ "gnome-keyring" ];
      };
    };
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
