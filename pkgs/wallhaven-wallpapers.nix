{
  lib,
  writeShellApplication,
  curl,
  jq,
  findutils,
  coreutils,
  # How many wallhaven-sourced images to keep around. Oldest-downloaded goes
  # first once this is exceeded, so the pool tracks the current toplist
  # instead of growing forever.
  count ? 24,
  # wallhaven's `topRange` search param: 1d, 3d, 1w, 1M, 3M, 6M, 1y.
  topRange ? "1M",
}:

# Pulls wallhaven's SFW toplist and drops it in ~/Pictures/Wallpapers, purely
# as a static image pool for noctalia's own directory-based random rotation —
# see home/wallhaven.nix for why this exists instead of driving noctalia's
# built-in Wallhaven browse panel.
#
# Every file this script writes or deletes is named `wallhaven_<id>.<ext>`,
# matching the naming noctalia's own Wallhaven panel already uses for manual
# downloads. That prefix is also the safety boundary: this script only ever
# touches files matching `wallhaven_*` in the target directory, so anything
# dropped in by hand under any other name is never looked at, let alone
# deleted.
writeShellApplication {
  name = "wallhaven-wallpapers";

  runtimeInputs = [
    curl
    jq
    findutils
    coreutils
  ];

  text = ''
    dir="$HOME/Pictures/Wallpapers"
    mkdir -p "$dir"

    api_url="https://wallhaven.cc/api/v1/search?sorting=toplist&topRange=${topRange}&purity=100&categories=111"

    response=$(curl -fsSL "$api_url")

    # id + full-resolution image URL, one pair per line.
    pairs=$(printf '%s' "$response" | jq -r '.data[] | "\(.id) \(.path)"')

    while read -r id url; do
      [ -z "$id" ] && continue
      ext="''${url##*.}"
      target="$dir/wallhaven_''${id}.''${ext}"
      # Wallhaven ids are stable, so an existing file means "already have it".
      if [ ! -e "$target" ]; then
        curl -fsSL -o "$target.part" "$url"
        mv "$target.part" "$target"
      fi
    done <<< "$pairs"

    # Enforce the cap, oldest download first. Never touches files without the
    # wallhaven_ prefix.
    mapfile -t existing < <(find "$dir" -maxdepth 1 -type f -name 'wallhaven_*' -printf '%T@ %p\n' | sort -n | cut -d' ' -f2-)
    excess=$(( ''${#existing[@]} - ${toString count} ))
    if (( excess > 0 )); then
      for ((i = 0; i < excess; i++)); do
        rm -f "''${existing[$i]}"
      done
    fi
  '';

  meta = {
    description = "Refresh a capped pool of wallhaven toplist wallpapers for noctalia's directory rotation";
    license = lib.licenses.mit;
    mainProgram = "wallhaven-wallpapers";
  };
}
