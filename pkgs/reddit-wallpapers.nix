{
  lib,
  writeShellApplication,
  curl,
  xmlstarlet,
  file,
  findutils,
  coreutils,
  # How many reddit-sourced images to keep, and how many new ones a run
  # fetches. Deliberately a *separate* cap from the wallhaven pool's rather
  # than one shared budget: the two scripts write into the same directory, so
  # a single mtime-ordered cap would let whichever source posted more that day
  # evict the other entirely. Two caps make the mix a knob instead of a race.
  count ? 12,
  # NOTE: there is deliberately no `subreddit` argument. Which subreddit this
  # pulls from is read at runtime from $REDDIT_SUBREDDIT; see the env file
  # below.
  #
  # Any image-heavy subreddit works. The extraction below only ever takes
  # direct i.redd.it links, so link-aggregator subs pointing at other image
  # hosts yield nothing rather than break.
  # Feed page size. 100 is reddit's hard maximum for a single listing request.
  limit ? 100,
  # Most feed requests one run may make, head and tail together. Rejected
  # images make the tail walk further to reach `count`, and reddit hands out
  # 429s readily, so a subreddit of mostly phone wallpapers must not turn into
  # ten requests in a row.
  maxPages ? 5,
  # What fits the monitors here: 3840x2400 (16:10) and 3840x2160 (16:9).
  # Aspect is width/height x100, so 160 and 178 for those two. The range is
  # wider than the pair because noctalia crops to fill anyway; its job is to
  # turn away portrait phone wallpapers and ultrawides.
  minWidth ? 2560,
  minHeight ? 1440,
  minAspect ? 150,
  maxAspect ? 180,
}:

