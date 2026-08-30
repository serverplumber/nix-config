# Standalone web apps: one window per site, no browser furniture at all, and a
# link that leaves the site gets handed to the real browser instead of being
# followed in place.
#
# This is deliberately NOT the Omarchy trick (`chromium --app=URL`). That does
# give a chromeless window, but its scope rule only kicks an off-site link out
# to *another window of the same browser and the same profile* — so the site
# still rides in the same cookie jar as everything else, which is the thing we
# wanted to avoid. Epiphany's application mode is the one that actually
# matches: a private profile directory per app (its own cookies, history and
# storage, sharing nothing with Brave), and an off-site link goes through
# ephy_file_open_uri_in_default_browser(), i.e. out to the system default
# browser.
#
# Epiphany is referenced by absolute store path and is deliberately NOT in
# home.packages — we want the web apps, not a fourth browser in the launcher.
#
# ***
#
# Mechanics, read out of the epiphany 50.4 source and confirmed against a live
# run, because almost every part of this is load-bearing in a non-obvious way:
#
#   - `epiphany --application-mode=<basename>.desktop <url>` looks that
#     basename up through GIO, reads its Name, and derives EVERYTHING from
#     SHA-1(Name): the GApplication id, the Wayland app_id, and the profile
#     directory ~/.local/share/org.gnome.Epiphany.WebApp_<sha1>. `name` below
#     is therefore not cosmetic — renaming an app strands its old profile, and
#     its logins, in the old directory under the old hash.
#   - Epiphany creates that profile directory itself on first launch, including
#     the `.app` marker file that is what actually puts it in application mode.
#     It is pure mutable state and is deliberately not managed from here.
#   - The desktop file goes to TWO places and both are required:
#       applications/                     the GIO lookup above, and the launcher
#       xdg-desktop-portal/applications/  epiphany asks the DynamicLauncher
#         portal for the entry in order to learn the app's URL. Without this
#         copy ephy_web_application_for_profile_directory() returns NULL and
#         the g_assert() in ephy_web_application_is_uri_allowed() aborts the
#         process the first time you click a link.
#   - The URL must be the LAST word of Exec=, because epiphany reads it as
#     argv[argc - 1], and Exec's first word must be an absolute path: GIO
#     rejects a desktop file whose Exec binary it cannot resolve, and epiphany
#     then exits with "Invalid desktop file passed to --application-mode".
#
# "Leaving the site" is judged by base domain (eTLD+1), not exact origin, so
# mail.proton.me and account.proton.me count as the same app and stay inside.
# A login flow that redirects through a *foreign* domain (Okta, auth0,
# Microsoft) will be thrown out to Brave instead, and the web app will never
# see the resulting cookie — `extraDomains` is the escape hatch for that.
#
# Zoom is the one deliberate exception to all of the above and uses Brave
# instead; its own section is at the bottom of this file.
{
  lib,
  pkgs,
  ...
}:
let
  webApps = [
    {
      name = "Proton Mail";
      url = "https://mail.proton.me/";
      icon = pkgs.fetchurl {
        # Pinned to a commit, not to `main`, so the hash cannot break under us.
        url = "https://raw.githubusercontent.com/homarr-labs/dashboard-icons/51cb393299f8c404e3792e01244746d253a1e480/png/proton-mail.png";
        sha256 = "12sy9l0bx4hxkgccpz88nprnnfc6mgkdmaq2x60p2lfqi32srwr4";
      };
    }
  ];

  appId = name: "org.gnome.Epiphany.WebApp_${builtins.hashString "sha1" name}";

  desktopFile =
    {
      name,
      url,
      icon,
      ...
    }:
    let
      id = appId name;
      item = pkgs.makeDesktopItem {
        name = id; # the basename must equal the GApplication id
        desktopName = name; # the SHA-1 input; see the header
        exec = "${pkgs.epiphany}/bin/epiphany --application-mode=${id}.desktop ${url}";
        icon = "${icon}";
        categories = [ "Network" ];
        startupWMClass = id; # so niri/hyprland rules can address one web app
      };
    in
    "${item}/share/applications/${id}.desktop";

  # Both copies point at the same store path, so they cannot drift.
  dataFiles =
    app:
    let
      target = "${appId app.name}.desktop";
      source = desktopFile app;
    in
    [
      (lib.nameValuePair "applications/${target}" { inherit source; })
      (lib.nameValuePair "xdg-desktop-portal/applications/${target}" { inherit source; })
    ];

  # Relocatable schema: org.gnome.Epiphany.webapp, rooted per web app under
  # /org/gnome/epiphany/web-apps/<app id>/webapp/.
  extraDomainSetting = app: {
    name = "org/gnome/epiphany/web-apps/${appId app.name}/webapp";
    value.additional-urls = app.extraDomains;
  };

  # ***
  #
  # Zoom, and why it is the exception.
  #
  # It does NOT go through Epiphany. The Zoom web client is built against
  # Chromium's and Firefox's WebRTC; on WebKitGTK screen sharing in particular
  # is not a bet worth taking, and a call that fails at the wrong moment is a
  # great deal worse than a browser tab that renders badly.
  #
  # So Zoom gets the other half of the isolation story instead — the throwaway
  # Brave *profile* already planned in package-migration.md's Tier 2 notes.
  # Separate profile rather than a private window on purpose: Chromium does not
  # persist camera/mic grants in incognito, so a private window would mean
  # re-authorising the devices at the start of every single meeting. The
  # profile is also the place conferencing permissions can accumulate, which is
  # what those notes wanted it for.
  #
  # This retires the item those notes call the hardest in the whole sandbox
  # list: with no native Zoom client installed there is nothing to box, and
  # camera/mic/screenshare take the ordinary portal path already wired up in
  # modules/desktop.nix and modules/audio.nix.
  #
  # zoom-web accepts a meeting link in any of the shapes Zoom hands out and
  # rewrites it to the web client on the SAME regional host — a meeting on
  # us02web.zoom.us does not exist on the generic one:
  #
  #   zoommtg://host/join?confno=<id>&pwd=<pw>   what a Zoom page fires at the
  #                                              native client to launch it
  #   https://host/j/<id>                        the link in the invitation
  #
  # and with no argument at all it opens the web client's home.
  zoomWeb = pkgs.writeShellApplication {
    name = "zoom-web";
    text = ''
      url="''${1-}"

      case "$url" in
        zoommtg://* | zoomus://*)
          host=$(printf '%s' "$url" | sed -n 's|^[a-z]*://\([^/]*\)/.*|\1|p')
          confno=$(printf '%s' "$url" | sed -n 's|.*[?&]confno=\([^&]*\).*|\1|p')
          passcode=$(printf '%s' "$url" | sed -n 's|.*[?&]pwd=\([^&]*\).*|\1|p')
          if [ -z "$host" ]; then
            host="zoom.us"
          fi
          if [ -n "$confno" ]; then
            target="https://$host/wc/join/$confno"
            if [ -n "$passcode" ]; then
              target="$target?pwd=$passcode"
            fi
          else
            target="https://app.zoom.us/wc/home"
          fi
          ;;
        *zoom.us/j/* | *zoom.us/w/*)
          target=$(printf '%s' "$url" | sed -e 's|/j/|/wc/join/|' -e 's|/w/|/wc/join/|')
          ;;
        "")
          target="https://app.zoom.us/wc/home"
          ;;
        *)
          target="$url"
          ;;
      esac

      exec ${pkgs.brave}/bin/brave \
        --profile-directory=Conferencing \
        --no-first-run \
        --no-default-browser-check \
        --app="$target"
    '';
  };

  zoomIcon = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/homarr-labs/dashboard-icons/51cb393299f8c404e3792e01244746d253a1e480/png/zoom.png";
    sha256 = "1p9smf31my32b75b6qakg5nd57h27k3bazvdlz4drv1zmwagq15d";
  };
in
{
  xdg.dataFile = builtins.listToAttrs (lib.concatMap dataFiles webApps);

  dconf.settings = builtins.listToAttrs (
    map extraDomainSetting (lib.filter (app: (app.extraDomains or [ ]) != [ ]) webApps)
  );

  # On PATH as well as in the launcher, because the common case is having a
  # meeting link already in hand: `zoom-web <paste>` joins it directly.
  home.packages = [ zoomWeb ];

  xdg.desktopEntries.zoom = {
    name = "Zoom";
    genericName = "Video Conferencing";
    exec = "${zoomWeb}/bin/zoom-web %u";
    icon = "${zoomIcon}";
    terminal = false;
    categories = [
      "Network"
      "AudioVideo"
    ];
    # So a "Launch Meeting" button on a Zoom page reaches the web client rather
    # than dead-ending on a native client that isn't installed.
    #
    # This claim is inert as things stand: xdg.mimeApps.enable is false, so
    # home-manager writes no mimeapps.list and ~/.config/mimeapps.list is still
    # the unmanaged Bluefin-era file. That is a pre-existing gap, not one this
    # module introduces — the mpv video associations in home/gui.nix are dead
    # for the same reason. Turning it on means taking that file over, so it is
    # left as its own decision. The launcher and `zoom-web <url>` work either
    # way.
    mimeType = [
      "x-scheme-handler/zoommtg"
      "x-scheme-handler/zoomus"
    ];
  };

  # Window rules: do NOT try to pin this with --class. Brave ignores it on
  # Wayland — verified live, the app_id came back as
  # brave-example.com__-Conferencing no matter what --class was set to. The
  # app_id is derived from the launch URL and the profile name, so it changes
  # per meeting; niri/hyprland rules have to match a pattern such as
  # ^brave-.*zoom\.us__wc_.*-Conferencing$ rather than a literal string.
}
