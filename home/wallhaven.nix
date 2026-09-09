{ pkgs, ... }:
let
  # Not in nixpkgs (it's a one-off script, not a project) — see
  # pkgs/wallhaven-wallpapers.nix.
  wallhaven-wallpapers = pkgs.callPackage ../pkgs/wallhaven-wallpapers.nix { };
in
{
  # noctalia ships a Wallhaven panel (home/noctalia.nix), but it's an
  # interactive search-and-pick UI, not a curation feature — there's nothing
  # there to drive declaratively. Cheaper to just refresh a capped pool of
  # top wallpapers on disk and let noctalia's existing directory-based random
  # rotation pick from it like any other local wallpaper.
  #
  # Point noctalia's wallpaper directory (Settings panel, or
  # ~/.local/state/noctalia/settings.toml) at ~/Pictures/Wallpapers to use
  # this pool — that setting lives in noctalia's own mutable state, not
  # something this flake can own (see home/noctalia.nix's `settings = {}`).
  systemd.user.services.wallhaven-wallpapers = {
    Unit = {
      Description = "Refresh the wallhaven toplist wallpaper pool";
      # Retry a few times rather than depending on network-online.target —
      # that's a system-manager unit and isn't reliably visible to the user
      # session it would need to gate.
      StartLimitIntervalSec = 300;
      StartLimitBurst = 5;
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${wallhaven-wallpapers}/bin/wallhaven-wallpapers";
      Restart = "on-failure";
      RestartSec = 30;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
