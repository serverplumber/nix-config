{ pkgs, ... }:
let
  # Not in nixpkgs (it's a one-off script, not a project) — see
  # pkgs/wallhaven-wallpapers.nix.
  wallhaven-wallpapers = pkgs.callPackage ../pkgs/wallhaven-wallpapers.nix { };
in
{
  # noctalia ships a Wallhaven panel, but it's an interactive search-and-pick
  # UI, not a curation feature — there's nothing there to drive declaratively.
  # Cheaper to just refresh a capped pool of top wallpapers on disk and let
  # noctalia's existing directory-based random rotation pick from it like any
  # other local wallpaper.
  #
  # The three directory settings that point noctalia at this pool are declared
  # in modules/noctalia.nix — NOT set by hand in the Settings UI, which is how
  # `directory` ended up empty (and therefore meaning all of ~/Pictures, camera
  # roll included) while only the light/dark pair were right.
  #
  # This stays on the home side rather than moving in with them: it is a plain
  # user unit running a downloader, with nothing noctalia-specific in it, and
  # keeping it here means the pool still refreshes under the standalone home
  # profile, which does not get modules/.
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
