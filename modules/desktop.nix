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

  # Graphical greeter: SDDM. It enumerates the wayland-sessions directory
  # itself, so niri, Hyprland and Plasma appear with no per-session wiring —
  # same as the two greeters before it.
  #
  # ***
  #
  # GREETER HISTORY, because this is the third one and the reasons matter:
  #
  # 1. tuigreet (until 2026-08-10). A terminal UI, so nothing to render and
  #    nothing to crash — but the maintained NotAShelf fork listed every
  #    session twice (8 entries for 4 .desktop files; dropping --sessions
  #    yielded 0 rather than 4, so the duplication was the greeter's own).
  #
  # 2. ReGreet (until 2026-08-25). GTK4 inside a cage compositor. It froze
  #    hard: regreet 0.4.0 links libgstplay/libgstgl and pushes *every*
  #    background through a GStreamer GstPlay pipeline so video wallpapers
  #    can work — a still PNG takes the identical path. On this hybrid
  #    Intel+NVIDIA box that pipeline's GL context thread livelocked, thread
  #    `gstglcontext` burning 916s of CPU over 900s of wall clock while the
  #    GTK main thread sat at zero context switches, i.e. fully blocked. The
  #    greeter painted, accepted a username and session, then froze the
  #    instant the password prompt appeared: /var/log/regreet/log ended at
  #    "greetd asks for a secret auth input: Password:" with nothing after,
  #    and greetd's session worker slept forever waiting for a password that
  #    was never sent. Measured 2026-08-25.
  #
  # The through-line is that greetd itself never failed — it is a small
  # daemon that does PAM and session spawning correctly. Every failure was in
  # a *greeter*, and greetd is a bring-your-own-greeter system, which makes
  # the integration our problem. SDDM ships as one tested unit with an
  # upstream that owns the seams, which is the whole reason for the move.
  #
  # If the goal is instead to delete the graphical greeter entirely while
  # keeping a password prompt and per-session choice, that design is written
  # up in docs/greeterless.md — it goes back to greetd, deliberately.
  services.displayManager.sddm = {
    enable = true;

    wayland = {
      enable = true;

      # nixpkgs defaults this to weston. kwin is the better choice here for
      # two reasons: Plasma already puts kwin in this closure so it costs
      # nothing, and kwin is a full compositor with real multi-GPU handling
      # (it ships NVIDIA-specific paths — KWIN_DRM_ALLOW_NVIDIA_COLORSPACE
      # and friends) rather than the minimal single-purpose compositors the
      # previous two greeters ran on.
      #
      # Note nixpkgs labels the whole `wayland` block "experimental Wayland
      # support". If it misbehaves, the fallbacks in descending order of
      # violence are: pin the greeter to the iGPU with
      #   systemd.services.display-manager.environment.KWIN_DRM_DEVICES =
      #     "/dev/dri/by-path/pci-0000:00:02.0-card";
      # (kwin's equivalent of the WLR_DRM_DEVICES pin cage used), switch
      # `compositor` to "weston", or set `wayland.enable = false` for the
      # X11 greeter, which is the oldest and best-tested path SDDM has and
      # still launches Wayland sessions perfectly well.
      compositor = "kwin";
    };
  };

  # Deliberately NOT pinning the greeter to the Intel iGPU, unlike the cage
  # setup this replaces.
  #
  # This laptop has two DRM devices: 00:02.0 Intel Iris Xe, which owns the
  # internal eDP-1 panel and is boot_vga, and 01:00.0 NVIDIA RTX 4070, which
  # owns HDMI-A-1 and DP-5/DP-6 — so every external screen hangs off the
  # dGPU. cage had to be pinned because wlroots multi-GPU against the NVIDIA
  # driver is a known-fragile path, and the cost was that the greeter could
  # never appear on an external display. kwin handles multi-GPU properly, so
  # it gets to make that choice itself and the greeter can light up HDMI.
  # The KWIN_DRM_DEVICES escape hatch above is there if that bet is wrong.

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

  # NB: the /var/lib/regreet and /var/cache/regreet tmpfiles rules that used
  # to live here are gone with ReGreet. SDDM provisions its own state under
  # /var/lib/sddm via its systemd unit and needs no help. If you ever go back
  # to greetd (see docs/greeterless.md), the greeter's state directory has to
  # be created by hand again — the nixpkgs regreet module never did it, and
  # the failure mode is a greeter that renders but ignores all input.
}
