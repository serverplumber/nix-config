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
    # Known upstream bug, still unresolved: after suspend/resume, HDMI-A-1
    # (the only output on the 4070/card0 — see above) can come back stuck.
    # niri spams "Page flip commit failed on device /dev/dri/card0 (Invalid
    # argument (os error 22))" — observed 2756 times in ~36s on 2026-08-15 —
    # then gives up and the output just stays dark. This is niri-wm/niri#3384
    # (same error signature, same NVIDIA-hybrid shape), open, no fix.
    #
    # niri does NOT self-recover from this — confirmed by testing, not just
    # log-reading: the connector disconnect/reconnect that eventually shows
    # up in the log is from physically unplugging and replugging the cable,
    # not from niri retrying its way out on its own. Software force-redetect
    # (writing `detect` to the connector's /sys/class/drm/.../status) might
    # work instead of a physical replug, but that needs root and is
    # untested — not wired up. For now the fix is unplug/replug the cable,
    # or log out of niri entirely (the workaround reported on #3384).
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

    # Terminals open at 1/3 width instead of niri's 50% preset: the plain
    # foot terminal (Mod+T) and the foot instance gui.nix's Helix.desktop
    # spawns with --app-id=helix for editing in a terminal.
    window-rules = [
      {
        matches = [
          { app-id = "^foot$"; }
          { app-id = "^helix$"; }
        ];
        default-column-width = {
          proportion = 1.0 / 3.0;
        };
      }
    ];

    # Absolute store paths throughout: a compositor does not reliably inherit
    # the home-manager profile's PATH, and a bare name that fails to resolve
    # produces no error — the key simply does nothing. Same reason noctalia is
    # spelled out above.
    #
    # ***
    #
    # This mirrors niri's own shipped default-config.kdl bind-for-bind — see
    # `default-config.kdl` in the niri source, or run `niri validate` — with
    # only the program names swapped for what's actually installed here:
    # foot for the terminal, noctalia for the launcher and lock (there is no
    # separate app launcher or screen locker package on this machine). This
    # is deliberate: until it's decided whether niri/Hyprland stick around at
    # all, the bindings should match what any niri tutorial or the wiki
    # teaches, not a personal remap. Press Mod+Shift+Slash for the built-in
    # cheat sheet ("Important Hotkeys") listing all of these live.
    binds = with config.lib.niri.actions; {
      "Mod+Shift+Slash".action = show-hotkey-overlay;

      "Mod+T".action = spawn "${pkgs.foot}/bin/foot";
      "Mod+D".action =
        spawn "${config.programs.noctalia.package}/bin/noctalia" "msg" "panel-toggle"
          "launcher";
      # `noctalia msg lock` is stale — noctalia 5.0 dropped the bare `lock`
      # command in favour of `session lock` (confirmed: the old form now
      # errors "unknown command"). Fixed while moving this off Super+Alt+L.
      # Mod+Shift+Backspace deliberately left alone — reserved in case
      # Shift+Backspace ever becomes Delete on the QMK layer.
      #
      # ⚠️ modules/sdbackup.nix mkForce's this bind to lock *and* raise the
      # "your backup card isn't in the machine" reminder. Editing the line
      # below will therefore appear to do nothing — change it there, not here.
      # Mod+Alt+Backspace (lock + caffeine) is untouched by that module.
      #
      # caffeine-disable after lock: a plain lock overrides whatever caffeine
      # state was left over from an earlier Mod+Alt+Backspace, same reasoning
      # as modules/sdbackup.nix's lockThen — a lock key should leave caffeine
      # in a known state, not whatever it happened to be.
      "Mod+Backspace".action = spawn-sh ''
        ${config.programs.noctalia.package}/bin/noctalia msg session lock
        ${config.programs.noctalia.package}/bin/noctalia msg caffeine-disable
      '';
      "Mod+Alt+Backspace".action = spawn-sh ''
        ${config.programs.noctalia.package}/bin/noctalia msg session lock
        ${config.programs.noctalia.package}/bin/noctalia msg caffeine-enable
      '';

      # niri-flake's typed actions API has no `screenshot`/`screenshot-screen`/
      # `screenshot-window` entries (absent from its memo-binds.nix cache),
      # but any action can be invoked via `niri msg action <name>` — same
      # effect as a native KDL bind, just spawned instead of typed. This
      # opens niri's own interactive screenshot UI; no grim/slurp/swappy
      # needed.
      # Print is NOT on the Preonic base layer — CLAUDE.md flags it as
      # unconfirmed alongside Home/End/Page and Delete — so the family lives
      # on Mod+P. Mod+Shift+P (power-off-monitors, further down) is a
      # different chord and does not collide.
      "Mod+P".action = spawn "niri" "msg" "action" "screenshot";
      "Mod+Ctrl+P".action = spawn "niri" "msg" "action" "screenshot-screen";
      "Mod+Alt+P".action = spawn "niri" "msg" "action" "screenshot-window";

      "Mod+Q" = {
        repeat = false;
        action = close-window;
      };

      # ------------------------------------------------------ navigation
      #
      # One scheme, shared verbatim with home/hyprland.nix, built ONLY from
      # keys that exist on the Preonic's base layer (CLAUDE.md "Keyboard"):
      # letters, digits, Esc/Shift/Ctrl/Alt/Super/Backspace and the arrows.
      # Brackets, Minus/Equal, Home/End, Page_Up/Down, Print and Delete are
      # NOT on that layer — everything that used them has been moved onto
      # reachable keys or dropped; the record is at the bottom of this block.
      #
      # Two rules cover the whole grid:
      #
      #   hjkl = focus / primary        arrows = move
      #   h/l  = horizontal (columns)   j/k    = vertical (window stack)
      #
      # and the modifier picks the scope:
      #
      #   Mod            this workspace's columns and windows
      #   Mod+Alt        the desktop (workspace) axis
      #   Mod+Ctrl       geometry: resize, plus consume/expel on the arrows
      #   Mod+Ctrl+Alt   monitors
      #
      # This replaces the previous vi-remap, which put J/K on the *workspace*
      # axis. That was the right call while Hyprland was on dwindle and had
      # no column concept to mirror; now that both sessions run a scrolling
      # column layout, J/K mean within-column focus in both and the desktop
      # axis has moved to Mod+Alt+J/K.

      "Mod+H".action = focus-column-left;
      "Mod+L".action = focus-column-right;
      "Mod+J".action = focus-window-down;
      "Mod+K".action = focus-window-up;

      "Mod+Left".action = move-column-left;
      "Mod+Right".action = move-column-right;
      "Mod+Up".action = move-window-up;
      "Mod+Down".action = move-window-down;

      # Desktop axis. Mod+Alt+H/L and Mod+Alt+Left/Right are deliberately
      # left unbound — the workspace axis is vertical only, and monitors
      # moved to Mod+Ctrl+Alt below.
      "Mod+Alt+J".action = focus-workspace-down;
      "Mod+Alt+K".action = focus-workspace-up;
      "Mod+Alt+Down".action = move-column-to-workspace-down;
      "Mod+Alt+Up".action = move-column-to-workspace-up;

      # Geometry. hjkl resizes; the arrows restructure columns instead.
      # Hyprland's equivalent of the width pair is layout("colresize ±0.1"),
      # whose argument is a fraction of screen width — the same 10% step.
      # Its height pair is pixels rather than a percentage, so that half is
      # only approximately in step (see home/hyprland.nix).
      "Mod+Ctrl+H".action = set-column-width "-10%";
      "Mod+Ctrl+L".action = set-column-width "+10%";
      "Mod+Ctrl+K".action = set-window-height "+10%";
      "Mod+Ctrl+J".action = set-window-height "-10%";

      "Mod+Ctrl+Left".action = consume-or-expel-window-left;
      "Mod+Ctrl+Right".action = consume-or-expel-window-right;

      # No Hyprland counterpart: its scrolling layout has no
      # focus-column-first/last message, so these two are niri-only and
      # Mod+Ctrl+Up/Down is left unbound there rather than faked.
      "Mod+Ctrl+Up".action = focus-column-first;
      "Mod+Ctrl+Down".action = focus-column-last;

      # Monitors. Directional rather than next/previous so the binds are
      # generic — niri resolves each against the real physical arrangement
      # and a direction with no monitor in it simply does nothing. The
      # displays are currently stacked VERTICALLY (see `outputs` above), so
      # today K/J and Up/Down are the live pair and H/L are inert; a
      # side-by-side setup would light H/L up with no config change.
      "Mod+Ctrl+Alt+H".action = focus-monitor-left;
      "Mod+Ctrl+Alt+L".action = focus-monitor-right;
      "Mod+Ctrl+Alt+J".action = focus-monitor-down;
      "Mod+Ctrl+Alt+K".action = focus-monitor-up;
      "Mod+Ctrl+Alt+Left".action = move-column-to-monitor-left;
      "Mod+Ctrl+Alt+Right".action = move-column-to-monitor-right;
      "Mod+Ctrl+Alt+Down".action = move-column-to-monitor-down;
      "Mod+Ctrl+Alt+Up".action = move-column-to-monitor-up;

      # Letter aliases for the desktop axis, kept because U/I are base-layer
      # and these were the reachable path before Mod+Alt+J/K existed.
      "Mod+U".action = focus-workspace-down;
      "Mod+I".action = focus-workspace-up;
      "Mod+Ctrl+U".action = move-column-to-workspace-down;
      "Mod+Ctrl+I".action = move-column-to-workspace-up;
      "Mod+Shift+U".action = move-workspace-down;
      "Mod+Shift+I".action = move-workspace-up;

      # ---------------------------------------------- removed binds, and why
      #
      # Unreachable on the Preonic base layer — rehomed or dropped:
      #
      #   Mod+BracketLeft/Right   consume-or-expel-window-left/right
      #                             -> Mod+Ctrl+Left/Right
      #   Mod+Minus / Mod+Equal   set-column-width -/+10%
      #                             -> Mod+Ctrl+H / Mod+Ctrl+L
      #   Mod+Shift+Minus/Equal   set-window-height -/+10%
      #                             -> Mod+Ctrl+J / Mod+Ctrl+K
      #   Mod+Home / Mod+End      focus-column-first/last
      #                             -> Mod+Ctrl+Up / Mod+Ctrl+Down
      #   Mod+Ctrl+Home/End       move-column-to-first/last
      #                             -> DROPPED, no replacement
      #   Mod+Page_Down/Up        focus-workspace-down/up
      #                             -> Mod+Alt+J/K (and Mod+U/I above)
      #   Mod+Ctrl+Page_Down/Up   move-column-to-workspace-down/up
      #                             -> Mod+Alt+Down/Up (and Mod+Ctrl+U/I)
      #   Mod+Shift+Page_Down/Up  move-workspace-down/up
      #                             -> Mod+Shift+U / Mod+Shift+I
      #   Print / Ctrl+Print /    screenshot / -screen / -window
      #     Alt+Print               -> Mod+P / Mod+Ctrl+P / Mod+Alt+P
      #   Ctrl+Alt+Delete         quit
      #                             -> DROPPED; Mod+Shift+E already quits
      #
      # Reachable, but reassigned by the scheme above:
      #
      #   Mod+Ctrl+{HJKL,arrows}  move-column-*/move-window-* -> Mod+arrows
      #   Mod+Shift+{H,L,arrows}  focus-monitor-*  -> Mod+Ctrl+Alt+hjkl
      #   Mod+Shift+Ctrl+*        move-column-to-monitor-*
      #                             -> Mod+Ctrl+Alt+arrows
      #   Mod+Shift+J/K           move-column-to-workspace-down/up
      #                             -> Mod+Alt+Down/Up
      #   Mod+Alt+{HJKL,arrows}   move-workspace-to-monitor-*
      #                             -> DROPPED, no new home. Mod+Shift+H/L
      #                                and Mod+Shift+arrows are now free if
      #                                it ever needs one.
      "Mod+WheelScrollDown" = {
        cooldown-ms = 150;
        action = focus-workspace-down;
      };
      "Mod+WheelScrollUp" = {
        cooldown-ms = 150;
        action = focus-workspace-up;
      };
      "Mod+Ctrl+WheelScrollDown" = {
        cooldown-ms = 150;
        action = move-column-to-workspace-down;
      };
      "Mod+Ctrl+WheelScrollUp" = {
        cooldown-ms = 150;
        action = move-column-to-workspace-up;
      };
      "Mod+WheelScrollRight".action = focus-column-right;
      "Mod+WheelScrollLeft".action = focus-column-left;
      "Mod+Ctrl+WheelScrollRight".action = move-column-right;
      "Mod+Ctrl+WheelScrollLeft".action = move-column-left;
      "Mod+Shift+WheelScrollDown".action = focus-column-right;
      "Mod+Shift+WheelScrollUp".action = focus-column-left;
      "Mod+Ctrl+Shift+WheelScrollDown".action = move-column-right;
      "Mod+Ctrl+Shift+WheelScrollUp".action = move-column-left;

      "Mod+1".action = focus-workspace 1;
      "Mod+2".action = focus-workspace 2;
      "Mod+3".action = focus-workspace 3;
      "Mod+4".action = focus-workspace 4;
      "Mod+5".action = focus-workspace 5;
      "Mod+6".action = focus-workspace 6;
      "Mod+7".action = focus-workspace 7;
      "Mod+8".action = focus-workspace 8;
      "Mod+9".action = focus-workspace 9;
      # "move-column-to-workspace" (indexed) is another gap in niri-flake's
      # typed actions — same situation as the screenshot actions above; only
      # the "-down"/"-up" relative variants are typed. Use `niri msg action`
      # directly, which supports the indexed form (`niri msg action
      # move-column-to-workspace --help` confirms it takes an index or name).
      "Mod+Ctrl+1".action = spawn "niri" "msg" "action" "move-column-to-workspace" "1";
      "Mod+Ctrl+2".action = spawn "niri" "msg" "action" "move-column-to-workspace" "2";
      "Mod+Ctrl+3".action = spawn "niri" "msg" "action" "move-column-to-workspace" "3";
      "Mod+Ctrl+4".action = spawn "niri" "msg" "action" "move-column-to-workspace" "4";
      "Mod+Ctrl+5".action = spawn "niri" "msg" "action" "move-column-to-workspace" "5";
      "Mod+Ctrl+6".action = spawn "niri" "msg" "action" "move-column-to-workspace" "6";
      "Mod+Ctrl+7".action = spawn "niri" "msg" "action" "move-column-to-workspace" "7";
      "Mod+Ctrl+8".action = spawn "niri" "msg" "action" "move-column-to-workspace" "8";
      "Mod+Ctrl+9".action = spawn "niri" "msg" "action" "move-column-to-workspace" "9";

      "Mod+Comma".action = consume-window-into-column;
      "Mod+Period".action = expel-window-from-column;

      "Mod+R".action = switch-preset-column-width;
      "Mod+Shift+R".action = switch-preset-column-width-back;
      "Mod+Ctrl+Shift+R".action = switch-preset-window-height;
      "Mod+Ctrl+R".action = reset-window-height;

      "Mod+F".action = maximize-column;
      "Mod+Shift+F".action = fullscreen-window;
      "Mod+M".action = maximize-window-to-edges;
      "Mod+Ctrl+F".action = expand-column-to-available-width;

      "Mod+C".action = center-column;
      "Mod+Ctrl+C".action = center-visible-columns;

      "Mod+V".action = toggle-window-floating;
      "Mod+Shift+V".action = switch-focus-between-floating-and-tiling;

      "Mod+W".action = toggle-column-tabbed-display;

      "Mod+O" = {
        repeat = false;
        action = toggle-overview;
      };

      "Mod+Escape" = {
        allow-inhibiting = false;
        action = toggle-keyboard-shortcuts-inhibit;
      };

      "Mod+Shift+E".action = quit;
      "Mod+Shift+P".action = power-off-monitors;

      # Volume, backlight, media transport — allow-when-locked so they work
      # at the lock screen, same as niri's shipped default.
      "XF86AudioRaiseVolume" = {
        allow-when-locked = true;
        action =
          spawn "${pkgs.wireplumber}/bin/wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "0.1+" "-l"
            "1.0";
      };
      "XF86AudioLowerVolume" = {
        allow-when-locked = true;
        action = spawn "${pkgs.wireplumber}/bin/wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "0.1-";
      };
      "XF86AudioMute" = {
        allow-when-locked = true;
        action = spawn "${pkgs.wireplumber}/bin/wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle";
      };
      "XF86AudioMicMute" = {
        allow-when-locked = true;
        action = spawn "${pkgs.wireplumber}/bin/wpctl" "set-mute" "@DEFAULT_AUDIO_SOURCE@" "toggle";
      };

      "XF86AudioPlay" = {
        allow-when-locked = true;
        action = spawn "${pkgs.playerctl}/bin/playerctl" "play-pause";
      };
      "XF86AudioStop" = {
        allow-when-locked = true;
        action = spawn "${pkgs.playerctl}/bin/playerctl" "stop";
      };
      "XF86AudioPrev" = {
        allow-when-locked = true;
        action = spawn "${pkgs.playerctl}/bin/playerctl" "previous";
      };
      "XF86AudioNext" = {
        allow-when-locked = true;
        action = spawn "${pkgs.playerctl}/bin/playerctl" "next";
      };

      "XF86MonBrightnessUp" = {
        allow-when-locked = true;
        action = spawn "${pkgs.brightnessctl}/bin/brightnessctl" "--class=backlight" "set" "+10%";
      };
      "XF86MonBrightnessDown" = {
        allow-when-locked = true;
        action = spawn "${pkgs.brightnessctl}/bin/brightnessctl" "--class=backlight" "set" "10%-";
      };
    };
  };
}
