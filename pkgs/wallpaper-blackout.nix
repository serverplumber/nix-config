{
  lib,
  writeShellApplication,
  runCommand,
  imagemagick,
  gnused,
  findutils,
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

  # Where to pick up again on restore: the wallpaper after the one that was
  # up when the background went black.
  resumeFile = "\${XDG_STATE_HOME:-$HOME/.local/state}/wallpaper-blackout-resume";
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
    findutils
    coreutils
    noctalia
  ];

  text = ''
    black=${black}
    state="${stateFile}"
    resume="${resumeFile}"

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
    # to go stale or to disagree with what is actually on screen. The resume
    # file below only says where to pick up, never which way to toggle.
    #
    # One wrinkle: $black is a store path, so a rebuild that changes the image
    # changes the path. Pressing the key while blacked out under an old path
    # therefore re-blacks with the new one instead of restoring, and the press
    # after that restores. Self-correcting, and not worth a state file.
    current=$(noctalia msg wallpaper-get)
    if [ "$current" = "$black" ]; then
      set_automation true false
      # Restore goes to the wallpaper after the one blacked out, not back to
      # it: the key doubles as "skip this one". Worked out on the way in and
      # set directly here, in one transition.
      #
      # The remembered path survives a nightly refresh: a pool wallpaper is
      # remembered as its `pool-NN` link, and the numbers are recreated on
      # every relink (pkgs/wallpaper-pool-link.nix), only pointing at other
      # images. Only a pool that shrank below that number, or a saved file
      # deleted meanwhile, falls back to a random pick.
      next=$(cat "$resume" 2>/dev/null || true)
      if [ -n "$next" ] && [ -e "$next" ]; then
        noctalia msg wallpaper-set "$next"
      else
        noctalia msg wallpaper-random
      fi
      rm -f "$resume"
      echo "wallpaper rotation on"
    else
      set_automation false true
      # `wallpaper-next` cannot be asked for from black — black is not in
      # the rotation, so noctalia would start over from the first file — and
      # cannot be called now either, since it switches rather than answers.
      # So the next one is worked out here: noctalia's order is the `ls`
      # order of the image files in the current one's directory, which a
      # case-insensitive version sort matches closely enough. An edge case
      # it gets wrong costs a different wallpaper, nothing more.
      #
      # Skipped when the current one is an older build's black (the wrinkle
      # above): that is no place to resume from, and the path remembered on
      # the way into it is still the right one.
      if [[ $current != /nix/store/* ]]; then
        mapfile -t images < <(find "$(dirname "$current")" -maxdepth 1 -xtype f \
          -regextype posix-extended -iregex '.*\.(jpe?g|png|webp)' | sort -f -V)
        next=""
        for i in "''${!images[@]}"; do
          if [ "''${images[i]}" = "$current" ]; then
            next=''${images[(i + 1) % ''${#images[@]}]}
            break
          fi
        done
        mkdir -p "$(dirname "$resume")"
        printf '%s\n' "$next" > "$resume"
      fi
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
