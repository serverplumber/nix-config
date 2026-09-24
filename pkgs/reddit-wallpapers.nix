{
  lib,
  writeShellApplication,
  curl,
  xmlstarlet,
  findutils,
  coreutils,
  # How many reddit-sourced images to keep. Deliberately a *separate* cap from
  # the wallhaven pool's rather than one shared budget: the two scripts write
  # into the same directory, so a single mtime-ordered cap would let whichever
  # source posted more that day evict the other entirely. Two caps make the
  # mix a knob instead of a race.
  count ? 24,
  # NOTE: there is deliberately no `subreddit` argument. Which subreddit this
  # pulls from is read at runtime from $REDDIT_SUBREDDIT, supplied by the
  # out-of-band env file described in home/wallpapers.nix — the same one the
  # wallhaven key comes from. This repo is public and a nix argument would
  # bake the name into both the source and the resulting store path.
  #
  # Any image-heavy subreddit works. The extraction below only ever takes
  # direct i.redd.it links, so link-aggregator subs pointing at other image
  # hosts yield nothing rather than break.
  # reddit's `t` param on a /top listing: hour, day, week, month, year, all.
  topRange ? "month",
  # Feed page size. 100 is reddit's hard maximum for a single listing request.
  limit ? 100,
}:

# Companion to pkgs/wallhaven-wallpapers.nix: fills the same
# ~/Pictures/Wallpapers pool from a subreddit, for noctalia's directory-based
# random rotation. See home/wallpapers.nix for the wiring.
#
# It reads the Atom feed (`/top.rss`), NOT the JSON API. This is not a style
# preference — reddit now 403s the anonymous `.json` endpoints for every
# User-Agent, and `old.reddit.com` 302s them to a login page, so the only
# remaining no-credentials routes are OAuth (which would mean a registered
# app and a client secret kept out of the nix store) or the RSS/Atom feed,
# which still serves 200 unauthenticated, age-gated subreddits included and
# with no interstitial cookie. The feed is strictly less metadata than the
# JSON, but it does carry the one thing that matters: each post's
# full-resolution i.redd.it URL, alongside the `t3_<id>` post id.
#
# Every file this script writes or deletes is named `reddit_<postid>.<ext>`.
# As with the wallhaven script, that prefix is the safety boundary: nothing
# outside `reddit_*` in the target directory is ever read or removed, so the
# two pools cannot evict each other's files and hand-dropped wallpapers under
# any other name are untouched.
writeShellApplication {
  name = "reddit-wallpapers";

  runtimeInputs = [
    curl
    xmlstarlet
    findutils
    coreutils
  ];

  text = ''
    # Not configured is not an error: the unit ships enabled, and a machine
    # that has not been given a subreddit should stay quiet rather than fail
    # and retry five times. Says so on stderr, which lands in the journal, so
    # a typo'd env file is still findable.
    if [ -z "''${REDDIT_SUBREDDIT:-}" ]; then
      echo "REDDIT_SUBREDDIT is unset — nothing to pull, skipping" >&2
      exit 0
    fi

    dir="$HOME/Pictures/Wallpapers"
    mkdir -p "$dir"

    feed_url="https://www.reddit.com/r/$REDDIT_SUBREDDIT/top.rss?t=${topRange}&limit=${toString limit}"

    # reddit answers a bare or spoofed-browser User-Agent with 429 fairly
    # readily. A descriptive one is what its API docs ask for, and the unit's
    # Restart=on-failure covers the 429s that happen anyway.
    feed=$(curl -fsSL -A "nixos-wallpaper-pool/1.0" "$feed_url")

    # Two-layer parse, on purpose. xmlstarlet handles the XML (namespaced
    # Atom, one <entry> per post) and yields `t3_<id>|<escaped html>`; the
    # image link only exists *inside* that escaped HTML blob, so a regex is
    # unavoidable for the second layer. Posts with no direct image link —
    # galleries, video, text — simply fail to match and are skipped.
    pairs=$(
      printf '%s' "$feed" \
        | xmlstarlet sel -N a=http://www.w3.org/2005/Atom \
            -t -m '//a:entry' -v 'a:id' -o '|' -v 'a:content' -n \
        | sed -n 's#^t3_\([a-z0-9]*\)|.*[^a-z]\(https://i\.redd\.it/[A-Za-z0-9_-]*\.\(jpe\?g\|png\|webp\)\).*#\1 \2#p'
    )

    while read -r id url; do
      [ -z "$id" ] && continue
      ext="''${url##*.}"
      target="$dir/reddit_''${id}.''${ext}"
      # Post ids are stable, so an existing file means "already have it".
      if [ ! -e "$target" ]; then
        curl -fsSL -A "nixos-wallpaper-pool/1.0" -o "$target.part" "$url"
        mv "$target.part" "$target"
      fi
    done <<< "$pairs"

    # Enforce the cap, oldest download first. Never touches files without the
    # reddit_ prefix.
    mapfile -t existing < <(find "$dir" -maxdepth 1 -type f -name 'reddit_*' -printf '%T@ %p\n' | sort -n | cut -d' ' -f2-)
    excess=$(( ''${#existing[@]} - ${toString count} ))
    if (( excess > 0 )); then
      for ((i = 0; i < excess; i++)); do
        rm -f "''${existing[$i]}"
      done
    fi
  '';

  meta = {
    description = "Refresh a capped pool of subreddit wallpapers for noctalia's directory rotation";
    license = lib.licenses.mit;
    mainProgram = "reddit-wallpapers";
  };
}
