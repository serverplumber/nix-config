#!/usr/bin/env bash
#
# sdbackup — offsite backup to an SD card you carry.
#
# The card is the whole point: cheap, pocketable, goes through an airport
# without comment, and can be destroyed in a second. The backup has to fit in
# a work break, so everything here is shaped around "start it, walk away, come
# back to a card that is safe to pull".
#
# Written as bash deliberately. It may become a single binary later; until
# then the constraints that matter for that port are honoured here — exit
# codes are the public interface, all mutable state lives in one JSON file,
# and there are no associative arrays or other bashisms that don't map to Go.
#
# Nothing in here is fancy. The judgement is in *what* it refuses to do:
# it will not write to an unrecognised card, it will not start a run that
# cannot finish inside the break budget, and it will not tell you the card is
# safe to remove until the data is actually on it.

set -euo pipefail

# --- exit codes: the public interface ----------------------------------------
# Kept stable across the eventual rewrite. The callers that matter (the lock
# hook, and a human in a terminal) branch on these, not on stderr text.
readonly EX_OK=0
readonly EX_NO_CARD=10       # no enrolled card is mounted
readonly EX_BAD_MARKER=11    # a card is mounted, but it isn't one of ours
readonly EX_NOT_DUE=12       # nothing to do yet
readonly EX_BUSY=20          # another sdbackup run holds the lock
readonly EX_FAILED=30        # the backup itself failed
readonly EX_INTERRUPTED=40   # card pulled, or we were killed, mid-run

# --- configuration -----------------------------------------------------------
# Every value is overridable by environment so the Nix module owns the policy
# and this script owns the mechanism. Defaults here are only for running it by
# hand outside the module.
: "${SDBACKUP_SOURCE:=$HOME}"
: "${SDBACKUP_EXCLUDES:=}"
: "${SDBACKUP_BUDGET_MINUTES:=20}"
: "${SDBACKUP_DUE_DAYS:=7}"
: "${SDBACKUP_PASSWORD_FILE:=$HOME/.config/restic/password}"
: "${SDBACKUP_STATE_DIR:=${XDG_STATE_HOME:-$HOME/.local/state}/sdbackup}"
# Where automounted removable media shows up. A list, because nothing in this
# config declares an automounter yet and the eventual answer may not be the
# /run/media/<user>/<label> that Bluefin used to give us. Overridable so the
# card-detection path can be exercised without a real card in a real slot.
: "${SDBACKUP_SEARCH_PATHS:=/run/media /media /mnt}"

readonly MARKER_NAME="sdbackup.card.json"
readonly REPO_SUBDIR="restic"
readonly STATE_FILE="$SDBACKUP_STATE_DIR/state.json"
readonly RUN_LOCK="$SDBACKUP_STATE_DIR/run.lock"

# Assumed throughput for the very first run, before we have measured anything.
# 20 MB/s is a pessimistic cheap-card figure on purpose: the failure we care
# about is promising a 10-minute run that takes 40, not the reverse.
readonly DEFAULT_BYTES_PER_SEC=20000000

# --- output ------------------------------------------------------------------

log()  { printf '==> %s\n' "$*" >&2; }
warn() { printf 'warning: %s\n' "$*" >&2; }
# die <message> [exit_code] — note "$1", not "$*": the code must not print.
die()  { printf 'error: %s\n' "$1" >&2; exit "${2:-1}"; }

# Desktop notification. Never fatal: a missing notification daemon must not
# take down a backup that is otherwise fine.
notify() {
  local urgency="$1" title="$2" body="${3:-}"
  notify-send --app-name=sdbackup --urgency="$urgency" "$title" "$body" 2>/dev/null || true
}

human_bytes() { numfmt --to=iec --suffix=B "${1:-0}" 2>/dev/null || echo "${1:-0}B"; }

human_duration() {
  local s="${1:-0}"
  if [ "$s" -lt 60 ]; then printf '%ds' "$s"
  else printf '%dm%02ds' "$((s / 60))" "$((s % 60))"
  fi
}

