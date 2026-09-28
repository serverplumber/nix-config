{
  lib,
  writeShellApplication,
  curl,
  jq,
  findutils,
  coreutils,
  # How many wallhaven-sourced images to keep: the top `count` of the current
  # toplist, nothing else.
  count ? 12,
  # wallhaven's `topRange` search param: 1d, 3d, 1w, 1M, 3M, 6M, 1y.
  topRange ? "1M",
  # wallhaven's `categories` bitmask: general / anime / people.
  #
  # The middle bit is off deliberately. With all three on, roughly a third of
  # the toplist is the anime category (measured: 7 of 24 on a 1M toplist
  # page), which is not what this pool is for. Turning the bit off is a
  # server-side filter, so the quota is spent on wallpapers that will actually
  # be used rather than downloading and discarding.
  #
  # The `people` bit stays on: that category is photography of people, not
  # illustration, and is a large part of the point of the pool.
  categories ? "101",
  # wallhaven's `purity` bitmask, three bits, least permissive first.
  #
  # `110` is the most this can ask for anonymously. The third bit requires an
  # authenticated request, and the failure mode is the dangerous kind:
  # wallhaven does not error on `purity=111` without a key, it silently drops
  # that bit and serves the first two anyway (while `purity=001` alone returns
  # an empty result set). So an over-broad value here looks like it worked.
  # To use the third bit, create an API key at
  # https://wallhaven.cc/settings/account, keep it outside the nix store —
  # which is world-readable, so it must never be inlined here — and let the
  # unit pass it in via $WALLHAVEN_API_KEY; see the env file below.
  purity ? "110",
  # What fits the monitors here: 3840x2400 (16:10) and 3840x2160 (16:9).
  # Both are server-side filters, so no quota goes on portrait phone
  # wallpapers. The floor is below the panels' native size because an exact
  # 4K floor thins the toplist a lot, and 1.5x upscaling holds up fine.
  ratios ? "16x9,16x10",
  atleast ? "2560x1440",
}:

# Pulls wallhaven's toplist into the units' state directory, purely as a
# static image pool for noctalia's own directory-based rotation — see
# home/wallpapers.nix for why this exists instead of driving noctalia's
# built-in Wallhaven browse panel. pkgs/wallpaper-pool-link.nix links the
# pool into ~/Pictures/Wallpapers.
#
# Every file this script writes or deletes is named `wallhaven_<id>.<ext>`,
# matching the naming noctalia's own Wallhaven panel uses for manual
# downloads. That prefix is also the safety boundary: this script only ever
# touches files matching `wallhaven_*` in the pool, which it shares with the
# reddit script.
#
# The unit in home/wallpapers.nix loads ~/.config/wallpaper-pool/env as its
# environment. Put the API key there:
#
#   WALLHAVEN_API_KEY=...
writeShellApplication {
  name = "wallhaven-wallpapers";

  runtimeInputs = [
    curl
    jq
    findutils
    coreutils
  ];

  text = ''
    # $STATE_DIRECTORY comes from the unit's StateDirectory=; the fallback is
    # the same path, for a run by hand.
    dir="''${STATE_DIRECTORY:-''${XDG_STATE_HOME:-$HOME/.local/state}/wallpaper-pool-state}"
    mkdir -p "$dir"

    api_url="https://wallhaven.cc/api/v1/search?sorting=toplist&topRange=${topRange}&purity=${purity}&categories=${categories}&ratios=${ratios}&atleast=${atleast}"

    # Optional, and only meaningful for the third purity bit — see the
    # `purity` argument above. Appended rather than baked into api_url so the
    # key never appears in a nix store path or a build log.
    if [ -n "''${WALLHAVEN_API_KEY:-}" ]; then
      api_url="$api_url&apikey=$WALLHAVEN_API_KEY"
    fi

    response=$(curl -fsSL "$api_url")

    # id + full-resolution image URL, one pair per line, top `count` only.
    pairs=$(printf '%s' "$response" | jq -r '.data[:${toString count}][] | "\(.id) \(.path)"')

    while read -r id url; do
      [ -z "$id" ] && continue
      ext="''${url##*.}"
      target="$dir/wallhaven_''${id}.''${ext}"
      # Wallhaven ids are stable, so an existing file means "already have it".
      # It is touched instead, so the mtime cap below evicts what fell off the
      # toplist, not whatever happened to be downloaded first.
      if [ -e "$target" ]; then
        touch "$target"
      else
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
