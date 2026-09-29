{
  lib,
  writeShellApplication,
  attr,
  libnotify,
  gnused,
  coreutils,
  noctalia,
}:

# Keep the wallpaper on screen: copy it out of the pool, which evicts on a
# cap, into ~/Pictures/Wallpapers as a plain file under a readable name.
# Bound to Mod+Ctrl+Alt+B in home/wallpapers.nix.
#
# The name is `<title>_<id>.<ext>` when the downloader recorded a title (only
# reddit does, as a `user.dublincore.title` xattr; see
# pkgs/reddit-wallpapers.nix), and `<source>_<id>.<ext>` otherwise. The id is
# in both, so two posts with the same title never collide, and a second press
# on the same image is recognised whichever name the first one chose.
#
# The copy lands in the rotation directory, so it stays in rotation.
# pkgs/wallpaper-pool-link.nix only ever removes symlinks into the pool, so a
# plain file there is never touched. It does not join the shuffle, though:
# rotation is alphabetical, so saved files show up as one run outside the
# `pool-NN` block.
writeShellApplication {
  name = "wallpaper-save";

  runtimeInputs = [
    attr
    libnotify
    gnused
    coreutils
    noctalia
  ];

  text = ''
    pool="''${XDG_STATE_HOME:-$HOME/.local/state}/wallpaper-pool-state"
    dir="$HOME/Pictures/Wallpapers"

    # Run from a keybind, so stdout goes nowhere; a notification is the only
    # way the result is seen.
    notify() {
      notify-send --app-name=wallpaper-save "$1" "$2" 2>/dev/null || true
    }

    img=$(readlink -f "$(noctalia msg wallpaper-get)")

    # Anything outside the pool is already a plain file: blackout's black
    # image, or a wallpaper saved earlier and now showing under its own name.
    case "$img" in
      "$pool"/reddit_* | "$pool"/wallhaven_*) ;;
      *)
        notify "Nothing to save" "The current wallpaper is not from the pool."
        exit 0
        ;;
    esac

    base=''${img##*/}
    ext=''${base##*.}
    stem=''${base%.*}
    source=''${stem%%_*}
    id=''${stem#*_}

    shopt -s nullglob
    already=("$dir"/*_"$id"."$ext")
    if (( ''${#already[@]} )); then
      notify "Already saved" "''${already[0]##*/}"
      exit 0
    fi

    # Anything outside [A-Za-z0-9.-] becomes `_` and runs collapse to one: no
    # spaces, no `/`, and once it is ASCII the byte cut cannot split a
    # character. Leading dots and underscores go too (a leading dot would
    # hide the file), as do trailing underscores before the `_<id>`.
    title=$(getfattr --only-values -n user.dublincore.title "$img" 2>/dev/null || true)
    name=$(printf '%s' "$title" | tr -c 'A-Za-z0-9.-' '_' | tr -s '_' | cut -c1-80 \
      | sed -E 's/^[._]+//; s/_+$//')
    if [ -z "$name" ]; then
      name=$source
    fi

    file="''${name}_$id.$ext"
    # Written as `.part` first so noctalia's rescan never picks up a half
    # copy; the extension keeps it out of the image filter until the rename.
    cp "$img" "$dir/$file.part"
    mv "$dir/$file.part" "$dir/$file"
    notify "Wallpaper saved" "$file"
  '';

  meta = {
    description = "Copy the current pool wallpaper into ~/Pictures/Wallpapers under a readable name";
    license = lib.licenses.mit;
    mainProgram = "wallpaper-save";
  };
}