# --- state -------------------------------------------------------------------
# One file, one shape. Per-card entries keyed by card id:
#   { "cards": { "01": { "last_run": <epoch>, "bytes": N, "seconds": N } } }

state_init() {
  mkdir -p "$SDBACKUP_STATE_DIR"
  [ -f "$STATE_FILE" ] || echo '{"cards":{}}' > "$STATE_FILE"
}

state_get() {  # state_get <card_id> <field> [default]
  state_init
  local v
  v="$(jq -r --arg c "$1" --arg f "$2" '.cards[$c][$f] // empty' "$STATE_FILE")"
  [ -n "$v" ] && echo "$v" || echo "${3:-}"
}

state_record() {  # state_record <card_id> <bytes> <seconds>
  state_init
  local tmp
  tmp="$(mktemp "$SDBACKUP_STATE_DIR/.state.XXXXXX")"
  jq --arg c "$1" --argjson b "$2" --argjson s "$3" --argjson t "$(date +%s)" \
     '.cards[$c] = {last_run: $t, bytes: $b, seconds: $s}' \
     "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

# Measured throughput for this card, falling back to the pessimistic default
# until a run has actually completed. This is why the ETA is worth trusting:
# it is this card's own history, not a number from a spec sheet.
throughput_for() {  # throughput_for <card_id>
  local bytes secs
  bytes="$(state_get "$1" bytes 0)"
  secs="$(state_get "$1" seconds 0)"
  if [ "${bytes:-0}" -gt 0 ] && [ "${secs:-0}" -gt 0 ]; then
    echo $(( bytes / secs ))
  else
    echo "$DEFAULT_BYTES_PER_SEC"
  fi
}

# --- rustic ------------------------------------------------------------------

rustic_at() {  # rustic_at <mountpoint> <args...>
  local mnt="$1"; shift
  rustic --repository "$mnt/$REPO_SUBDIR" --password-file "$SDBACKUP_PASSWORD_FILE" "$@"
}

# The repository's own id, used to prove a marker belongs to this repo rather
# than having been copied onto some other card.
repo_id_at() {
  rustic_at "$1" cat config 2>/dev/null | jq -r '.id // empty' 2>/dev/null || true
}

# --- cards -------------------------------------------------------------------

# Enumerate every mounted volume that carries our marker. Deliberately
# discovered by scanning for the marker rather than by device path:
# /dev/mmcblk0p1 is not stable, and the whole identity story here is "the card
# says who it is", not "it appeared at the address I remembered".
#
# Two glob depths because automounters disagree: udisks2 gives
# /run/media/<user>/<label>, others give /media/<label>.
find_card_mounts() {
  local root d
  for root in $SDBACKUP_SEARCH_PATHS; do
    [ -d "$root" ] || continue
    for d in "$root"/*/ "$root"/*/*/; do
      [ -f "$d$MARKER_NAME" ] && printf '%s\n' "${d%/}"
    done
  done 2>/dev/null | sort -u
}

marker_field() { jq -r --arg f "$2" '.[$f] // empty' "$1/$MARKER_NAME" 2>/dev/null || true; }

# A card is ours if the marker parses AND the repo id it claims matches the
# repo actually sitting next to it. That second half is what makes this more
# than decoration — a marker copied onto a different card fails it.
card_is_valid() {  # card_is_valid <mountpoint>
  local mnt="$1" claimed actual
  claimed="$(marker_field "$mnt" repo_id)"
  [ -n "$claimed" ] || return 1
  [ -d "$mnt/$REPO_SUBDIR" ] || return 1
  actual="$(repo_id_at "$mnt")"
  # An unreadable repo id means a wrong password or a damaged repo, not a
  # forged card. Refuse either way, but say which.
  if [ -z "$actual" ]; then
    warn "$mnt: repository did not open (wrong password file, or damaged)"
    return 1
  fi
  [ "$claimed" = "$actual" ]
}

# Resolve the card to act on: an explicit id if given, otherwise whichever
# valid card is mounted. Prints exactly one line, "<mount>\t<id>\t<ok|invalid>".
# Returns 1 only when no card carrying a marker is mounted at all — "a card is
# here but it isn't ours" is a different answer from "no card", and the caller
# needs to tell them apart to raise the right notification.
#
# A valid card always wins over an invalid one, so a stray SD card sitting in a
# second slot can't mask the real one.
resolve_card() {  # resolve_card [wanted_id]
  local wanted="${1:-}" mnt id fallback=""
  while read -r mnt; do
    [ -n "$mnt" ] || continue
    id="$(marker_field "$mnt" card_id)"
    if [ -n "$wanted" ] && [ "$wanted" != "$id" ]; then continue; fi
    if card_is_valid "$mnt"; then
      printf '%s\t%s\tok\n' "$mnt" "$id"
      return 0
    fi
    [ -n "$fallback" ] || fallback="$(printf '%s\t%s\tinvalid' "$mnt" "${id:-?}")"
  done < <(find_card_mounts)
  [ -n "$fallback" ] && { printf '%s\n' "$fallback"; return 0; }
  return 1
}

# --- subcommands -------------------------------------------------------------

cmd_enroll() {
  local mnt="${1:-}" card_id="${2:-}"
  [ -n "$mnt" ] || die "usage: sdbackup enroll <mountpoint> [card-id]"
  [ -d "$mnt" ] || die "$mnt is not mounted"
  [ -f "$SDBACKUP_PASSWORD_FILE" ] || die \
    "no password file at $SDBACKUP_PASSWORD_FILE

Create one, and STORE IT SOMEWHERE ELSE TOO — lose it and the repository is
unrecoverable by design:

  mkdir -p $(dirname "$SDBACKUP_PASSWORD_FILE")
  head -c 32 /dev/urandom | base64 > $SDBACKUP_PASSWORD_FILE
  chmod 600 $SDBACKUP_PASSWORD_FILE"

  if [ -f "$mnt/$MARKER_NAME" ]; then
    die "$mnt is already enrolled as card '$(marker_field "$mnt" card_id)'"
  fi

  # Pick the next free two-digit id if one wasn't given.
  if [ -z "$card_id" ]; then
    state_init
    card_id="$(jq -r '[.cards | keys[] | tonumber] | (max // 0) + 1 | tostring | if length < 2 then "0" + . else . end' "$STATE_FILE")"
  fi

  if [ ! -d "$mnt/$REPO_SUBDIR" ]; then
    log "initialising repository at $mnt/$REPO_SUBDIR"
    rustic_at "$mnt" init
  else
    log "reusing existing repository at $mnt/$REPO_SUBDIR"
  fi

  local rid
  rid="$(repo_id_at "$mnt")"
  [ -n "$rid" ] || die "could not read repository id after init"

  # `uname -n`, not `hostname`: coreutils is already a runtime input, whereas
  # hostname(1) would drag in another package for no gain.
  jq -n --arg c "$card_id" --arg r "$rid" --arg h "$(uname -n)" \
        --arg l "$(findmnt --raw --noheadings --output LABEL --target "$mnt" 2>/dev/null | head -1)" \
        --argjson t "$(date +%s)" \
        '{card_id:$c, repo_id:$r, label:$l, hostname:$h, created:$t}' \
        > "$mnt/$MARKER_NAME"
  sync

  log "enrolled $mnt as card '$card_id' (repo $rid)"
  log "run 'sdbackup run' to take the first backup"
}

# Describe how long ago an epoch timestamp was, in whole days.
age_of() {  # age_of <epoch|0>
  local last="${1:-0}"
  if [ "$last" -le 0 ]; then echo "never"
  else echo "$(( ( $(date +%s) - last ) / 86400 )) days ago"
  fi
}

cmd_cards() {
  state_init
  local mnt id mounted_ids=""
  printf '%-6s %-9s %-30s %s\n' CARD STATUS MOUNT "LAST BACKUP"

  # Mounted cards first, with live status.
  while read -r mnt; do
    [ -n "$mnt" ] || continue
    id="$(marker_field "$mnt" card_id)"
    id="${id:-?}"
    mounted_ids="$mounted_ids $id"
    if card_is_valid "$mnt"; then
      printf '%-6s %-9s %-30s %s\n' "$id" present "$mnt" "$(age_of "$(state_get "$id" last_run 0)")"
    else
      printf '%-6s %-9s %-30s %s\n' "$id" INVALID "$mnt" -
    fi
  done < <(find_card_mounts)

  # Then cards we know about that aren't in the machine, stalest last. Listed
  # when asked, never nagged about — one card is a perfectly reasonable setup.
  while IFS=$'\t' read -r id last; do
    [ -n "$id" ] || continue
    case " $mounted_ids " in *" $id "*) continue ;; esac
    printf '%-6s %-9s %-30s %s\n' "$id" absent - "$(age_of "$last")"
  done < <(jq -r '.cards | to_entries | sort_by(-.value.last_run)[] | "\(.key)\t\(.value.last_run)"' "$STATE_FILE")
}

