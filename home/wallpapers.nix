{ config, pkgs, ... }:
let
  # None of the three is in nixpkgs (they're one-off scripts, not projects) —
  # see pkgs/{wallhaven,reddit}-wallpapers.nix and pkgs/wallpaper-blackout.nix.
  wallhaven-wallpapers = pkgs.callPackage ../pkgs/wallhaven-wallpapers.nix { };
  reddit-wallpapers = pkgs.callPackage ../pkgs/reddit-wallpapers.nix { };

  # noctalia isn't a nixpkgs attribute — it comes from the flake input's home
  # module — so the binary is passed in explicitly, the same way
  # modules/sdbackup.nix reaches for it.
  wallpaper-blackout = pkgs.callPackage ../pkgs/wallpaper-blackout.nix {
    noctalia = config.programs.noctalia.package;
  };

  # Both sources fill the same directory and want the same failure handling,
  # so the unit shape is written once. What differs is only the name, the
  # description and the binary.
  #
  # Restart=on-failure is load-bearing for both, for different reasons: it
  # stands in for network-online.target (a system-manager unit, not reliably
  # visible to the user session that would need to gate on it), and it is also
  # what absorbs reddit's 429s, which it hands out readily even to a polite
  # User-Agent. Five tries over five minutes covers a laptop that logged in
  # before the wifi associated.
  refreshService = description: program: {
    Unit = {
      Description = description;
      StartLimitIntervalSec = 300;
      StartLimitBurst = 5;
    };
    Service = {
      Type = "oneshot";
      ExecStart = program;
      Restart = "on-failure";
      RestartSec = 30;
      # Optional: `-` means "skip silently if absent", so both units work
      # unchanged before this file exists. It carries the two settings that
      # must not be in the repo, for two different reasons:
      #
      #   WALLHAVEN_API_KEY  a credential. /nix/store is world-readable, so
      #                      inlining it would publish it to every user and
      #                      every build on the machine.
      #   REDDIT_SUBREDDIT   which subreddit to pull. Not secret, but this
      #                      repo is public and what a machine fetches
      #                      wallpapers from need not be.
      #
      #   mkdir -p ~/.config/wallpaper-pool
      #   printf 'WALLHAVEN_API_KEY=...\nREDDIT_SUBREDDIT=...\n' \
      #     > ~/.config/wallpaper-pool/env
      #   chmod 0600 ~/.config/wallpaper-pool/env
      #
      # Each is handled independently: without the key wallhaven serves only
      # its first two purity bits (see that package's `purity` argument for
      # why that fails silently rather than erroring); without the subreddit
      # the reddit unit logs and exits 0 rather than failing.
      EnvironmentFile = "-%h/.config/wallpaper-pool/env";
    };
    Install.WantedBy = [ "default.target" ];
  };

  # Midnight, and only if the machine is up: no Persistent=true, so a laptop
  # that was asleep or off at 00:00 does not fire a catch-up run the moment it
  # comes back — the login-time run from Install.WantedBy already covers that
  # case, and firing both would just mean two refreshes in a minute.
  #
  # The jitter is per-unit and keeps the two sources off the same instant.
  refreshTimer = description: {
    Unit.Description = description;
    Timer = {
      OnCalendar = "*-*-* 00:00:00";
      RandomizedDelaySec = "5m";
    };
    Install.WantedBy = [ "timers.target" ];
  };
in
{
  # noctalia ships a Wallhaven panel, but it's an interactive search-and-pick
  # UI, not a curation feature — there's nothing there to drive declaratively.
  # Cheaper to just refresh a capped pool of top wallpapers on disk and let
  # noctalia's existing directory-based random rotation pick from it like any
  # other local wallpaper. That the pool then also accepts a second source
  # (reddit) for free is the payoff of having gone that way.
  #
  # The three directory settings that point noctalia at this pool are declared
  # in modules/noctalia.nix — NOT set by hand in the Settings UI, which is how
  # `directory` ended up empty (and therefore meaning all of ~/Pictures, camera
  # roll included) while only the light/dark pair were right.
  #
  # This stays on the home side rather than moving in with them: these are
  # plain user units running downloaders, with nothing noctalia-specific in
  # them, and keeping them here means the pool still refreshes under the
  # standalone home profile, which does not get modules/.
  systemd.user.services = {
    wallhaven-wallpapers = refreshService "Refresh the wallhaven toplist wallpaper pool" (
      pkgs.lib.getExe wallhaven-wallpapers
    );
    reddit-wallpapers = refreshService "Refresh the reddit wallpaper pool" (
      pkgs.lib.getExe reddit-wallpapers
    );
  };

  systemd.user.timers = {
    wallhaven-wallpapers = refreshTimer "Nightly wallhaven wallpaper pool refresh";
    reddit-wallpapers = refreshTimer "Nightly reddit wallpaper pool refresh";
  };

  # ***

  # Mod+Alt+B: black background, rotation off — and the same key back again.
  #
  # Alt+b rather than plain b because plain Mod+B is the SD-card backup run
  # (modules/sdbackup.nix) and stays that way.
  #
  # The binds live here rather than in home/{niri,hyprland}.nix for the reason
  # modules/sdbackup.nix's header gives about its own: this is one small
  # feature, and the script, the reason it exists and the keys that reach it
  # should be one file to read and one file to delete. Both compositor files
  # are signposted at their lock binds so nobody hunts for a missing bind.
  #
  # Not bound under Plasma. noctalia isn't started there (see
  # modules/plasma.nix), so there is no wallpaper daemon to talk to and
  # nothing this script could do — unlike sdbackup, which has a real Plasma
  # equivalent via loginctl and therefore does bind all three.
  programs.niri.settings.binds =
    let
      inherit (config.lib.niri.actions) spawn;
    in
    {
      # Lowercase `b`, as in modules/sdbackup.nix: niri treats Mod+B and Mod+b
      # as the same bind, and the capital would imply a Shift that is not
      # actually pressed. Mod+Alt+b is a genuinely distinct bind from Mod+b,
      # so the two coexist without a duplicate-keybind error.
      "Mod+Alt+b".action = spawn "${pkgs.lib.getExe wallpaper-blackout}";
    };

  # `extraConfig` is a `lines` option with no override mechanism, so this must
  # not collide with home/hyprland.nix or modules/sdbackup.nix — both of which
  # append to this same option. "SUPER + ALT + b" is free in both: sdbackup
  # owns plain "SUPER + b", and hyprland.nix owns "SUPER + ALT + Backspace".
  wayland.windowManager.hyprland.extraConfig = ''

    -------------------------------------------------------- wallpaper blackout
    -- Black, static background ⇄ the rotating pool — see home/wallpapers.nix.
    hl.bind("SUPER + ALT + b", hl.dsp.exec_cmd(${builtins.toJSON "${pkgs.lib.getExe wallpaper-blackout}"}))
  '';
}
