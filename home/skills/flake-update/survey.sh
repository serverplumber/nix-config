#!/usr/bin/env bash
# State for the flake-update skill. Five questions, five subcommands, because
# they differ in cost by two orders of magnitude and a single "dump everything"
# call would make the cheap ones hostage to the slow ones:
#
#   state     — what is running, what is owed, what failed   (instant, offline)
#   inputs    — locked rev vs upstream head, per root input  (~10s, network)
#   kludges   — the workaround inventory                     (instant, offline)
#   warnings  — evaluation warnings for the laptop closure    (~60s, measured)
#   versions  — locked vs upstream version of named attrs    (~5s + fetch)
#
# No arguments runs the three cheap ones. Nothing here writes: no flake.lock,
# no generation, no config. `nix eval` and `git ls-remote` only.
#
# ── Facts this script exists to encode ─────────────────────────────────────
#
# `just have <attr>` does the same job as `versions` and is DOCUMENTED IN
# CLAUDE.md, but it is broken (2026-09-24): `just have` reaches nix through the
# `nix` → `_nix` passthrough recipes, whose `{{args}}` interpolation is
# unquoted, so the expression is word-split and nix reports
# `flag '--expr' requires 1 argument(s), but only 0 were given`. Fails with one
# attribute as readily as with three. `versions` calls nix directly for exactly
# that reason — do not reintroduce the indirection.
#
# flake.lock's NODE names are not INPUT names. Today the node called `nixpkgs`
# is hyprland's pin (which deliberately does not follow ours, see flake.nix)
# and this repo's own nixpkgs is the node called `nixpkgs_2`. Resolving through
# `.locks.nodes.root.inputs` is not pedantry — reading the node named
# `nixpkgs` gives the wrong answer on this flake.
#
# Upstream heads come from `git ls-remote`, not `nix flake metadata <url>`:
# ls-remote is one request that fetches no tree (0.4s for a small repo, ~8s for
# nixpkgs), where resolving a flake ref downloads the whole tarball to hash it.
#
# `versions` resolves github:NixOS/nixpkgs/nixos-unstable through getFlake,
# which is subject to nix's tarball-ttl (1h), so its upstream column can be up
# to an hour stale. Set SURVEY_REFRESH=1 to pass --refresh and pay a re-fetch.
#
# Evaluation warnings are NOT hidden by nix's eval cache — measured 2026-09-24,
# the same warning printed on a second identical run. `--no-eval-cache` is
# passed anyway so this does not depend on that remaining true.
#
# An UNTRACKED file anywhere in the repo makes the eval fail outright —
# `error: Path 'home/skills/x' in the repository ... is not tracked by Git`,
# raised while evaluating `warnings`, which reads as a problem with the config
# rather than with git. `warnings` checks for this first and says so; the fix is
# `git add` (staging is reversible, and these are files you meant to keep).
# Learned the hard way on 2026-09-24, by this skill's own files.
#
# Dependencies: nix, git, coreutils, grep — plus jq for `inputs`, which is
# declared in home/dev.nix and so is on PATH for this user, but the section
# degrades to a message rather than a crash if it ever is not.

set -uo pipefail

repo="${SURVEY_REPO:-}"
if [ -z "$repo" ]; then
  if [ -f "$PWD/flake.nix" ]; then repo="$PWD"; else repo="$HOME/code/nix-config"; fi
fi

nixf=(--extra-experimental-features nix-command --extra-experimental-features flakes)
[ -n "${SURVEY_REFRESH:-}" ] && nixf+=(--refresh)

rule() { printf '════════════════════════════════════════════════════════════\n'; }
have() { command -v "$1" >/dev/null 2>&1; }

if ! have nix; then
  echo "!! no host nix on PATH. Everything below that evaluates or resolves is"
  echo "!! unavailable; the justfile's podman route is for building, not for a"
  echo "!! survey. Run this on the laptop."
  exit 1
fi

# ── state ───────────────────────────────────────────────────────────────────
# Same three-file test as `just needs-reboot`, reimplemented rather than
# shelled out to: this must answer even when run from a copy of the repo, or
# from a directory with no justfile.
cmd_state() {
  rule
  echo "RUNNING SYSTEM"
  rule
  if [ ! -e /run/current-system ]; then
    echo "  not running NixOS — nothing to compare against"
    return
  fi
  echo "  current-system: $(basename "$(readlink -f /run/current-system)")"
  echo "  booted-system:  $(basename "$(readlink -f /run/booted-system)")"
  echo "  kernel:         $(uname -r)"

  owed=0
  for f in kernel kernel-modules initrd; do
    if [ "$(readlink -f /run/booted-system/$f)" != "$(readlink -f /run/current-system/$f)" ]; then
      echo "  !! $f differs from the booted system"
      owed=1
    fi
  done
  if [ "$owed" = 1 ]; then
    echo "  !! A REBOOT IS ALREADY OWED from an earlier switch. Any nvidia or"
    echo "  !! kernel symptom reported now may be that, not the update."
  else
    echo "  booted system is current"
  fi

  echo
  echo "  failed system units:"
  systemctl --failed --no-legend --plain 2>/dev/null | sed 's/^/    /' | grep . || echo "    none"
  echo "  failed user units:"
  systemctl --user --failed --no-legend --plain 2>/dev/null | sed 's/^/    /' | grep . || echo "    none"
  echo
}