# Is a backup due for this card?
is_due() {  # is_due <card_id>
  local last
  last="$(state_get "$1" last_run 0)"
  [ "${last:-0}" -eq 0 ] && return 0
  [ $(( ( $(date +%s) - last ) / 86400 )) -ge "$SDBACKUP_DUE_DAYS" ]
}

cmd_run() {
  local wanted="" force=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --card) wanted="${2:-}"; shift 2 ;;
      --force) force=1; shift ;;
      *) die "unknown option: $1" ;;
    esac
  done

  local resolved mnt card_id status
  if ! resolved="$(resolve_card "$wanted")"; then
    notify normal "Backup card not in the machine" \
      "Insert your SD card to back up. Nothing was written."
    log "no enrolled card mounted"
    exit "$EX_NO_CARD"
  fi
  IFS=$'\t' read -r mnt card_id status <<<"$resolved"
  if [ "$status" != ok ]; then
    notify critical "Unrecognised SD card" \
      "That card is not an enrolled backup card. Nothing was written."
    log "card present at $mnt but marker invalid"
    exit "$EX_BAD_MARKER"
  fi

  if [ "$force" -eq 0 ] && ! is_due "$card_id"; then
    log "card '$card_id' backed up less than $SDBACKUP_DUE_DAYS days ago; not due"
    exit "$EX_NOT_DUE"
  fi

  # Only one run at a time. flock rather than a pidfile so a killed run can
  # never strand the lock.
  state_init
  exec 9>"$RUN_LOCK"
  flock -n 9 || { log "another sdbackup run is in progress"; exit "$EX_BUSY"; }

  # Re-exec under systemd-inhibit so a lid close or the 600s idle-suspend
  # cannot cut the run in half. Belt and braces alongside caffeine: caffeine
  # relies on the compositor honouring an idle inhibitor, whereas swayidle
  # calls `systemctl suspend` directly and only logind can refuse that.
  if [ -z "${SDBACKUP_INHIBITED:-}" ]; then
    log "re-executing under systemd-inhibit"
    local -a reexec=("$0" run --card "$card_id")
    [ "$force" -eq 1 ] && reexec+=(--force)
    SDBACKUP_INHIBITED=1 exec systemd-inhibit \
      --what=sleep:idle:handle-lid-switch \
      --who=sdbackup --why="Offsite backup to SD card in progress" \
      "${reexec[@]}"
  fi

  do_backup "$mnt" "$card_id" "$force"
}

