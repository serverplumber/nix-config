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
      # `checkConfig` defaults to true, so a typo'd key fails the build via
      # `noctalia config validate` rather than being ignored at runtime.
      settings = {
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
      };
    };
  };
}
