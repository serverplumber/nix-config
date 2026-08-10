{ inputs, pkgs, ... }:
let
  hyprPkgs = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  # The home-manager module for Hyprland ships with home-manager itself, so
  # there is nothing to import — unlike niri and noctalia.
  wayland.windowManager.hyprland = {
    enable = true;
    package = hyprPkgs.hyprland;
    portalPackage = hyprPkgs.xdg-desktop-portal-hyprland;

    # systemd.enable is left at its default. It exports the session
    # environment into the systemd user manager; it does NOT start noctalia.
    # noctalia comes up via exec-once below — see §7a.

    settings = {
      "$mod" = "SUPER";

      # Same layout as home/niri.nix, transcribed from the working GNOME
      # config on Bluefin. Format: name, resolution@rate, position, scale.
      # Positions are logical (post-scale), so the external's 1080 logical
      # height is what pushes eDP-1 down.
      monitor = [
        "HDMI-A-1, 3840x2160@60, 0x0, 2"
        "eDP-1,    3840x2400@60, 0x1080, 2"
      ];

      # Same rule as niri: the compositor starts the shell, not systemd.
      exec-once = [ "noctalia-shell" ];

      input = {
        touchpad = {
          natural_scroll = true;
          tap-to-click = true;
        };
      };

      bind = [
        # Basics
        "$mod, Return, exec, foot"
        "$mod, Q, killactive"
        "$mod, Space, exec, noctalia-shell ipc call launcher toggle"
        "$mod, F, fullscreen"
        "$mod, V, togglefloating"

        # Focus — same hjkl as the niri session, so muscle memory carries
        "$mod, H, movefocus, l"
        "$mod, L, movefocus, r"
        "$mod, J, movefocus, d"
        "$mod, K, movefocus, u"
        "$mod SHIFT, H, movewindow, l"
        "$mod SHIFT, L, movewindow, r"
      ];

      # bindl = works while the session is locked; binde = repeats on hold.
      bindle = [
        ", XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+ -l 1.0"
        ", XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
        ", XF86MonBrightnessUp,  exec, brightnessctl set 5%+"
        ", XF86MonBrightnessDown, exec, brightnessctl set 5%-"
      ];

      bindl = [
        ", XF86AudioMute,    exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
        ", XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
        ", XF86AudioPlay, exec, playerctl play-pause"
        ", XF86AudioNext, exec, playerctl next"
        ", XF86AudioPrev, exec, playerctl previous"
      ];
    };
  };
}