do_backup() {  # do_backup <mountpoint> <card_id> <force>
  local mnt="$1" card_id="$2" force="${3:-0}"

  local -a backup_args=(
    backup "$SDBACKUP_SOURCE"
    --git-ignore
    --exclude-if-present .nobackup
    --one-file-system
  )
  # The exclude list is the repo's single source of truth, shared with
  # `just restic_init` and modules/backup.nix. Never a second copy.
  #
  # --custom-ignorefile, NOT --glob-file. This matters more than it looks:
  # rustic's --glob-file is an ALLOWLIST, where a bare pattern *includes* and
  # only a leading `!` excludes — the inverse of both gitignore and restic's
  # --exclude-file. Handing backup-excludes.txt to --glob-file silently backs
  # up ZERO files and still exits 0. Measured, not guessed.
  # --custom-ignorefile treats the file as a .gitignore, which is exactly the
  # semantics backup-excludes.txt is already written in.
  if [ -n "$SDBACKUP_EXCLUDES" ]; then
    [ -f "$SDBACKUP_EXCLUDES" ] || die "exclude file not found: $SDBACKUP_EXCLUDES"
    backup_args+=(--custom-ignorefile "$SDBACKUP_EXCLUDES")
  else
    warn "no exclude file configured — backing up everything under $SDBACKUP_SOURCE"
  fi

  # Pre-flight: how much is actually going to move, and will it fit in a break?
  # `--json` prints nothing useful on a dry run; `--json-progress` is the one
  # that emits a final summary line, and `data_added_packed` is the figure that
  # matters — bytes actually written to the card, after dedup and compression.
  log "estimating (dry run)…"
  local dry summary bytes files rate eta
  dry="$(rustic_at "$mnt" --dry-run --json-progress "${backup_args[@]}" 2>/dev/null || true)"
  summary="$(printf '%s\n' "$dry" \
    | jq -sc 'map(select(.message_type == "summary")) | last // {}' 2>/dev/null || echo '{}')"
  bytes="$(printf '%s' "$summary" | jq -r '.data_added_packed // .total_bytes_processed // 0' 2>/dev/null || echo 0)"
  files="$(printf '%s' "$summary" | jq -r '.total_files_processed // 0' 2>/dev/null || echo 0)"
  bytes="${bytes%.*}"; bytes="${bytes:-0}"; [ "$bytes" = null ] && bytes=0
  files="${files%.*}"; files="${files:-0}"; [ "$files" = null ] && files=0

  # Backing up zero files is never correct for a home directory, and it is the
  # exact shape of a misconfigured exclude file — which otherwise succeeds
  # silently and leaves you with an empty "backup". Refuse it.
  if [ "$files" -eq 0 ]; then
    notify critical "Backup aborted" "The exclude configuration matched everything. Nothing was written."
    die "dry run matched 0 files — the exclude file is wrong, refusing to write an empty backup
  source:   $SDBACKUP_SOURCE
  excludes: ${SDBACKUP_EXCLUDES:-(none)}" "$EX_FAILED"
  fi
  rate="$(throughput_for "$card_id")"
  eta=$(( bytes / (rate > 0 ? rate : DEFAULT_BYTES_PER_SEC) ))

  log "about $(human_bytes "$bytes") to write; estimated $(human_duration "$eta") at $(human_bytes "$rate")/s"

  if [ "$eta" -gt $(( SDBACKUP_BUDGET_MINUTES * 60 )) ] && [ "$force" -eq 0 ]; then
    notify normal "Backup needs longer than a break" \
      "Estimated $(human_duration "$eta"), budget is ${SDBACKUP_BUDGET_MINUTES}m. Run 'sdbackup run --force' when you have time."
    die "estimated $(human_duration "$eta") exceeds the ${SDBACKUP_BUDGET_MINUTES}m budget; use --force to run anyway" "$EX_FAILED"
  fi

  # From here on the card is being written to. If we die, say so loudly —
  # a card pulled mid-write is the expected failure mode, and on exFAT (no
  # journal) the user needs to know to fsck it rather than assume it's fine.
  local interrupted=1
  # shellcheck disable=SC2329  # invoked via trap
  cleanup() {
    if [ "$interrupted" -eq 1 ]; then
      sync 2>/dev/null || true
      notify critical "Backup interrupted" \
        "The card was removed or the run was killed. Run 'sdbackup verify' before trusting it."
      log "interrupted — run 'sdbackup verify --card $card_id' to check the repository"
    fi
  }
  trap cleanup EXIT
  trap 'exit '"$EX_INTERRUPTED" INT TERM

  notify low "Backup started" "Card $card_id — about $(human_duration "$eta")."
  local t0 t1 elapsed
  t0="$(date +%s)"
  if ! rustic_at "$mnt" "${backup_args[@]}"; then
    interrupted=0
    trap - EXIT
    notify critical "Backup failed" "Card $card_id. Nothing was marked as done."
    exit "$EX_FAILED"
  fi
  t1="$(date +%s)"
  elapsed=$(( t1 - t0 ))
  interrupted=0
  trap - EXIT

  # Flush before claiming success. "Safe to remove" has to mean it.
  log "flushing to card…"
  sync

  state_record "$card_id" "${bytes:-0}" "$(( elapsed > 0 ? elapsed : 1 ))"

  log "done in $(human_duration "$elapsed") — SAFE TO REMOVE card $card_id"
  notify normal "SAFE TO REMOVE" \
    "Backup finished in $(human_duration "$elapsed"). Card $card_id can be pulled."
}

