{ inputs, ... }: {
  # Everything noctalia, in one file: the system services its bar and panels
  # read from, and the home-manager declaration of the shell itself. It used
  # to be split across here and home/noctalia.nix, which meant the answer to
  # "how is the shell configured" lived in two places and the wallpaper
  # settings lived in neither. Same reasoning as modules/sdbackup.nix's header
  # comment: one feature, one file to read and one file to delete.
  #
  # What is deliberately NOT here: the places that merely *call* noctalia —
  # the spawn-at-startup and binds in home/{niri,hyprland}.nix, the idle lock
  # in home/default.nix, the SD-card binds in modules/sdbackup.nix. Those are
  # compositor/idle/backup config that happens to invoke this shell; pulling
  # them in would drag three unrelated features along with them.

  ### system side ###########################################################
  #
  # Upstream exposes `recommendedServices.enable` on its own NixOS module,
  # which turns on exactly these four. They are spelled out here instead so
  # that nothing about the system config depends on a flake module's defaults
  # changing under us — and so the reason each one exists is visible.

  hardware.bluetooth.enable = true; # bluetooth applet
  services.upower.enable = true; # battery indicator
  services.power-profiles-daemon.enable = true; # power profile switcher
  # networking.networkmanager.enable is already set in hosts/laptop/default.nix

  # `services.tuned.enable` is the alternative to power-profiles-daemon.
  # They conflict — enable exactly one.

  # noctalia.cachix.org lives in modules/caches.nix — see the note there about
  # why the builder needs it separately from the built system.

  ### the shell itself ######################################################
  #
  # Shared by both the niri and Hyprland sessions — noctalia has native
  # support for each, so the bar, launcher, notifications, lockscreen and
  # wallpaper are identical whichever one you log into. That is most of what
  # makes running both cheap. It is NOT started under Plasma (see
  # modules/plasma.nix); nothing here changes that.
  home-manager.users.stablefly = {
    imports = [ inputs.noctalia.homeModules.default ];

    programs.noctalia = {
      enable = true;

      # `settings` is written to ~/.config/noctalia/config.toml, which noctalia
      # reads FIRST and then lets ~/.local/state/noctalia/settings.toml (what
      # the in-app Settings UI writes) override key by key. So anything set
      # here is a default the UI can still walk over — it is not a lock. Keep
      # this list short and limited to things that must be right on a fresh
      # home, and check `noctalia config export merged` when a value appears
      # not to take: a stale UI-written key in the state file wins silently.
      #
      # `checkConfig` runs `noctalia config validate` at build time, but it is
      # NOT a safety net for typos: an unknown key or section only produces a
      # WARN and validate still exits 0, so the build passes and the key is
      # silently ignored at runtime. `noctalia config export merged` echoes
      # unknown keys back too. Neither tool can tell a real setting from a
      # misspelt one — check a new key against `config export full`, which
      # lists only settings noctalia actually has.
      settings = {
        # Blurred, tinted layer between the wallpaper and the windows.
        # blur_intensity (0.5) and tint_intensity (0.3) are left at their
        # defaults; the tint colour is not configurable at all — noctalia
        # always uses palette.surface, so it follows the active theme.
        backdrop.enabled = true;

        # Bar layout, left section only: workspaces and nothing else. The
        # launcher (magnifying glass) and wallpaper-picker buttons are
        # noctalia defaults; both open panels that are reachable from
        # elsewhere, so they were shelf space rather than controls.
        #
        # This is the first time the bar's contents are declared here at all.
        # The cost is that `start` no longer tracks upstream — a widget added
        # to noctalia's default left section in a later release will not
        # appear. `center` and `end` are deliberately left undeclared and do
        # still track: at the time of writing they are ["clock"] and the
        # eleven-widget tray/status run.
        bar.default.start = [ "workspaces" ];

        # Make the workspace pills show workspace *names*, not indices —
        # without this a named workspace still renders as its number and the
        # name is invisible. Widget settings live in their own
        # `[widget.<name>]` table, NOT inline in the bar's widget list: an
        # entry written as a table inside `bar.default.start` is dropped
        # silently, taking the whole widget off the bar (measured
        # 2026-09-23).
        #
        # max_label_chars defaults low enough to render one letter, which
        # looks like the feature not working rather than a width limit. 8 is
        # enough for the names actually in use; the pill grows to fit.
        widget.workspaces = {
          label_source = "name";
          max_label_chars = 8;
        };

        # All three wallpaper directories, explicitly. Empty means "use the
        # XDG Pictures directory", which is ~/Pictures — the camera-roll
        # import, full of personal photos that must never end up on a
        # lockscreen or an external monitor. Only the light/dark pair had been
        # pointed at the curated pool; `directory` was left empty and so
        # resolved to the whole of ~/Pictures.
        #
        # ~/Pictures/Wallpapers is filled by home/wallhaven.nix (the wallhaven
        # toplist pool). noctalia expands the leading `~` itself, and this is
        # the exact spelling its Settings UI writes, so the declared value and
        # a UI-set one are byte-identical rather than one being an absolute
        # path that silently shadows the other.
        wallpaper = {
          directory = "~/Pictures/Wallpapers";
          directory_dark = "~/Pictures/Wallpapers";
          directory_light = "~/Pictures/Wallpapers";

          # Rotate through the pool. Only `enabled` was actually set in the UI;
          # interval_seconds = 1800, order = "random" and recursive = true are
          # noctalia's defaults and are deliberately left undeclared rather
          # than restated here, so they track upstream.
          #
          # Nothing else from the state file's [wallpaper] tree belongs in nix:
          # default/last/monitors.<output> hold the currently-displayed image
          # path and are rewritten on every rotation.
          automation.enabled = true;
        };

        # Where the weather widget and the sunrise/sunset schedule think they
        # are. `auto_locate` is the alternative and is left OFF on purpose: it
        # resolves position by sending the machine's IP to noctalia.dev on every
        # lookup. A fixed address is one fewer thing phoning out, and it does
        # not wander when the laptop is on a VPN or tethered.
        #
        # "City, Country" is the shape noctalia's own field documents. The
        # timezone this pairs with is set separately and is NOT read from here —
        # see time.timeZone in hosts/laptop/default.nix.
        location = {
          address = "Montreal, Canada";
          auto_locate = false;
        };

        # Canton Becker's astronomy calendar (moon phases, eclipses, transits).
        #
        # Shape lifted verbatim from what the Settings UI wrote, not guessed:
        # the account is a table under `account.<slot>`, and the URL key is
        # `server_url`. `[[calendar.account]]` and `url` both looked plausible
        # and both validate clean — see the checkConfig note above for why that
        # proves nothing.
        #
        # https, not the webcal:// the site advertises: webcal is a pseudo-
        # scheme clients rewrite before fetching. The published path 302s to
        # /astronomy-calendar-files/astrocal.ics; kept as-is because that is
        # the stable public URL and noctalia follows the redirect.
        calendar = {
          enabled = true;
          account.subscription = {
            name = "AstroCal";
            server_url = "https://cantonbecker.com/astronomy-calendar/astrocal.ics";
            type = "ics";
          };
        };
      };
    };
  };
}
