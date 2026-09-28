{
  lib,
  writeShellApplication,
  findutils,
  coreutils,
  util-linux,
}:

# Links the downloaded pools into ~/Pictures/Wallpapers as `pool-01.<ext>`,
# `pool-02.<ext>`, ..., in a fresh random order each time. Run after either
# downloader finishes (ExecStartPost in home/wallpapers.nix).
#
# The point is the numbering. noctalia rotates alphabetically (see
# modules/noctalia.nix), so shuffled names turn a sequential rotation into a
# mix of both sources through the day, with no repeat until the whole pool has
# been shown. noctalia keeps the link's own path as the current wallpaper and
# rescans every cycle, so after a relink it carries on from the same number.
#
# The images themselves stay in the state directory next to the downloaders'
# state. Only symlinks pointing into it are ever removed here, so anything
# else in ~/Pictures/Wallpapers is left alone.
writeShellApplication {
  name = "wallpaper-pool-link";

  runtimeInputs = [
    findutils
    coreutils
    util-linux
  ];

  text = ''
    pool="''${STATE_DIRECTORY:-''${XDG_STATE_HOME:-$HOME/.local/state}/wallpaper-pool-state}"
    dir="$HOME/Pictures/Wallpapers"
    mkdir -p "$pool" "$dir"

    # Both units run this; the lock keeps two relinks from interleaving.
    exec 9> "$pool/.link.lock"
    flock 9

    find "$dir" -maxdepth 1 -type l -lname "$pool/*" -delete

    # Extension match skips a download still in flight as `<name>.part` in
    # the other unit.
    mapfile -t images < <(find "$pool" -maxdepth 1 -type f \
      \( -name 'reddit_*' -o -name 'wallhaven_*' \) \
      -regextype posix-extended -regex '.*\.(jpe?g|png|webp)' | shuf)

    n=0
    for img in "''${images[@]}"; do
      n=$((n + 1))
      ln -s "$img" "$(printf '%s/pool-%02d.%s' "$dir" "$n" "''${img##*.}")"
    done
  '';

  meta = {
    description = "Link the wallpaper pools into ~/Pictures/Wallpapers in shuffled order";
    license = lib.licenses.mit;
    mainProgram = "wallpaper-pool-link";
  };
}