cmd_verify() {
  local wanted="" repair=0 resolved mnt card_id status
  while [ $# -gt 0 ]; do
    case "$1" in
      --card)   wanted="${2:-}"; shift 2 ;;
      --repair) repair=1; shift ;;
      *) die "unknown option: $1" ;;
    esac
  done

  if ! resolved="$(resolve_card "$wanted")"; then
    log "no enrolled card mounted"
    exit "$EX_NO_CARD"
  fi
  IFS=$'\t' read -r mnt card_id status <<<"$resolved"
  if [ "$status" != ok ]; then
    log "card present at $mnt but marker invalid"
    exit "$EX_BAD_MARKER"
  fi

  # rustic has no lock concept, so unlike restic there is nothing to unlock
  # after a yank — what an interrupted run leaves behind is an index that
  # disagrees with the pack files. `repair index` fixes that.
  #
  # It is NOT run automatically, and that is deliberate. Repair rebuilds the
  # index from the packs it can actually read, so on a card with genuinely
  # damaged data it "succeeds" by dropping the reference to the broken pack —
  # check then passes, and the tool reports a healthy backup that has quietly
  # lost data. Measured: corrupting a single pack and auto-repairing turned a
  # correct exit 30 into a lying exit 0. A verifier that repairs its way to a
  # pass is worse than no verifier.
  #
  # --read-data-subset is not usable on its own; rustic requires --read-data
  # alongside it. 5% catches a damaged card without re-reading the whole repo
  # off slow media every time.
  log "checking repository on card $card_id…"
  if [ "$repair" -eq 1 ]; then
    warn "--repair given: rebuilding the index before checking"
    rustic_at "$mnt" repair index || true
  fi
  if ! rustic_at "$mnt" check --read-data --read-data-subset 5%; then
    notify critical "Backup card failed verification" \
      "Card $card_id did not pass check. Do not rely on it."
    die "check FAILED on card $card_id — do not rely on this backup

