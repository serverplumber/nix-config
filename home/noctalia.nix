{ inputs, ... }: {
  imports = [ inputs.noctalia.homeModules.default ];

  # Shared by both the niri and Hyprland sessions — noctalia has native
  # support for each, so the bar, launcher, notifications, lockscreen and
  # wallpaper are identical whichever one you log into. That is most of what
  # makes running both cheap.
  programs.noctalia = {
    enable = true;

    # Left deliberately empty. noctalia ships a working default config and
    # has an in-app settings UI; anything set here overrides that and stops
    # the UI round-tripping. Move settings in once they have stabilised —
    # same hazard as the old hand-written rc.xml, see O-5.
    settings = { };
  };
}