# Companion to pkgs/wallhaven-wallpapers.nix: fills the same pool from a
# subreddit, for noctalia's directory-based rotation. The pool lives in the
# units' state directory and is linked into ~/Pictures/Wallpapers by
# pkgs/wallpaper-pool-link.nix. See home/wallpapers.nix for the wiring.
#
# It reads the Atom feed (`/new.rss`), NOT the JSON API. This is not a style
# preference — reddit now 403s the anonymous `.json` endpoints for every
# User-Agent, and `old.reddit.com` 302s them to a login page, so the only
# remaining no-credentials routes are OAuth (which would mean a registered
# app and a client secret kept out of the nix store) or the RSS/Atom feed,
# which still serves 200 unauthenticated, age-gated subreddits included and
# with no interstitial cookie. The feed is strictly less metadata than the
# JSON, but it does carry the one thing that matters: each post's
# full-resolution i.redd.it URL, alongside the `t3_<id>` post id. It does not
# carry image dimensions, so those are checked after download.
#
# `new`, not `top`: a date-ordered listing never reshuffles, so everything
# seen is one contiguous stretch of it, bounded by two post ids kept in the
# state file. Each run first takes what was posted since the newer mark
# (oldest first, so the mark only ever moves over posts actually looked at),
# then, if that fell short of `count`, pages back in time from the older mark.
# Post ids are base-36 and assigned in order, so they compare as numbers.
# Rejected posts still move the marks: seen means looked at, not kept.
#
# Every file this script writes or deletes is named `reddit_<postid>.<ext>`.
# As with the wallhaven script, that prefix is the safety boundary: nothing
# outside `reddit_*` in the target directory is ever read or removed, so the
# two pools cannot evict each other's files.
#
# The unit in home/wallpapers.nix loads ~/.config/wallpaper-pool/env as its
# environment. Put the subreddit there:
#
#   REDDIT_SUBREDDIT=...
writeShellApplication {
  name = "reddit-wallpapers";

  runtimeInputs = [
    curl
    xmlstarlet
    file
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

    # $STATE_DIRECTORY comes from the unit's StateDirectory=; the fallback is
    # the same path, for a run by hand. It holds the images and the marks.
    # One marks file per subreddit: marks from another subreddit point into a
    # listing they are not part of.
    dir="''${STATE_DIRECTORY:-''${XDG_STATE_HOME:-$HOME/.local/state}/wallpaper-pool-state}"
    mkdir -p "$dir"
    state="$dir/reddit-$REDDIT_SUBREDDIT"
    high="" low=""
    if [ -s "$state" ]; then
      read -r high low < "$state"
    fi
    save() { echo "$high $low" > "$state"; }

    agent="nixos-wallpaper-pool/1.0"
    pages=0
    fetched=0

    # One `<id> <image url or ->` line per post, newest first. $1 is the id to
    # page past, or empty for the top of the listing.
    #
    # reddit answers a bare or spoofed-browser User-Agent with 429 fairly
    # readily. A descriptive one is what its API docs ask for, and the unit's
    # Restart=on-failure covers the 429s that happen anyway.
    fetch_page() {
      local url="https://www.reddit.com/r/$REDDIT_SUBREDDIT/new.rss?limit=${toString limit}"
      if [ -n "$1" ]; then
        url="$url&after=t3_$1"
      fi
      # Explicit return: this runs inside $(...), where errexit does not
      # reach, and a 429 read as an empty page would end the run as a success
      # instead of letting Restart=on-failure retry it.
      local feed
      feed=$(curl -fsSL -A "$agent" "$url") || return
      # The image link only exists inside the entry's escaped HTML, so a
      # regex is unavoidable for that layer. normalize-space keeps each entry
      # on one line. `|| true` because xmlstarlet exits 1 on an empty page.
      # Galleries, video and text posts have no direct link and come out as
      # `-`: still seen, never kept.
      printf '%s' "$feed" \
        | { xmlstarlet sel -N a=http://www.w3.org/2005/Atom \
              -t -m '//a:entry' -v 'a:id' -o ' ' -v 'normalize-space(a:content)' -n || true; } \
        | while read -r tid content; do
            [[ $tid =~ ^t3_([a-z0-9]+)$ ]] || continue
            local img
            img=$(grep -oE 'https://i\.redd\.it/[A-Za-z0-9_-]+\.(jpe?g|png|webp)' <<< "$content" | head -n1 || true)
            echo "''${BASH_REMATCH[1]} ''${img:--}"
          done
    }

    # Download one post's image and keep it only if it fits the monitors.
    # A failed download counts as a rejection: a deleted image 404s forever,
    # and failing the unit over it would retry the same post five times.
    take() {
      local id=$1 url=$2
      [ "$url" != - ] || return 1
      local target="$dir/reddit_$id.''${url##*.}"
      curl -fsSL -A "$agent" -o "$target.part" "$url" || { rm -f "$target.part"; return 1; }
      # `file` prints the size last for JPEG, PNG and WebP; a JFIF density
      # like 72x72 can come earlier, hence the last match.
      local dims w h
      dims=$(file -b "$target.part" | grep -oE '[0-9]+ ?x ?[0-9]+' | tail -n1 || true)
      dims=''${dims// /}
      w=''${dims%x*} h=''${dims#*x}
      if [ -n "$dims" ] \
        && (( w >= ${toString minWidth} && h >= ${toString minHeight} )) \
        && (( w * 100 >= h * ${toString minAspect} && w * 100 <= h * ${toString maxAspect} )); then
        mv "$target.part" "$target"
      else
        rm -f "$target.part"
        return 1
      fi
    }

    # Head: everything posted since the newer mark. Skipped on a first run,
    # where there is no mark and the tail simply starts from the top.
    if [ -n "$high" ]; then
      new=()
      after=""
      reached=0
      while (( pages < ${toString maxPages} && ! reached )); do
        out=$(fetch_page "$after")
        pages=$((pages + 1))
        [ -n "$out" ] || break
        while read -r id url; do
          if (( 36#$id <= 36#$high )); then
            reached=1
            break
          fi
          new+=("$id $url")
        done <<< "$out"
        after=''${out##*$'\n'}
        after=''${after%% *}
      done
      # If the page budget ran out before reaching the mark, the posts between
      # the deepest page read and the mark are skipped for good. Only a
      # subreddit posting hundreds a day gets here.
      for ((i = ''${#new[@]} - 1; i >= 0 && fetched < ${toString count}; i--)); do
        read -r id url <<< "''${new[i]}"
        if take "$id" "$url"; then
          fetched=$((fetched + 1))
        fi
        high=$id
        save
      done
    fi

    # Tail: back in time from the older mark. An empty page ends it — the
    # listing stops about 1000 posts back, after which only the head feeds
    # the pool.
    after=$low
    while (( fetched < ${toString count} && pages < ${toString maxPages} )); do
      out=$(fetch_page "$after")
      pages=$((pages + 1))
      [ -n "$out" ] || break
      while read -r id url; do
        (( fetched < ${toString count} )) || break
        [ -n "$high" ] || high=$id
        if take "$id" "$url"; then
          fetched=$((fetched + 1))
        fi
        low=$id
        save
      done <<< "$out"
      after=$low
    done

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
