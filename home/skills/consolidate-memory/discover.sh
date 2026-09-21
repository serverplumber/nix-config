#!/usr/bin/env bash
# Load state for the consolidate-memory skill: every auto-memory file on the
# machine, in one call, plus the machine-wide rules they are measured against.
#
# Dumps contents by default rather than listing paths, because the whole point
# of the skill is comparing memories against each other. The duplication worth
# removing is mostly cross-project — the same rule filed separately under four
# repos — and that is invisible when the files are read one at a time. Twenty
# memory files is well under 30KB; read them together or the comparison cannot
# happen. Use --brief for a paths-only overview.
#
# Pure discovery. Reads, counts and pairs; never writes, moves or deletes.
#
# The pairing only ever runs FORWARDS — project path to slug. Claude Code names
# a project's state directory after its absolute path with both "/" and "_"
# replaced by "-", which is lossy: "-home-stablefly-code-opensauce-dirt" is
# opensauce_dirt here, but could equally have been a directory literally named
# opensauce-dirt, and ~/code holds opensauce, opensauce_dirt and
# opensaucechickenesc side by side. Never parse a slug back into a path; mangle
# each candidate directory and look the result up instead.
#
# Related footgun: every slug begins with "-", so anything handed a slug as a
# RELATIVE path reads it as a flag. Always build absolute paths from $projects.
# `cd ~/.claude/projects && find <slug>/memory ...` fails outright here, since
# find is bfs and rejects it rather than doing something surprising — but the
# same shape with a tool that guesses would be worse.
#
# Dependencies are coreutils and findutils only, on purpose — this ships as a
# plain file in the skill directory rather than a wrapped derivation, so it must
# not reach for anything that might be absent (there is no python3 here).

set -uo pipefail

brief=0
root="$HOME/code"
for arg in "$@"; do
  case "$arg" in
    --brief) brief=1 ;;
    *) root="$arg" ;;
  esac
done

projects="$HOME/.claude/projects"
machine_src="$root/nix-config/home/claude-code.md"
machine_live="$HOME/.claude/CLAUDE.md"

if [ ! -d "$projects" ]; then
  echo "no project state directory at $projects — nothing to consolidate"
  exit 0
fi

rule() { printf '════════════════════════════════════════════════════════════\n'; }

# ── The file everything is measured against ─────────────────────────────────
rule
echo "MACHINE-WIDE RULES"
rule
if [ -f "$machine_src" ]; then
  echo "source: $machine_src   (edit target)"
  echo "live:   $machine_live  (what sessions actually load)"
  if [ -f "$machine_live" ] && ! diff -q "$machine_src" "$machine_live" >/dev/null 2>&1; then
    echo
    echo "!! DRIFT: source and live differ — there are unapplied changes."
    echo "!! Deduping against the source would measure memories against rules"
    echo "!! that are not in force yet. Say so before going further."
  fi
  if [ "$brief" -eq 0 ]; then
    echo
    sed 's/^/  | /' "$machine_src"
  fi
else
  echo "!! no machine-wide file at $machine_src — nothing to promote into"
fi
echo

# ── Every project with a non-empty inbox ────────────────────────────────────
matched=""
total=0
projects_with=0

for dir in "$root"/*/; do
  [ -d "$dir" ] || continue
  dir="${dir%/}"
  slug="$(printf '%s' "$dir" | tr '/_' '--')"
  mem="$projects/$slug/memory"
  [ -d "$mem" ] || continue
  matched="$matched $slug "

  files=""
  count=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    count=$((count + 1))
    files="$files$f
"
  done < <(find "$mem" -maxdepth 1 -name '*.md' ! -name 'MEMORY.md' 2>/dev/null | sort)
  [ "$count" -gt 0 ] || continue

  total=$((total + count))
  projects_with=$((projects_with + 1))

  rule
  echo "PROJECT  $dir"
  echo "slug     $slug"
  echo "memory   $mem  ($count files)"

  # Destinations are listed, not dumped: a project CLAUDE.md can be large and
  # is only needed once a memory has actually survived to phase 3. Read the
  # one you need then.
  dests=0
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    dests=$((dests + 1))
    echo "dest     $c  ($(wc -c <"$c" | tr -d ' ') bytes, not dumped — read on demand)"
  done < <(find "$dir" -name 'CLAUDE.md' -not -path '*/.git/*' 2>/dev/null | sort)
  [ "$dests" -gt 0 ] || echo "dest     NONE — ask before creating one"

  if [ -s "$mem/MEMORY.md" ]; then
    echo "index    MEMORY.md, $(grep -c . "$mem/MEMORY.md" 2>/dev/null) non-blank lines"
  else
    echo "index    MEMORY.md empty or absent (pointers may be out of sync)"
  fi
  rule

  if [ "$brief" -eq 0 ]; then
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      echo
      echo "──── ${f##*/} ────"
      cat "$f"
    done <<<"$files"
  else
    printf '%s' "$files" | sed 's|^|  |'
  fi
  echo
done

# ── Memory left behind by a project that moved or went away ─────────────────
rule
echo "ORPHANED MEMORY (no directory under $root mangles to this slug)"
rule
orphans=0
while IFS= read -r m; do
  [ -n "$m" ] || continue
  s="$(basename "$(dirname "$m")")"
  case "$matched" in
    *" $s "*) continue ;;
  esac
  n=$(find "$m" -maxdepth 1 -name '*.md' ! -name 'MEMORY.md' 2>/dev/null | wc -l | tr -d ' ')
  [ "$n" -gt 0 ] || continue
  orphans=$((orphans + 1))
  echo "  $s — $n memories — $m"
done < <(find "$projects" -maxdepth 2 -name memory -type d 2>/dev/null | sort)
[ "$orphans" -gt 0 ] || echo "  none"
echo
echo "TOTAL: $total memories across $projects_with projects, $orphans orphaned"
