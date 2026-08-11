{
  config,
  pkgs,
  ...
}:
{
  # DO NOT import inputs.niri.homeModules.niri here.
  #
  # An earlier version did, on the assumption that the module system dedupes
  # by key so a second import would be free. It is not: niri-flake's NixOS
  # module pulls the HM module in via its own nixos/common.nix under a
  # different key, so importing it again declares every option twice —
  #
  #   error: The option `home-manager.users.stablefly.programs.niri.finalConfig'
  #   in `.../nixos/common.nix' is already declared in `.../home/niri.nix'.
  #
  # ***
  #
  # The NixOS path gets the module automatically. The standalone
  # homeConfigurations output has no NixOS module to do that, so flake.nix
  # adds it there — and only there.

  # Must be set HERE as well as in modules/niri.nix. The home-manager module
  # carries its own `programs.niri.package`, and homeConfigurations.stablefly
  # is standalone — it never sees the NixOS module, so the NixOS-side setting
  # does not reach it. Same reason as there: niri-flake's niri-stable fails to
  # evaluate against our nixpkgs pin (libdisplay-info_0_2 removed).
  programs.niri.package = pkgs.niri;

  programs.niri.settings = {
    # Display layout, transcribed from the working GNOME config on Bluefin
    # (~/.config/monitors.xml). External above internal, both HiDPI at scale 2:
    #   HDMI-A-1  logical 1920x1080 at (0,0)      <- primary, LG Ultra HD
    #   eDP-1     logical 1920x1200 at (0,1080)
    # GNOME calls the external "HDMI-1"; the DRM connector name niri wants is
    # "HDMI-A-1".
    outputs = {
      "HDMI-A-1" = {
        mode = {
          width = 3840;
          height = 2160;
          refresh = 60.0;
        };
        scale = 2.0;
        position = {
          x = 0;
          y = 0;
        };
      };
      "eDP-1" = {
        mode = {
          width = 3840;
          height = 2400;
          refresh = 60.0;
        };
        scale = 2.0;
        position = {
          x = 0;
          y = 1080;
        };
      };
    };

    # Deliberately NOT pinning the render device — see O-10a.
    #
    # Left unset, niri renders on the Intel iGPU and the 4070 is powered only
    # when something needs it: a display attached to it, or an offloaded app.
    # Combined with powerManagement.finegrained that is automatic dock-aware
    # behaviour — dGPU up when the monitor is plugged in, runtime-suspended
    # when it is not. GNOME does exactly this today and is smooth.
    #
    # The cost is the cross-GPU copy for HDMI-A-1 (niri#3674). If the external
    # display stutters, uncomment the line below — it pins rendering to the
    # 4070, which fixes the stutter but keeps the dGPU awake permanently,
    # undocked too. Restarting the session is required either way; it is not a
    # live setting.
    #
    # debug.render-drm-device = "/dev/dri/by-path/pci-0000:01:00.0-render";
    #
    # ***
    #
    # noctalia is started by the compositor, not by a systemd user unit.
    # Upstream deprecated the systemd approach in favour of this. Do not also
    # add a unit — you get two shells.
    spawn-at-startup = [
      {
        command = [
          "${config.programs.noctalia.package}/bin/noctalia"
          "--daemon"
        ];
      }
    ];

    input.touchpad = {
      tap = true;
      natural-scroll = true;
    };

    # Absolute store paths throughout: a compositor does not reliably inherit
    # the home-manager profile's PATH, and a bare name that fails to resolve
    # produces no error — the key simply does nothing. Same reason noctalia is
    # spelled out above.
    binds = with config.lib.niri.actions; {
      # Basics
      "Mod+Return".action = spawn "${pkgs.foot}/bin/foot";
      "Mod+Q".action = close-window;
      "Mod+Space".action =
        spawn "${config.programs.noctalia.package}/bin/noctalia" "msg" "panel-toggle"
          "launcher";

      # Screenshots. niri does have native screenshot actions in its KDL, but
      # niri-flake's typed `config.lib.niri.actions` does not expose them —
      # only `do-screen-transition` matches. Rather than bypass the typed API,
      # use the same grim/slurp pipeline as the Hyprland session, so both
      # behave identically.
      "Print".action =
        spawn "sh" "-c"
          "${pkgs.grim}/bin/grim -g \"$(${pkgs.slurp}/bin/slurp)\" - | ${pkgs.swappy}/bin/swappy -f -";
      "Shift+Print".action = spawn "sh" "-c" "${pkgs.grim}/bin/grim - | ${pkgs.swappy}/bin/swappy -f -";

      # Column/scroll navigation — the reason to run niri at all
      "Mod+H".action = focus-column-left;
      "Mod+L".action = focus-column-right;
      "Mod+J".action = focus-window-down;
      "Mod+K".action = focus-window-up;
      "Mod+Shift+H".action = move-column-left;
      "Mod+Shift+L".action = move-column-right;
      "Mod+F".action = maximize-column;
      "Mod+Shift+F".action = fullscreen-window;
      "Mod+V".action = toggle-window-floating;

      # Volume. allow-when-locked so they work at the lock screen.
      "XF86AudioRaiseVolume" = {
        allow-when-locked = true;
        action = spawn "${pkgs.wireplumber}/bin/wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%+" "-l" "1.0";
      };
      "XF86AudioLowerVolume" = {
        allow-when-locked = true;
        action = spawn "${pkgs.wireplumber}/bin/wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%-";
      };
      "XF86AudioMute" = {
        allow-when-locked = true;
        action = spawn "${pkgs.wireplumber}/bin/wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle";
      };
      "XF86AudioMicMute" = {
        allow-when-locked = true;
        action = spawn "${pkgs.wireplumber}/bin/wpctl" "set-mute" "@DEFAULT_AUDIO_SOURCE@" "toggle";
      };

      # Backlight
      "XF86MonBrightnessUp" = {
        allow-when-locked = true;
        action = spawn "${pkgs.brightnessctl}/bin/brightnessctl" "set" "5%+";
      };
      "XF86MonBrightnessDown" = {
        allow-when-locked = true;
        action = spawn "${pkgs.brightnessctl}/bin/brightnessctl" "set" "5%-";
      };

      # Transport
      "XF86AudioPlay" = {
        allow-when-locked = true;
        action = spawn "${pkgs.playerctl}/bin/playerctl" "play-pause";
      };
      "XF86AudioNext" = {
        allow-when-locked = true;
        action = spawn "${pkgs.playerctl}/bin/playerctl" "next";
      };
      "XF86AudioPrev" = {
        allow-when-locked = true;
        action = spawn "${pkgs.playerctl}/bin/playerctl" "previous";
      };
    };

  };
}
