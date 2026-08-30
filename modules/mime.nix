{ lib, ... }:
# Default applications, declared once at the system level.
#
# There are two levels on purpose, and the split is what makes runtime
# clobbering impossible:
#
#   1. /etc/xdg/mimeapps.list (this file) holds every actual default. It is
#      in XDG_CONFIG_DIRS — second entry, right after ~/.config/kdedefaults,
#      confirmed in /etc/set-environment — so per the mime-apps spec it is
#      consulted for any mimetype the user-level file does not claim.
#   2. ~/.config/mimeapps.list is handed to home-manager (xdg.mimeApps.enable
#      in home/gui.nix), which writes it as a read-only store symlink. It is
#      deliberately empty: it exists as a lid, not as content. An empty
#      [Default Applications] claims nothing, so every lookup falls through
#      to this file, and no application can write the user file to grab a
#      mimetype for itself.
#
# That second point is the reason for the arrangement. Vivaldi and Brave both
# rewrite ~/.config/mimeapps.list on "make me your default browser" — which is
# exactly how the pre-migration file ended up with Bluefin flatpak IDs
# (com.vivaldi.Vivaldi.desktop, GSConnect) still claiming http/https on a
# machine where those .desktop files no longer exist. Nothing opened anything.
#
# The cost is real and worth stating: "Set as default" in a browser's
# preferences, Dolphin's "Open With -> always use this", and `xdg-mime default`
# now all fail or silently no-op. Changing a default means editing this file.
# Per-user overrides, if one is ever wanted, go in home/gui.nix's
# xdg.mimeApps.defaultApplications, which outranks everything here.
#
# ***
#
# Grouped by handler rather than by mimetype because that is the direction the
# question actually gets asked in ("what does mpv own?"). The inversion below
# emits each pair into BOTH sections:
#
#   [Default Applications] is the answer to "what opens this".
#   [Added Associations] is what makes that answer legal. Several entries here
#   do not declare the mimetype in their own .desktop file and would otherwise
#   be ignored — org.kde.okular.desktop declares only
#   application/vnd.kde.okular-archive (PDF lives in the separate
#   okularApplication_pdf.desktop, which is why that name is used below), and
#   the home-manager LibreOffice entry declares no MimeType at all.
let
  handlers = {
    # Brave is the system browser; home/webapps.nix depends on this
    # specifically — an off-site link inside an Epiphany web app is handed to
    # ephy_file_open_uri_in_default_browser(), i.e. to whatever answers here.
    # Use brave-browser.desktop, not com.brave.Browser.desktop: nixpkgs ships
    # both, and the latter is a NoDisplay=true flatpak-name alias.
    "brave-browser.desktop" = [
      "x-scheme-handler/http"
      "x-scheme-handler/https"
      "x-scheme-handler/about"
      "x-scheme-handler/unknown"
      "text/html"
      "application/xhtml+xml"
    ];

    # The video list is the one that used to sit dead in home/gui.nix; audio is
    # new, and safe, because mpv is the only media player installed at all.
    "mpv.desktop" = [
      "video/mp4"
      "video/x-matroska"
      "video/webm"
      "video/quicktime"
      "video/x-msvideo"
      "video/mpeg"
      "video/ogg"
      "video/x-flv"
      "video/x-ms-wmv"
      "video/3gpp"
      "audio/mpeg"
      "audio/flac"
      "audio/ogg"
      "audio/x-vorbis+ogg"
      "audio/opus"
      "audio/mp4"
      "audio/x-m4a"
      "audio/aac"
      "audio/x-wav"
    ];

    "imv.desktop" = [
      "image/png"
      "image/jpeg"
      "image/gif"
      "image/webp"
      "image/bmp"
      "image/tiff"
      "image/avif"
      "image/heif"
      "image/jxl"
      "image/svg+xml"
    ];

    # Not org.kde.okular.desktop — see the note above about which Okular entry
    # actually declares application/pdf.
    "okularApplication_pdf.desktop" = [
      "application/pdf"
      "application/x-gzpdf"
      "application/x-bzpdf"
    ];
    "okularApplication_epub.desktop" = [ "application/epub+zip" ];

    # home/gui.nix writes this entry by hand because LibreOffice in script mode
    # ships no share/applications at all. It carries no MimeType, so without
    # the [Added Associations] half of this file every office document on the
    # machine opens in nothing.
    "libreoffice.desktop" = [
      "application/vnd.oasis.opendocument.text"
      "application/vnd.oasis.opendocument.spreadsheet"
      "application/vnd.oasis.opendocument.presentation"
      "application/msword"
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
      "application/vnd.ms-excel"
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
      "application/vnd.ms-powerpoint"
      "application/vnd.openxmlformats-officedocument.presentationml.presentation"
      "text/csv"
    ];

    "org.kde.dolphin.desktop" = [ "inode/directory" ];

    # Not the Helix.desktop that ships with the package — home/gui.nix shadows
    # that ID with one that launches foot explicitly, because Terminal=true is
    # not reliably honoured under niri or Hyprland. Read the comment there
    # before touching this list; like LibreOffice above, the shadowing entry
    # carries no MimeType of its own, so [Added Associations] is what makes
    # these bind at all.
    #
    # Every mimetype below was read off `xdg-mime query filetype` on this
    # machine rather than assumed, which turned up two worth knowing:
    #   - .nix files are plain text/plain; shared-mime-info has no Nix type, so
    #     text/plain is doing that work and cannot be narrowed.
    #   - .ts is text/vnd.trolltech.linguist, i.e. Qt Linguist, not TypeScript.
    #     Included deliberately — on this machine a .ts file is TypeScript.
    "Helix.desktop" = [
      "text/plain"
      "text/markdown"
      "text/english"
      "text/x-log"
      "text/x-python"
      "text/rust"
      "text/javascript"
      "text/vnd.trolltech.linguist"
      "application/json"
      "application/yaml"
      "application/toml"
      "application/x-shellscript"
      "application/x-fishscript"
      "text/x-c"
      "text/x-c++"
      "text/x-csrc"
      "text/x-chdr"
      "text/x-c++src"
      "text/x-c++hdr"
      "text/x-java"
      "text/x-makefile"
      "text/x-tex"
    ];

    # Deep links. zoom.desktop is generated by home/webapps.nix and points at
    # the Brave-hosted web client; claiming the schemes here is what makes a
    # "Launch Meeting" button on a Zoom page reach it instead of dead-ending on
    # a native client that is not installed.
    "zoom.desktop" = [
      "x-scheme-handler/zoommtg"
      "x-scheme-handler/zoomus"
    ];
    "bitwarden.desktop" = [ "x-scheme-handler/bitwarden" ];

    # Both of these .desktop files live unmanaged in
    # ~/.local/share/applications, written by the tools themselves. Claiming
    # the scheme from here still works — the lookup resolves a desktop id
    # across all of XDG_DATA_DIRS, and the per-user directory is in it.
    "claude-code-url-handler.desktop" = [ "x-scheme-handler/claude-cli" ];
    "jetbrainsd.desktop" = [ "x-scheme-handler/jetbrains" ];
  };

  # handler -> [mimetype] inverted to mimetype -> handler.
  byMime = lib.foldl' (acc: desktop: acc // lib.genAttrs handlers.${desktop} (_: desktop)) { } (
    lib.attrNames handlers
  );
in
{
  # mkKeyValue without spaces around `=`: GKeyFile strips them, but every other
  # mimeapps.list on the system is written `key=value` and matching that keeps
  # the file diffable against what tools produce.
  environment.etc."xdg/mimeapps.list".text =
    lib.generators.toINI { mkKeyValue = k: v: "${k}=${v}"; }
      {
        "Added Associations" = byMime;
        "Default Applications" = byMime;
      };
}
