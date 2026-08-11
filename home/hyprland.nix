{
  config,
  inputs,
  pkgs,
  ...
}:
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
    # noctalia comes up via hl.on("hyprland.start") below — see §7a.

    # ***

    # `settings` is deliberately unused. Hyprland 0.55+ configures in LUA, not
    # hyprlang, and home-manager's `settings` just maps each attribute name to
    # a call `hl.<name>(...)`. That cannot express what this config needs:
    #
    #   "$mod" = "SUPER";        ->  hl.$mod("SUPER")      -- not valid Lua
    #   exec-once = [ "..." ];   ->  hl.exec-once("...")   -- not valid Lua
    #
    # Both are syntax errors, so the whole file fails to load and Hyprland
    # boots into:
    #
    #   emergency mode tripped: A lua config error resulted in no binds
    #   being registered
    #
    # Verified with `luac -p`: "<name> expected near '$'". Writing the Lua
    # directly is the only honest option — dispatchers are hl.dsp.* functions,
    # not strings, and the mod key wants a Lua local.
    #
    # Reference: ${hyprPkgs.hyprland}/share/hypr/hyprland.lua (shipped
    # default) and .../share/hypr/stubs/hl.meta.lua (API types).
    extraConfig = ''
      local mod = "SUPER"

      ---------------------------------------------------------------- outputs
      -- Transcribed from the working GNOME config. Harmless in a VM: the
      -- connector names simply do not match anything and are ignored.
      hl.monitor({ output = "HDMI-A-1", mode = "3840x2160@60", position = "0x0",    scale = 2 })
      hl.monitor({ output = "eDP-1",    mode = "3840x2400@60", position = "0x1080", scale = 2 })

      ---------------------------------------------------------------- input
      hl.config({
        input = {
          touchpad = {
            natural_scroll = true,
            tap_to_click   = true,
          },
        },
      })

      ---------------------------------------------------------------- startup
      -- noctalia is started by the compositor, not by a systemd user unit;
      -- upstream deprecated the systemd approach. Do not also add a unit.
      --
      -- The binary is `noctalia`, NOT `noctalia-shell` — that was the v4
      -- Quickshell-era name and v5 is a standalone native app. It also needs
      -- --daemon; without it the process starts and exits. Absolute store
      -- path because the compositor does not necessarily inherit the
      -- home-manager profile's PATH.
      hl.on("hyprland.start", function()
        hl.exec_cmd("${config.programs.noctalia.package}/bin/noctalia --daemon")
      end)

      ---------------------------------------------------------------- basics
      hl.bind(mod .. " + Return", hl.dsp.exec_cmd("${pkgs.foot}/bin/foot"))
      hl.bind(mod .. " + Q",      hl.dsp.window.close())
      hl.bind(mod .. " + Space",  hl.dsp.exec_cmd("${config.programs.noctalia.package}/bin/noctalia msg panel-toggle launcher"))
      hl.bind(mod .. " + V",      hl.dsp.window.float({ action = "toggle" }))

      ------------------------------------------------------------ screenshot
      -- Hyprland has no built-in capture, unlike niri. grim takes the shot,
      -- slurp picks the region, swappy opens it for annotation.
      hl.bind("Print",
        hl.dsp.exec_cmd("sh -c '${pkgs.grim}/bin/grim -g \"$(${pkgs.slurp}/bin/slurp)\" - | ${pkgs.swappy}/bin/swappy -f -'"))
      hl.bind("SHIFT + Print",
        hl.dsp.exec_cmd("sh -c '${pkgs.grim}/bin/grim - | ${pkgs.swappy}/bin/swappy -f -'"))

      ---------------------------------------------------------------- focus
      -- Same hjkl as the niri session so muscle memory carries between them.
      hl.bind(mod .. " + H", hl.dsp.focus({ direction = "left"  }))
      hl.bind(mod .. " + L", hl.dsp.focus({ direction = "right" }))
      hl.bind(mod .. " + J", hl.dsp.focus({ direction = "down"  }))
      hl.bind(mod .. " + K", hl.dsp.focus({ direction = "up"    }))

      hl.bind(mod .. " + SHIFT + H", hl.dsp.window.move({ direction = "left"  }))
      hl.bind(mod .. " + SHIFT + L", hl.dsp.window.move({ direction = "right" }))

      ---------------------------------------------------------------- media
      -- locked = works at the lock screen; repeating = holds down.
      hl.bind("XF86AudioRaiseVolume",
        hl.dsp.exec_cmd("${pkgs.wireplumber}/bin/wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"),
        { locked = true, repeating = true })
      hl.bind("XF86AudioLowerVolume",
        hl.dsp.exec_cmd("${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),
        { locked = true, repeating = true })
      hl.bind("XF86AudioMute",
        hl.dsp.exec_cmd("${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),
        { locked = true })
      hl.bind("XF86AudioMicMute",
        hl.dsp.exec_cmd("${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),
        { locked = true })

      hl.bind("XF86MonBrightnessUp",
        hl.dsp.exec_cmd("${pkgs.brightnessctl}/bin/brightnessctl -e4 -n2 set 5%+"),
        { locked = true, repeating = true })
      hl.bind("XF86MonBrightnessDown",
        hl.dsp.exec_cmd("${pkgs.brightnessctl}/bin/brightnessctl -e4 -n2 set 5%-"),
        { locked = true, repeating = true })

      hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("${pkgs.playerctl}/bin/playerctl play-pause"), { locked = true })
      hl.bind("XF86AudioNext", hl.dsp.exec_cmd("${pkgs.playerctl}/bin/playerctl next"),       { locked = true })
      hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("${pkgs.playerctl}/bin/playerctl previous"),   { locked = true })
    '';
  };
}
