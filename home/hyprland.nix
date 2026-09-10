{
  config,
  inputs,
  pkgs,
  ...
}:
let
  hyprPkgs = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system};

  # Hyprland has no built-in equivalent of niri's show-hotkey-overlay
  # (checked hl.meta.lua — no such dispatcher exists), so this stands in for
  # it. Hand-maintained rather than generated from `hyprctl binds`: the JSON
  # that dispatcher list gives back (modmask ints, dispatcher class names,
  # no per-bind description set below) is not something worth decoding in a
  # shell one-liner for a list this short. Keep it in sync by hand when
  # binds change below — same convention as the sdbackup.nix warning further
  # down this file.
  #
  # Keys are written as symbols (◆ super, ⇧ shift, ⌃ ctrl, ⌥ alt, ⌫
  # backspace, ←↓↑→ arrows) with a legend on the first line, so a chord is
  # one glyph per key and the whole sheet fits without wrapping. Letters are
  # lowercase unless ⇧ is in the chord, so the case shown is the case typed.
  # The column padding assumes those glyphs render single-width; if foot's
  # font draws them wide the descriptions will step right, which is ugly but
  # readable.
  cheatsheet = pkgs.writeText "hyprland-cheatsheet.txt" ''
    Hyprland — Important Hotkeys

    ◆ super   ⇧ shift   ⌃ ctrl   ⌥ alt   ⌫ backspace

    ◆t                    terminal
    ◆q                    close window
    ◆c                    center column
    ◆m                    maximize window
    ◆⇧E                   exit session
    ◆e                    file manager
    ◆v                    toggle floating
    ◆d                    launcher
    ◆⌥⌫                   lock + caffeine

    ◆⌫                    lock (see modules/sdbackup.nix)
    ◆b                    lock + caffeine + SD backup (see modules/sdbackup.nix)

    -- hjkl = focus, arrows = move · h/l = columns, j/k = window stack --
    ◆h / ◆l               focus column left / right
    ◆j / ◆k               focus window down / up in column
    ◆← / ◆→               move column left / right
    ◆↑ / ◆↓               move window up / down in column

    ◆⌥j / ◆⌥k             focus desktop down / up
    ◆⌥↓ / ◆⌥↑             move window to desktop down / up

    ◆⌃h / ◆⌃l             column width -10% / +10%
    ◆⌃k / ◆⌃j             window height +10% / -10%
    ◆⌃← / ◆⌃→             consume-or-expel window prev / next
    ◆⌃↑ / ◆⌃↓             (niri only: focus first / last column)

    ◆⌃⌥ + hjkl            focus monitor left/down/up/right
    ◆⌃⌥ + ←↓↑→            move window to monitor

    ◆\                    promote window into its own column
    ◆, / ◆.               consume / expel window from column
    ◆r / ◆⇧R              cycle column width presets
    ◆f                    maximize column (fit to screen width)
    ◆⌃f                   expand column into free space

    ◆0-9                  switch workspace
    ◆⇧0-9                 move window to workspace
    ◆s                    toggle scratchpad
    ◆⇧S                   move window to scratchpad
    ◆ scroll              cycle workspaces

    ◆ LMB drag            move window
    ◆ RMB drag            resize window

    ◆⇧/                   this cheat sheet
  '';
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
            -- 3-finger drag = click-and-drag (text selection, window drag,
            -- etc.) via libinput's native emulated-button-press feature.
            -- 1 = trigger on 3 fingers specifically; 2 would be 4 fingers
            -- instead — verified the valid range is 0-2 live via
            -- `hyprctl getoption input:touchpad:drag_3fg` (max-value error
            -- above 2). Deliberately disjoint from the 4-finger workspace
            -- swipe gesture below so the two never contend for the same
            -- finger count.
            drag_3fg = 1,
          },
        },
      })

      -- 4-finger horizontal swipe = switch workspace. Hyprland's own
      -- shipped default binds this to 3 fingers instead (see
      -- ${hyprPkgs.hyprland}/share/hypr/hyprland.lua) — bumped to 4 here so
      -- it doesn't collide with the 3-finger drag-to-select above; both
      -- verified live via `hyprctl eval` not to conflict.
      hl.gesture({
        fingers   = 4,
        direction = "horizontal",
        action    = "workspace",
      })

      --------------------------------------------------------------- layout
      -- "scrolling" is Hyprland's native PaperWM/niri-style layout (columns
      -- on an infinitely growing tape, plugin-free since it landed alongside
      -- the Lua config migration — confirmed present in this build via
      -- ${hyprPkgs.hyprland}/share/hypr/stubs/hl.meta.lua's scrolling.*
      -- config keys). Swapped in for dwindle's plain 2D grid so the
      -- focus/move binds below can share niri's column-based mental model
      -- instead of a second, different one. See
      -- https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/ for the
      -- full hl.dsp.layout(msg) message reference the binds below draw on.
      --
      -- direction = "right": new columns open to the right and the tape
      -- scrolls right to reveal them, matching niri's default column order.
      -- fullscreen_on_one_column carried over from Hyprland's own shipped
      -- example (hyprland.lua) for the same reason dwindle's
      -- preserve_split was kept explicit here — it's the default, but
      -- worth stating since behavior depends on it.
      hl.config({
        general = {
          layout = "scrolling",
        },
        scrolling = {
          direction = "right",
          fullscreen_on_one_column = true,
        },
      })

      -- Terminals open at 1/3 width instead of the layout's default column
      -- width: the plain foot terminal (Mod+T) and the foot instance
      -- gui.nix's Helix.desktop spawns with --app-id=helix for editing in a
      -- terminal. `class` matches a Wayland client's app-id here, same as
      -- niri's window-rules. `scrolling_width` is this layout's per-window
      -- override for column width (0-1 = proportion of the tape),
      -- confirmed via src/config/lua/bindings/LuaBindingsInternal.hpp in
      -- the hyprland source — undocumented on the wiki's Lua-config page.
      hl.window_rule({ name = "foot-width", match = { class = "^foot$" }, scrolling_width = 1 / 3 })
      hl.window_rule({ name = "helix-width", match = { class = "^helix$" }, scrolling_width = 1 / 3 })

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
      -- No longer a bind-for-bind mirror of Hyprland's shipped example
      -- hyprland.lua. That mirroring was itself the bug: niri (home/niri.nix)
      -- was left on its own wiki-default binds, so the same key meant two
      -- different things depending which compositor happened to be running
      -- — worst offenders were Mod+Q (spawn terminal here vs. close window
      -- in niri) and Mod+M (exit session here vs. maximize window in niri).
      -- Muscle memory doesn't know which session it's in, so the keys below
      -- are now realigned to match niri's letter for the same action
      -- wherever the layout has a sane equivalent. File manager (Mod+E) and
      -- scratchpad (Mod+S / Mod+Shift+S) are kept as-is — niri has no
      -- launcher-adjacent/scratchpad binds to collide with, so there was
      -- nothing to realign. Mod+P (pseudotile) is gone: that flag is a
      -- dwindle-only concept — there is no "pseudo" state in a column
      -- layout — so the bind was dropped rather than kept as dead weight.
      --
      -- Mod+R/Mod+F used to be listed here as deliberately unbound — dwindle
      -- had no "column" concept for either niri action to map onto. Now that
      -- the layout below is scrolling, both have a real equivalent and are
      -- bound further down alongside the rest of the column-axis binds.
      --
      -- Note there is no default screenshot bind and no default lock bind —
      -- Hyprland's example config doesn't set either (niri's does, via
      -- Mod+Backspace / Mod+P in home/niri.nix). Ask if you want them added.
      local terminal = "${pkgs.foot}/bin/foot"
      local fileManager = "${pkgs.kdePackages.dolphin}/bin/dolphin"
      local menu = "${config.programs.noctalia.package}/bin/noctalia msg panel-toggle launcher"
      -- Shipped default text was "hyprctl dispatch 'hl.dsp.exit()'", which
      -- is not a valid dispatcher — normalized to the real exit dispatcher.
      local exitSession = "command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch exit"

      hl.bind(mod .. " + T", hl.dsp.exec_cmd(terminal))               -- niri: Mod+T
      hl.bind(mod .. " + Q", hl.dsp.window.close())                   -- niri: Mod+Q
      hl.bind(mod .. " + C", hl.dsp.layout("center"))                 -- niri: Mod+C (center-column)
      hl.bind(mod .. " + M", hl.dsp.window.fullscreen(1))             -- niri: Mod+M (maximize-window-to-edges)
      hl.bind(mod .. " + SHIFT + E", hl.dsp.exec_cmd(exitSession))    -- niri: Mod+Shift+E (quit)
      hl.bind(mod .. " + E", hl.dsp.exec_cmd(fileManager))            -- kept
      hl.bind(mod .. " + V", hl.dsp.window.float({ action = "toggle" })) -- already matches niri
      hl.bind(mod .. " + D", hl.dsp.exec_cmd(menu))                   -- niri: Mod+D

      -- Mod+Alt+Backspace: lock + caffeine, mirroring home/niri.nix's own
      -- bind (untouched by modules/sdbackup.nix on either compositor — that
      -- module only owns plain Backspace and Mod+b). caffeine-enable is an
      -- absolute set, not a toggle, so this always ends caffeinated
      -- regardless of prior state — same "lock overrides caffeine" reasoning
      -- as niri's bind and sdbackup.nix's lockThen.
      --
      -- Plain Mod+Backspace (lock only) is deliberately NOT bound here.
      -- modules/sdbackup.nix already binds "SUPER + Backspace" via this
      -- file's extraConfig (a `lines` option, plain string concatenation —
      -- unlike niri's structured binds set, there is no mkForce/override
      -- mechanism for Hyprland's Lua config, so a second hl.bind() on the
      -- same combo here would just race the one sdbackup.nix adds). Add the
      -- lock-only bind there, not here, if sdbackup.nix is ever disabled.
      hl.bind(mod .. " + ALT + Backspace", hl.dsp.exec_cmd(
        "${config.programs.noctalia.package}/bin/noctalia msg session lock && " ..
        "${config.programs.noctalia.package}/bin/noctalia msg caffeine-enable"))

      -- Backslash is the physical key under Backspace on the Preonic.
      -- Promotes the focused window into its own new column — the scrolling
      -- layout has no "split" concept, so togglesplit's old key was free.
      hl.bind(mod .. " + backslash", hl.dsp.layout("promote"))

      -- "slash" verified live via `hyprctl eval 'hl.bind("SUPER + SHIFT +
      -- slash", ...)'` — it's a valid Hyprland key name (xkbcommon keysym),
      -- same as niri's Mod+Shift+Slash for its built-in show-hotkey-overlay.
      hl.bind(mod .. " + SHIFT + slash", hl.dsp.exec_cmd(
        "${pkgs.foot}/bin/foot -e ${pkgs.less}/bin/less ${cheatsheet}"))

      ------------------------------------------------------ scrolling layout
      -- One scheme, shared verbatim with home/niri.nix, built only from keys
      -- that exist on the Preonic's base layer (CLAUDE.md "Keyboard"):
      -- letters, digits, Esc/Shift/Ctrl/Alt/Super/Backspace and the arrows.
      -- Brackets and -/= are NOT on that layer, which is why the old
      -- Mod+bracketleft/bracketright consume-or-expel binds are gone (they
      -- moved to Mod+Ctrl+Left/Right below). Two rules cover the whole grid:
      --
      --   hjkl = focus / primary        arrows = move
      --   h/l  = horizontal (columns)   j/k    = vertical (window stack)
      --
      -- and the modifier picks the scope:
      --
      --   Mod            the current workspace's columns and windows
      --   Mod+Alt        the desktop (workspace) axis
      --   Mod+Ctrl       geometry: resize, plus consume/expel on the arrows
      --   Mod+Ctrl+Alt   monitors
      --
      -- hl.dsp.layout("focus ..") is the layout-aware focus dispatcher: it
      -- recenters the tape on the newly focused column and wraps at the ends
      -- per scrolling.wrap_focus. Deliberately used instead of the generic
      -- hl.dsp.focus(), which only does geometric nearest-neighbour and
      -- would not scroll the tape to reach an off-screen column.
      hl.bind(mod .. " + h", hl.dsp.layout("focus l"))
      hl.bind(mod .. " + l", hl.dsp.layout("focus r"))
      hl.bind(mod .. " + j", hl.dsp.layout("focus d"))
      hl.bind(mod .. " + k", hl.dsp.layout("focus u"))

      -- Arrows are the "move" half of the same axes. Left/Right reposition
      -- the whole column on the tape (swapcol); Up/Down reorder the focused
      -- window inside its column — hl.dsp.window.move() lands in
      -- CScrollingAlgorithm::moveTargetTo, whose UP/DOWN branch calls
      -- column->up()/down(). That is the layout's purpose-built in-column
      -- reorder, not an approximation: there is simply no layoutMsg for it,
      -- so the generic window dispatcher is the correct route.
      hl.bind(mod .. " + left",  hl.dsp.layout("swapcol l"))
      hl.bind(mod .. " + right", hl.dsp.layout("swapcol r"))
      hl.bind(mod .. " + up",    hl.dsp.window.move({ direction = "up" }))
      hl.bind(mod .. " + down",  hl.dsp.window.move({ direction = "down" }))

      ------------------------------------------------------- desktop (Mod+Alt)
      -- j/k focus the next/previous workspace, arrows carry the window with
      -- you. "e+1"/"e-1" walk existing workspaces rather than numbered ones,
      -- so this stays useful alongside the Mod+[0-9] absolute binds below.
      -- Mod+Alt+H/L and Mod+Alt+Left/Right are deliberately unbound: the
      -- desktop axis is vertical only, and monitors live on Mod+Ctrl+Alt.
      hl.bind(mod .. " + ALT + j", hl.dsp.focus({ workspace = "e+1" }))
      hl.bind(mod .. " + ALT + k", hl.dsp.focus({ workspace = "e-1" }))
      hl.bind(mod .. " + ALT + down", hl.dsp.window.move({ workspace = "e+1" }))
      hl.bind(mod .. " + ALT + up",   hl.dsp.window.move({ workspace = "e-1" }))

      ------------------------------------------------ geometry (Mod+Ctrl)
      -- hjkl resizes. Column width goes through the layout's own colresize,
      -- whose argument is a FRACTION OF SCREEN WIDTH — 0.1 is therefore the
      -- exact equivalent of niri's set-column-width "10%".
      --
      -- Window height has no layoutMsg, so it goes through the generic
      -- resize dispatcher, which CScrollingAlgorithm::resizeTarget handles
      -- on the y axis by redistributing height between adjacent windows in
      -- the column. Two consequences worth knowing: it is PIXELS, not a
      -- percentage, so exact parity with niri is not possible (120px ≈ 10%
      -- of this machine's 1920x1200 logical display); and it needs at least
      -- two windows in the column (resizeTarget guards on
      -- targetDatas.size() > 1), so on a lone window it correctly no-ops.
      hl.bind(mod .. " + CTRL + h", hl.dsp.layout("colresize -0.1"))
      hl.bind(mod .. " + CTRL + l", hl.dsp.layout("colresize +0.1"))
      hl.bind(mod .. " + CTRL + k", hl.dsp.window.resize({ x = 0, y = -120, relative = true }))
      hl.bind(mod .. " + CTRL + j", hl.dsp.window.resize({ x = 0, y = 120, relative = true }))

      -- The arrows at this level restructure columns instead of resizing:
      -- consume pulls the adjacent column's window in, expel pushes the
      -- focused one out, and consume_or_expel picks whichever applies for
      -- the given side. This is where the old Mod+bracketleft/bracketright
      -- went. Plain consume/expel keep comma/period further down — both are
      -- base-layer keys, so they stay.
      hl.bind(mod .. " + CTRL + left",  hl.dsp.layout("consume_or_expel prev"))
      hl.bind(mod .. " + CTRL + right", hl.dsp.layout("consume_or_expel next"))

      -- Mod+Ctrl+Up/Down is focus-column-first/last in home/niri.nix and is
      -- deliberately UNBOUND here: the scrolling layout exposes no such
      -- message. Its layoutMsg switch handles only move, colresize, fit,
      -- focus, promote, consume, expel, consume_or_expel, swapcol, center,
      -- inhibit_scroll and fit_into_view — none of which jumps to the first
      -- or last column. Left unbound rather than faked with something that
      -- would mean a different thing in each session.

      ------------------------------------------- monitors (Mod+Ctrl+Alt)
      -- Directional rather than next/previous so the binds are generic: the
      -- monitor selector resolves l/r/u/d against the actual physical
      -- arrangement (CMonitorQueryCore::fromConfigString) and simply no-ops
      -- when nothing sits that way. This machine's displays are currently
      -- stacked VERTICALLY (HDMI-A-1 above, eDP-1 below), so today k/j and
      -- Up/Down are the live pair and h/l are inert — but plugging into a
      -- side-by-side setup makes h/l work with no config change.
      hl.bind(mod .. " + CTRL + ALT + h", hl.dsp.focus({ monitor = "l" }))
      hl.bind(mod .. " + CTRL + ALT + l", hl.dsp.focus({ monitor = "r" }))
      hl.bind(mod .. " + CTRL + ALT + j", hl.dsp.focus({ monitor = "d" }))
      hl.bind(mod .. " + CTRL + ALT + k", hl.dsp.focus({ monitor = "u" }))
      hl.bind(mod .. " + CTRL + ALT + left",  hl.dsp.window.move({ monitor = "l" }))
      hl.bind(mod .. " + CTRL + ALT + right", hl.dsp.window.move({ monitor = "r" }))
      hl.bind(mod .. " + CTRL + ALT + down",  hl.dsp.window.move({ monitor = "d" }))
      hl.bind(mod .. " + CTRL + ALT + up",    hl.dsp.window.move({ monitor = "u" }))

      ------------------------------------------------------------ column ops
      -- Restructure columns: consume pulls the next column's front window
      -- into the current column; expel kicks the current column's last
      -- window out into its own column. Same keys as niri's
      -- consume-window-into-column / expel-window-from-column.
      hl.bind(mod .. " + comma",  hl.dsp.layout("consume"))
      hl.bind(mod .. " + period", hl.dsp.layout("expel"))

      -- Column width presets: R/Shift+R cycle scrolling.explicit_column_widths
      -- forward/back (niri: switch-preset-column-width{,-back}). F fits the
      -- focused column to the full screen width (niri: maximize-column);
      -- Ctrl+F expands it into whatever free space is left without pushing
      -- other columns off-screen (niri: expand-column-to-available-width).
      hl.bind(mod .. " + R", hl.dsp.layout("colresize +conf"))
      hl.bind(mod .. " + SHIFT + R", hl.dsp.layout("colresize -conf"))
      hl.bind(mod .. " + F", hl.dsp.layout("fit active"))
      hl.bind(mod .. " + CTRL + F", hl.dsp.layout("fit expand"))

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
