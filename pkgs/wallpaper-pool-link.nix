{
  lib,
  writeShellApplication,
  attr,
  imagemagick,
  findutils,
  coreutils,
  util-linux,
  noctalia,
  # Hour of the day the arc peaks at; the darkest images sit 12 hours away.
  brightestHour ? 12,
}:

# Links the downloaded pools and the saved wallpapers into
# ~/Pictures/Wallpapers/rotation, ordered by brightness as one daily arc:
# dark → bright → dark, so the bright images come up by day and the dark ones
# at night, behind windows dimmed by transparency. Run after either
# downloader finishes (ExecStartPost in home/wallpapers.nix), after a save
# (pkgs/wallpaper-save.nix) and on the way back from black
# (pkgs/wallpaper-blackout.nix).
#
# The point is the numbering. noctalia rotates alphabetically (see
# modules/noctalia.nix), so the `NNN_` prefix is the walk order. Alternate
# images go on the way up and the rest come back down, which ends the list
# next to where it starts and puts two images of similar brightness on
# either side of the peak.
#
# Brightness is mean luma of a 64x64 thumbnail, kept in a
# `user.wallpaper.luma` xattr so each image is measured once: pool files never
# change under their name, and a saved file is measured again only if the
# attribute did not survive whatever copied it.
#
# After relinking, the link for the current time of day is put on screen.
# That is only approximately where noctalia's rotation would be, since the
# arc length times the 30-minute interval is not a day, but every login and
# the midnight refresh land back on it, so the error never outlasts a
# session.
#
# Each link's name ends in its target's own file name, so a link path only
# ever names one image. noctalia might treat re-setting the path already up
# as no change, and that is then harmless rather than leaving the screen and
# the path disagreeing (which pkgs/wallpaper-save.nix would act on).
#
# The rotation directory belongs to this script and holds nothing but its
# links. The images themselves stay where they are: the pools in the state
# directory, saved files in ~/Pictures/Wallpapers.
writeShellApplication {
  name = "wallpaper-pool-link";

  runtimeInputs = [
    attr
    imagemagick
    findutils
    coreutils
    util-linux
    noctalia
  ];

  text = ''
    pool="''${STATE_DIRECTORY:-''${XDG_STATE_HOME:-$HOME/.local/state}/wallpaper-pool-state}"
    dir="$HOME/Pictures/Wallpapers"
    rot="$dir/rotation"
    mkdir -p "$pool" "$rot"

    # --restore: pick even over the black background.
    # pkgs/wallpaper-blackout.nix passes it on the way back, while the black
    # is still up.
    restore=""
    if [ "''${1:-}" = --restore ]; then
      restore=1
      shift
    fi

    # Optional: an image in the arc to put on screen instead of the
    # time-of-day pick. wallpaper-save passes the copy it just made, so
    # saving does not change what is showing.
    keep="''${1:-}"

    # The units and wallpaper-save all run this; the lock keeps two relinks
    # from interleaving.
    exec 9> "$pool/.link.lock"
    flock 9

    # Extension match skips a download still in flight as `<name>.part` in a
    # unit, or a copy in flight in wallpaper-save.
    mapfile -t saved < <(find "$dir" -maxdepth 1 -type f \
      -regextype posix-extended -iregex '.*\.(jpe?g|png|webp)')
    mapfile -t pooled < <(find "$pool" -maxdepth 1 -type f \
      \( -name 'reddit_*' -o -name 'wallhaven_*' \) \
      -regextype posix-extended -regex '.*\.(jpe?g|png|webp)')

    # A pool image already saved is in the arc as its saved copy; linking
    # both would show it twice. The `_<id>.<ext>` tail is what
    # wallpaper-save names its copy by.
    shopt -s nullglob
    images=("''${saved[@]}")
    for img in "''${pooled[@]}"; do
      base=''${img##*/}
      stem=''${base%.*}
      copies=("$dir"/*_"''${stem#*_}.''${base##*.}")
      (( ''${#copies[@]} )) || images+=("$img")
    done

    # An image that will not decode is left out; it would not display
    # either.
    lines=()
    for img in "''${images[@]}"; do
      luma=$(getfattr --only-values -n user.wallpaper.luma "$img" 2>/dev/null || true)
      if [ -z "$luma" ]; then
        luma=$(magick "''${img}[0]" -resize '64x64!' -colorspace Gray -format '%[fx:mean]' info: 2>/dev/null) \
          || continue
        setfattr -n user.wallpaper.luma -v "$luma" "$img" 2>/dev/null || true
      fi
      lines+=("$luma $img")
    done

    sorted=()
    if (( ''${#lines[@]} )); then
      mapfile -t sorted < <(printf '%s\n' "''${lines[@]}" | sort -g | cut -d' ' -f2-)
    fi

    arc=()
    for (( i = 0; i < ''${#sorted[@]}; i += 2 )); do
      arc+=("''${sorted[i]}")
    done
    for (( i = ''${#sorted[@]} - 1 - (''${#sorted[@]} % 2); i > 0; i -= 2 )); do
      arc+=("''${sorted[i]}")
    done

    find "$rot" -maxdepth 1 -type l -delete
    links=()
    for i in "''${!arc[@]}"; do
      link=$(printf '%s/%03d_%s' "$rot" "$((i + 1))" "''${arc[i]##*/}")
      ln -s "''${arc[i]}" "$link"
      links+=("$link")
    done
    (( ''${#links[@]} )) || exit 0

    # Not over pkgs/wallpaper-blackout.nix's black (a store path), which a
    # nightly refresh must not undo, unless blackout itself is asking. No
    # noctalia at all (Plasma) comes out as an empty answer and skips this
    # too.
    current=$(noctalia msg wallpaper-get 2>/dev/null || true)
    if [[ -z $current || ($current == /nix/store/* && -z $restore) ]]; then
      exit 0
    fi

    pick=""
    for i in "''${!arc[@]}"; do
      if [ -n "$keep" ] && [ "''${arc[i]}" = "$keep" ]; then
        pick=''${links[i]}
        break
      fi
    done
    if [ -z "$pick" ]; then
      read -r h m < <(date '+%H %M')
      secs=$(( (10#$h * 3600 + 10#$m * 60 - (${toString brightestHour} - 12) * 3600 + 86400) % 86400 ))
      pick=''${links[secs * ''${#links[@]} / 86400]}
    fi
    noctalia msg wallpaper-set "$pick" > /dev/null || true
  '';

  meta = {
    description = "Link the wallpaper pools and saved wallpapers into a daily brightness arc";
    license = lib.licenses.mit;
    mainProgram = "wallpaper-pool-link";
  };
}
