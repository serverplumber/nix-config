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
      --
      -- eDP-1 gets HDR back (migration doc O-11): GNOME's monitors.xml had
      -- `colormode: bt2100` on the internal panel, and neither compositor
      -- carried that over on migration. cm = "hdredid" is Hyprland's PQ/HDR
      -- transfer function using the panel's own EDID-reported primaries
      -- (more accurate than generic BT.2020 primaries via plain "hdr", and
      -- like both HDR modes it auto-falls-back to sRGB if the panel doesn't
      -- actually report HDR support — see src/output/Monitor.cpp in the
      -- Hyprland source). bitdepth = 10 alongside it: HDR at 8-bit bands
      -- visibly. HDMI-A-1 (external) is left alone — unconfirmed whether
      -- that display supports HDR at all.
      --
      -- This only does anything in this (Hyprland) session — niri as
      -- currently pinned has no HDR/color-management config exposed at all,
      -- see home/gui.nix's mpv comment.
      hl.monitor({ output = "HDMI-A-1", mode = "3840x2160@60", position = "0x0",    scale = 2 })
      hl.monitor({ output = "eDP-1",    mode = "3840x2400@60", position = "0x1080", scale = 2, bitdepth = 10, cm = "hdredid" })

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
      --
      -- This mirrors Hyprland's own shipped example hyprland.lua bind-for-
      -- bind (see ${hyprPkgs.hyprland}/share/hypr/hyprland.lua) — with only
      -- the program names swapped for what's actually installed here: foot
      -- for the terminal, noctalia for the launcher (there is no separate
      -- app-launcher package on this machine; dolphin is already installed
      -- as the file manager, so SUPER+E is unchanged). Deliberate: until
      -- it's decided whether niri/Hyprland stick around at all, the
      -- bindings should match what the Hyprland wiki teaches, not a
      -- personal remap.
      --
      -- Note there is no default screenshot bind and no default lock bind —
      -- Hyprland's example config doesn't set either (niri's does, via
      -- Super+Alt+L / Print in home/niri.nix). Ask if you want them added.
      local terminal = "${pkgs.foot}/bin/foot"
      local fileManager = "${pkgs.kdePackages.dolphin}/bin/dolphin"
      local menu = "${config.programs.noctalia.package}/bin/noctalia msg panel-toggle launcher"

      hl.bind(mod .. " + Q", hl.dsp.exec_cmd(terminal))
      hl.bind(mod .. " + C", hl.dsp.window.close())
      -- Shipped default text was "hyprctl dispatch 'hl.dsp.exit()'", which
      -- is not a valid dispatcher — normalized to the real exit dispatcher.
      hl.bind(mod .. " + M", hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch exit"))
      hl.bind(mod .. " + E", hl.dsp.exec_cmd(fileManager))
      hl.bind(mod .. " + V", hl.dsp.window.float({ action = "toggle" }))
      hl.bind(mod .. " + R", hl.dsp.exec_cmd(menu))
      hl.bind(mod .. " + P", hl.dsp.window.pseudo())
      hl.bind(mod .. " + J", hl.dsp.layout("togglesplit"))    -- dwindle only

      -- Move focus with mod + arrow keys
      hl.bind(mod .. " + left",  hl.dsp.focus({ direction = "left" }))
      hl.bind(mod .. " + right", hl.dsp.focus({ direction = "right" }))
      hl.bind(mod .. " + up",    hl.dsp.focus({ direction = "up" }))
      hl.bind(mod .. " + down",  hl.dsp.focus({ direction = "down" }))

      -- Switch workspaces with mod + [0-9]
      -- Move active window to a workspace with mod + SHIFT + [0-9]
      for i = 1, 10 do
        local key = i % 10 -- 10 maps to key 0
        hl.bind(mod .. " + " .. key,         hl.dsp.focus({ workspace = i}))
        hl.bind(mod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
      end

      -- Special workspace (scratchpad)
      hl.bind(mod .. " + S",         hl.dsp.workspace.toggle_special("magic"))
      hl.bind(mod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

      -- Scroll through existing workspaces with mod + scroll
      hl.bind(mod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
      hl.bind(mod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

      -- Move/resize windows with mod + LMB/RMB and dragging
      hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
      hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

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
        { locked = true, repeating = true })
      hl.bind("XF86AudioMicMute",
        hl.dsp.exec_cmd("${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),
        { locked = true, repeating = true })

      hl.bind("XF86MonBrightnessUp",
        hl.dsp.exec_cmd("${pkgs.brightnessctl}/bin/brightnessctl -e4 -n2 set 5%+"),
        { locked = true, repeating = true })
      hl.bind("XF86MonBrightnessDown",
        hl.dsp.exec_cmd("${pkgs.brightnessctl}/bin/brightnessctl -e4 -n2 set 5%-"),
        { locked = true, repeating = true })

      hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("${pkgs.playerctl}/bin/playerctl next"),       { locked = true })
      hl.bind("XF86AudioPause", hl.dsp.exec_cmd("${pkgs.playerctl}/bin/playerctl play-pause"), { locked = true })
      hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("${pkgs.playerctl}/bin/playerctl play-pause"), { locked = true })
      hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("${pkgs.playerctl}/bin/playerctl previous"),   { locked = true })
    '';
  };
}