If the last run was interrupted (card pulled mid-write), a stale index is the
likely cause and is safe to rebuild:

  sdbackup verify --card $card_id --repair

If that still fails, the media itself is damaged rather than merely stale.
exFAT has no journal, so a card yanked mid-write can be genuinely corrupt —
fsck.exfat the card, and re-enroll a fresh one if it does not come back." "$EX_FAILED"
  fi

  # A check that passes still does not prove the data comes back, and that is
  # the failure this whole tool exists to prevent. So pull one real file out of
  # the snapshot and compare it byte for byte.
  #
  # `ls --long` is what makes this honest: its first column is the mode, so we
  # can insist on a regular file with a non-zero size. Picking blindly off
  # plain `ls` selects a directory, which "restores" successfully and proves
  # nothing whatsoever.
  log "spot-restoring one file to prove it actually restores…"
  local probe_line probe want_size got_size
  probe_line="$(rustic_at "$mnt" ls latest --long 2>/dev/null \
    | awk '$1 ~ /^-/ && $4 > 0 { print; exit }' || true)"

  if [ -z "$probe_line" ]; then
    warn "no regular file in the latest snapshot to spot-restore; check passed but restore is UNPROVEN"
  else
    probe="$(printf '%s' "$probe_line" | sed -n 's/.*"\(.*\)".*/\1/p')"
    want_size="$(printf '%s' "$probe_line" | awk '{print $4}')"
    got_size="$(rustic_at "$mnt" dump "latest:$probe" 2>/dev/null | wc -c)"

    if [ "$got_size" != "$want_size" ]; then
      die "spot restore of '$probe' returned $got_size bytes, expected $want_size — this repository is NOT a backup" "$EX_FAILED"
    fi

    # If the file is still on disk, compare content too — size alone can match
    # while the bytes are wrong.
    if [ -r "/$probe" ]; then
      local a b
      a="$(rustic_at "$mnt" dump "latest:$probe" 2>/dev/null | sha256sum | cut -d' ' -f1)"
      b="$(sha256sum < "/$probe" | cut -d' ' -f1)"
      [ "$a" = "$b" ] || die "spot restore of '$probe' does not match the file on disk — this repository is NOT a backup" "$EX_FAILED"
      log "restored '$probe' ($want_size bytes) — content matches the live file"
    else
      log "restored '$probe' ($want_size bytes) — size matches (file no longer on disk to compare)"
    fi
  fi

  log "card $card_id verified"
}

