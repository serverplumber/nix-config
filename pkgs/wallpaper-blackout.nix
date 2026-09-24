{
  lib,
  writeShellApplication,
  runCommand,
  imagemagick,
  gnused,
  coreutils,
  noctalia,
}:

let
  # A real file rather than a compositor "no wallpaper" mode, because noctalia
  # owns the background on both sessions and has no IPC for "draw nothing" —
  # only `wallpaper-set <path>`. 4K so it is never upscaled on either output;
  # a solid colour compresses to about a kilobyte regardless.
  black = runCommand "black-wallpaper.png" { nativeBuildInputs = [ imagemagick ]; } ''
    magick -size 3840x2160 xc:black "$out"
  '';

  # The Settings UI writes ~/.local/state/noctalia/settings.toml, which
  # overrides the nix-written config.toml key by key — so this is the file
  # that has to change, and config.toml (a read-only store symlink) cannot be
  # touched anyway.
  stateFile = "$HOME/.local/state/noctalia/settings.toml";
in

# Toggle: black, non-rotating background ⇄ the normal rotating wallpaper pool.
# Bound to Mod+Alt+B in home/wallpapers.nix.
#
# Rotation is the awkward half. noctalia exposes wallpaper-set/-next/-random
# over IPC but nothing for `wallpaper.automation.enabled`, so the only way to
# stop the 30-minute rotation is to write the setting and ask noctalia to
# re-read it. `msg config-reload` does pick it up, and — verified — noctalia
# does not write its in-memory copy back over the edit afterwards.
#
# Editing TOML with sed is normally the wrong answer, so note what makes it
# safe here: the file is machine-written by noctalia itself (regular shape, no
# hand formatting to preserve), the edit is one boolean in one named section,
# and the script refuses to continue if either the key is missing or the value
# did not actually change. A noctalia format change surfaces as a loud failure
# rather than a key that silently stops toggling.
writeShellApplication {
  name = "wallpaper-blackout";

  runtimeInputs = [
    gnused
    coreutils
    noctalia
  ];

  text = ''
    black=${black}
    state="${stateFile}"

    [ -f "$state" ] || { echo "no noctalia state file at $state" >&2; exit 1; }

    # Flips `enabled` inside [wallpaper.automation] only — the file has other
    # `enabled` keys under other sections, hence the address range rather than
    # a bare substitution. Reloads before checking, so what is verified is
    # that the running shell adopted the value, not merely that sed changed a
    # byte on disk.
    set_automation() {
      local want="$1" from="$2"
      grep -q '^[[:space:]]*\[wallpaper\.automation\]' "$state" \
        || { echo "no [wallpaper.automation] section in $state" >&2; exit 1; }
      sed -i "/^[[:space:]]*\[wallpaper\.automation\]/,/^[[:space:]]*$/ s/^\([[:space:]]*\)enabled = $from/\1enabled = $want/" "$state"
      noctalia msg config-reload > /dev/null
      noctalia config export merged | grep -A2 '\[wallpaper\.automation\]' | grep -q "enabled = $want" \
        || { echo "failed to set wallpaper automation to $want" >&2; exit 1; }
    }

    # The current wallpaper path is the toggle state — no side-car state file
    # to go stale or to disagree with what is actually on screen.
    #
    # One wrinkle: $black is a store path, so a rebuild that changes the image
    # changes the path. Pressing the key while blacked out under an old path
    # therefore re-blacks with the new one instead of restoring, and the press
    # after that restores. Self-correcting, and not worth a state file.
    if [ "$(noctalia msg wallpaper-get)" = "$black" ]; then
      set_automation true false
      # A fresh random pick rather than the wallpaper that was up before:
      # the pool is capped and refreshed nightly, so a remembered path is
      # quite likely to have been evicted by the time it is restored.
      noctalia msg wallpaper-random
      echo "wallpaper rotation on"
    else
      set_automation false true
      noctalia msg wallpaper-set "$black"
      echo "background black, rotation off"
    fi
  '';

  meta = {
    description = "Toggle between a black static background and noctalia's rotating wallpaper pool";
    license = lib.licenses.mit;
    mainProgram = "wallpaper-blackout";
  };
}