# ── inputs ──────────────────────────────────────────────────────────────────
cmd_inputs() {
  rule
  echo "ROOT INPUTS — locked vs upstream head"
  rule
  if ! have jq; then
    echo "  jq missing (declared in home/dev.nix) — skipping. Read flake.lock by hand."
    return
  fi
  meta=$(nix "${nixf[@]}" flake metadata --json "$repo" 2>/dev/null)
  if [ -z "$meta" ]; then
    echo "  could not read flake metadata for $repo"
    return
  fi
  printf '  %-16s %-12s %-12s %-22s %s\n' INPUT LOCKED HEAD LOCKED-DATE REPO/REF
  while IFS=$'\t' read -r name owner rrepo ref rev when; do
    [ -n "$name" ] || continue
    url="https://github.com/$owner/$rrepo"
    if [ "$ref" = "default" ]; then
      head=$(git ls-remote "$url" HEAD 2>/dev/null | awk 'NR==1{print $1}')
    else
      head=$(git ls-remote "$url" "refs/heads/$ref" 2>/dev/null | awk 'NR==1{print $1}')
    fi
    head=${head:-"?"}
    mark="  "
    [ "${head:0:12}" = "${rev:0:12}" ] && mark="= " || mark="→ "
    [ "$head" = "?" ] && mark="? "
    printf '%s%-16s %-12s %-12s %-22s %s\n' \
      "$mark" "$name" "${rev:0:12}" "${head:0:12}" "$when" "$owner/$rrepo@$ref"
  done < <(printf '%s' "$meta" | jq -r '
    .locks as $l | $l.nodes.root.inputs | to_entries[]
    | .key as $name | ($l.nodes[.value]) as $v
    | [ $name, $v.locked.owner, $v.locked.repo,
        ($v.original.ref // "default"), $v.locked.rev,
        ($v.locked.lastModified | todate) ] | @tsv' | sort)
  echo
  echo "  '=' nothing upstream to review.  '→' moved.  '?' head unknown (offline?)."
  echo "  Node names in flake.lock are NOT input names — this reads root.inputs."
  echo
}

# ── kludges ─────────────────────────────────────────────────────────────────
# Code only. bluefin-to-nixos-migration.md and package-migration.md hold the
# reasoning behind several of these, but they are a record of past decisions —
# grepping them produces hits that cannot be removed. Read them for context on
# a hit found here; never treat them as inventory.
cmd_kludges() {
  # An array, not a word-split string: `grep "${files[@]}"` is the only form
  # that survives a path with a space in it, and shellcheck is clean on it —
  # pkgs/sdbackup.nix lints its own shell at build time, so this file should
  # hold to the same bar.
  local -a files=()
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    files+=("$f")
  done < <(cd "$repo" && find . -name '*.nix' -not -path './docs/*' -not -path './.git/*' | sort)
  files+=("./justfile")

  rule
  echo "KLUDGE INVENTORY  (read the WHOLE comment around each hit — this repo"
  echo "writes down why, and that comment is the spec for the removal test)"
  rule

  echo
  echo "── marker words ────────────────────────────────────────────────────"
  (cd "$repo" && grep -rniE \
    "workaround|kludge|\bhack\b|\bTODO\b|\bFIXME\b|for now|temporar|until upstream|until (a|the) fix|parked|waiting on|no fix|still (open|unresolved|broken)|upstream (bug|issue|fix|pr)|regression|re-add|revert" \
    "${files[@]}" 2>/dev/null) | sed 's/^/  /' | grep . || echo "  none"

  echo
  echo "── upstream tickets referenced (read each before touching its site) ──"
  (cd "$repo" && grep -rnoE \
    "(https?://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/(issues|pull)/[0-9]+|[A-Za-z][A-Za-z0-9._-]*#[0-9]{2,7})" \
    "${files[@]}" 2>/dev/null) | sed 's/^/  /' | grep . || echo "  none"

  echo
  echo "── structural: overrides, forces, patches, skipped checks ───────────"
  (cd "$repo" && grep -rnE \
    "overrideAttrs|overridePythonAttrs|\.override[ ({]|nixpkgs\.overlays|fetchpatch|^\s*patches\s*=|mkForce|mkOverride|doInstallCheck\s*=\s*false|doCheck\s*=\s*false|dontCheck" \
    "${files[@]}" 2>/dev/null) | sed 's/^/  /' | grep . || echo "  none"

  echo
  echo "── local derivations (each is a bet that nixpkgs lacks the package) ──"
  if [ -d "$repo/pkgs" ]; then
    (cd "$repo" && find pkgs -name '*.nix' | sort | sed 's/^/  /')
    echo "  → check each attr name with: survey.sh versions <attr>"
  else
    echo "  none"
  fi

  echo
  echo "── 20 oldest dated claims (a stale date is a stale measurement) ─────"
  (cd "$repo" && grep -rnoE "20[0-9][0-9]-[01][0-9]-[0-3][0-9]" "${files[@]}" 2>/dev/null) |
    awk -F: '{print $3"\t"$1":"$2}' | sort | sed 's/^/  /' | head -20 | grep . || echo "  none"
  echo
}

# ── warnings ────────────────────────────────────────────────────────────────
# Evaluates the laptop closure without building it: the drvPath forces the
# whole module system, which is what raises the warnings, and costs ~60s.
# `just check` is the wider net (all four outputs, plus assertions); this is
# the one that reproduces exactly what a `nixos-rebuild` would have printed.
cmd_warnings() {
  rule
  echo "EVALUATION WARNINGS — nixosConfigurations.laptop (~60s, no build)"
  rule
  # Untracked files abort the eval with an error about git, surfaced as if the
  # option `warnings' were at fault. Say it plainly before spending the minute.
  local untracked
  untracked=$(git -C "$repo" ls-files --others --exclude-standard 2>/dev/null | head -5)
  if [ -n "$untracked" ]; then
    echo "  !! untracked files present — the eval WILL fail on them:"
    printf '%s\n' "$untracked" | sed 's/^/  !!   /'
    echo "  !! 'git add' them first (reversible); nix cannot read untracked"
    echo "  !! paths out of a dirty tree."
    echo
  fi
  out=$(nix "${nixf[@]}" eval --no-eval-cache --raw \
    "$repo#nixosConfigurations.laptop.config.system.build.toplevel.drvPath" 2>&1)
  printf '%s\n' "$out" | grep -E "warning|trace:|error" | sed 's/^/  /' | grep . ||
    echo "  none — the closure evaluates clean"
  echo
  printf '%s\n' "$out" | grep -E "^/nix/store/.*\.drv$" | sed 's/^/  drv: /'
  echo
  echo "  A warning naming an attribute or option THIS REPO writes is yours to"
  echo "  fix. Grep the stem, not the suggested replacement: a warning saying"
  echo "  'use libreoffice-stable' is raised by our libreoffice-fresh."
  echo
}

# ── versions ────────────────────────────────────────────────────────────────
cmd_versions() {
  if [ "$#" -eq 0 ]; then
    echo "usage: survey.sh versions <attr>... (e.g. linuxPackages.kernel libreoffice-fresh)"
    return 1
  fi
  local list
  list=$(printf '"%s" ' "$@")
  rule
  echo "PACKAGE VERSIONS — locked pin vs nixos-unstable HEAD"
  rule
  nix "${nixf[@]}" eval --impure --raw --expr "
    let
      self = builtins.getFlake \"$repo\";
      lib = self.inputs.nixpkgs.lib;
      mk = f: import f { system = \"x86_64-linux\"; config.allowUnfree = true; };
      locked = mk self.inputs.nixpkgs;
      head = mk (builtins.getFlake \"github:NixOS/nixpkgs/nixos-unstable\");
      ver = pkgs: n:
        let
          r = builtins.tryEval (
            let v = lib.attrByPath (lib.splitString \".\" n) null pkgs;
            in if v == null then \"MISSING\" else (v.version or \"(no version)\")
          );
        in if r.success then r.value else \"THROWS\";
      pad = n: s: s + lib.concatStrings (lib.genList (_: \" \")
        (let d = n - builtins.stringLength s; in if d > 0 then d else 1));
      row = n: \"  \" + (pad 34 n) + (pad 20 (ver locked n)) + (ver head n);
    in lib.concatStringsSep \"\n\" (
      [ (\"  \" + (pad 34 \"ATTR\") + (pad 20 \"LOCKED\") + \"UPSTREAM\") ]
      ++ map row [ $list ]
    )
  " 2>&1 | grep -v "^evaluation warning:"
  echo
  echo
  echo "  A differing UPSTREAM column is what an update would bring in for that"
  echo "  attribute. MISSING upstream on a local derivation means keep it;"
  echo "  present means the local copy may be retirable."
  echo
}

case "${1:-all}" in
  state) cmd_state ;;
  inputs) cmd_inputs ;;
  kludges) cmd_kludges ;;
  warnings) cmd_warnings ;;
  versions)
    shift
    cmd_versions "$@"
    ;;
  all)
    echo "repo: $repo   (the three cheap sections; 'warnings' and 'versions' on demand)"
    echo
    cmd_state
    cmd_inputs
    cmd_kludges
    ;;
  *)
    echo "usage: survey.sh [state|inputs|kludges|warnings|versions <attr>...]"
    exit 2
    ;;
esac