# Fired from the lock binds. The screen is already locked by the time this
# runs — the compositor bind locks first and unconditionally, because backup
# logic must never be able to stop the screen from locking.
cmd_on_lock() {
  local do_backup_too=0
  [ "${1:-}" = "--backup" ] && do_backup_too=1

  local resolved mnt card_id status
  if ! resolved="$(resolve_card "")"; then
    # No card. If a backup is overdue, this is the reminder — the marker check
    # failing IS the "you forgot the card" trigger, not just a refusal.
    state_init
    local stalest
    stalest="$(jq -r --argjson d "$SDBACKUP_DUE_DAYS" --argjson now "$(date +%s)" \
      '[.cards | to_entries[] | select((($now - .value.last_run) / 86400) >= $d)] | length' \
      "$STATE_FILE" 2>/dev/null || echo 0)"
    if [ "${stalest:-0}" -gt 0 ] || [ "$do_backup_too" -eq 1 ]; then
      notify normal "Backup card not in the machine" \
        "An offsite backup is due. Insert your SD card and press Mod+B."
    fi
    exit "$EX_NO_CARD"
  fi
  IFS=$'\t' read -r mnt card_id status <<<"$resolved"
  if [ "$status" != ok ]; then
    notify critical "Unrecognised SD card" \
      "The card in the machine is not an enrolled backup card."
    log "card present at $mnt but marker invalid"
    exit "$EX_BAD_MARKER"
  fi

  if [ "$do_backup_too" -eq 1 ]; then
    cmd_run --card "$card_id" --force
  elif is_due "$card_id"; then
    notify normal "Backup is due" "Card $card_id is in the machine. Press Mod+B to back up."
  fi
}

usage() {
  cat >&2 <<'EOF'
sdbackup — offsite backup to an SD card you carry

  sdbackup enroll <mountpoint> [card-id]   prepare a card and register it
  sdbackup cards                           list known cards, stalest last
  sdbackup run [--card ID] [--force]       back up to the inserted card
  sdbackup verify [--card ID] [--repair]   check the repo AND spot-restore
  sdbackup on-lock [--backup]              lock-hook: remind, or remind+run

exit codes: 0 ok · 10 no card · 11 bad marker · 12 not due · 20 busy
            30 failed · 40 interrupted
EOF
  exit 64
}

main() {
  [ $# -gt 0 ] || usage
  local sub="$1"; shift
  case "$sub" in
    enroll)  cmd_enroll  "$@" ;;
    cards)   cmd_cards   "$@" ;;
    run)     cmd_run     "$@" ;;
    verify)  cmd_verify  "$@" ;;
    on-lock) cmd_on_lock "$@" ;;
    -h|--help|help) usage ;;
    *) die "unknown subcommand: $sub" ;;
  esac
  exit "$EX_OK"
}

main "$@"
