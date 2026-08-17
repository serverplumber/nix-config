# SD-card offsite backup — `modules/sdbackup.nix`

## Context

On 2026-08-16 an accidental `rm -rf $HOME` turned this from a nice-to-have
into the thing that matters. `backup-excludes.txt` was rewritten the same day
(still uncommitted) because the old "never" section had blanket-excluded
`Downloads`, `.local`, `.ollama`, `.tabby` and `.var` — so months of unfiled
invoices and hours of JetBrains Local History had no copy anywhere.

There is still no working offsite backup. `modules/backup.nix` targets
`sftp:CHANGEME`, so its daily timer fails every day. Two items in
`bluefin-to-nixos-migration.md` are blocked on this landing: "irreplaceable
data exists off this disk" (line 1444) and deleting the old Bluefin
`root`/`var` subvolumes (line 1514) — the actual point of no return.

**The idea:** the offsite medium is an SD card. Cheap, fast enough, fits in a
wallet or a handful of change, goes through airport security unnoticed, and
can be crushed in a second if it has to be. The backup fits in a work break —
a cold init over lunch, an incremental over a coffee break. The machine
reminds you; it doesn't rely on you remembering.

Nobody ships this. It's a real feature of this OS, and it gets its own
module and a place in the closure, not a pile of glue spread across `home/`
and the `justfile`. Bash is fine — "don't write a program to do anything
fancy" — but the thing itself is first-class. If it later refactors into a
single binary daemon, having it in one file is what makes that possible.

**This supersedes `bluefin-to-nixos-migration.md:1399**, which said the tool
should live in a separate repo and that a Nix-native version must not be
built as a substitute. That note should be amended when this lands.

---

## The correction that shaped this

My first draft measured that 11G of the 14G under `~/code` is git-ignored,
found ~4.6G of irreplaceable material inside that ignored set, and concluded
`.gitignore` was an unsafe exclusion authority — then proposed a curated
pattern list and an audit subcommand to work around it.

Wrong problem. That material is only ignored because it's copyrighted source
text that doesn't belong in a git repo. `lecturer/.gitignore` says so itself:

```
# Source texts (copyrighted material, large binaries)
texts/
```

Copyright is an exceptional reason to ignore something and isn't worth any
code. Move the data where it belongs, symlink it back, and `.gitignore`
becomes an honest statement of "regenerable" — at which point reading it is
the obviously correct mechanism.

Verified since: **`rustic` 0.11.3 is in nixpkgs** with `--git-ignore`,
`--no-require-git`, `--custom-ignorefile`, `--exclude-if-present`,
`--glob-file`, and it reads/writes restic-format repos so plain `restic`
stays a fallback reader. **`~/Books` already exists** — 8.4G, organised by
subject (`art`, `CAD`, `Chemistry`, `Electronics`, `essays`, …), so
`lecturer/texts` drops into an existing taxonomy.

Net effect: **`backup-excludes.txt` needs zero new patterns**, no curated
build-name list, no audit subcommand. Every artefact I catalogued —
`_build`, `deps`, `.venv`, `.elixir_ls`, `.dart_tool`, `Pods`, `.libs`,
loose `.o`, `nix-config/vm/*.qcow2` — is already correctly gitignored by its
own repo, so `--git-ignore` gets all of it for free.

---

## Step 1 — Fix the layout (`ln`, not code)

Do this first; it's what makes everything after it simple.

| move | to | size |
|---|---|---|
| `code/lecturer/texts/` | `~/Books/<subject>/` | 374M, 36 files |
| `code/lecturer/working_texts/` | `~/Documents/lecturer_working/` | 4.1G, 315 files |

Symlink each back so `lecturer` keeps working unchanged — both paths are
referenced by tracked code (`justfile`, `CLAUDE.md`, `docs/`).
`working_texts/` has no top-level `.gitignore`; each working directory is
self-ignoring per the comment in `lecturer/.gitignore`, so moving the parent
wholesale is fine.

rustic stores a symlink as a symlink, not its target — so the link costs
nothing and the real bytes are backed up once at their new home. Both
destinations are already inside the `$HOME` path set.

Two leftovers, for decision rather than action:

- **`code/invoice/`** — 946M / ~87k files, of which `invoiceninja/` is 794M
  and 86,968 files (45% of `~/code`'s entire file count on its own), plus
  `data/`, a live MySQL datadir. You've said it's abandoned in favour of the
  ERP you wrote. Deleting it removes the largest file-count item and the only
  database-consistency problem in the set. Nothing here depends on it.
- **`opensauce_dirt/priv/static/uploads/`** — 12M, 5 real uploaded images,
  gitignored. After the two moves this is the only remaining
  ignored-but-irreplaceable thing found. Same treatment keeps the rule clean;
  at 12M it's also small enough to ignore.

---

## Step 2 — `modules/sdbackup.nix`

One module owns the whole feature: the package, the binds for all three
sessions, the supporting packages, and the state layout. One file to read,
one file to delete, one file to port.

```nix
{ config, lib, pkgs, ... }:
let cfg = config.services.sdbackup; in {
  options.services.sdbackup = {
    enable        = mkEnableOption "SD-card offsite backup";
    budgetMinutes = mkOption { default = 20; };   # refuse runs longer than a break
    dueAfterDays  = mkOption { default = 7;  };   # when the reminder starts firing
  };
  config = mkIf cfg.enable {
    environment.systemPackages = [ sdbackup pkgs.rustic pkgs.libnotify pkgs.exfatprogs ];
    home-manager.users.stablefly = { ... };       # binds for niri / Hyprland / Plasma
  };
}
```

**Trade-off, stated plainly:** binds are home-manager territory, so the
module reaches into `home-manager.users.stablefly` rather than letting
`home/niri.nix` own them. That's unusual for this repo, and it's the point —
keeping the feature in one file is what you asked for, and it's what makes
the eventual refactor into a daemon a single-file operation instead of an
archaeology exercise. Imported from `hosts/laptop/default.nix` alongside the
other modules.

**`pkgs/sdbackup.nix`** — `writeShellApplication` wrapping
`pkgs/sdbackup/sdbackup.sh`, with `runtimeInputs = [ rustic libnotify
util-linux systemd ]`. The script stays a real, separately-editable file
rather than a Nix string, so it's readable, and the port later reads one file
instead of unpicking a derivation.

Subcommands: `enroll` · `cards` · `run` · `verify` · `on-lock`

### Backup invocation

```
rustic -r <card>/restic backup $HOME \
  --git-ignore \
  --custom-ignorefile backup-excludes.txt \
  --exclude-if-present .nobackup \
  --one-file-system
```

`--git-ignore` handles everything inside a git repo, tracking each project's
own build layout as it changes. `backup-excludes.txt` stays the single source
of truth (CLAUDE.md:75) for the `$HOME`-wide items no repo knows about
(`.local/share/containers`, named `.cache` subdirs, `.ollama/models`,
`Downloads/iso`), unchanged and still shared with `just restic_init`.
`--no-require-git` is deliberately *not* passed, so outside repos
`backup-excludes.txt` rules alone.

### Card identity

Match on marker file, never device path — `/dev/mmcblk0p1` moves.

```
<mount>/
├── sdbackup.card.json     ← marker
└── restic/                ← repo (matches just restic_init's layout)
```

Marker holds card id, label, created timestamp, hostname, and the
**repository id** (`rustic cat config` → `.id`). Verification: marker parses
*and* its repo id matches the live one — proving the marker belongs to *this*
repo rather than having been copied onto a random card. No signing tool, no
key to manage, and stronger than a static signature file for the case that
matters. Rustic already encrypts the repo; this is identity, not
confidentiality.

**Filesystem: exFAT** (`exfatprogs` 1.4.2). The card must mount on macOS if
this laptop dies — "I'll use what I have to keep working" is the whole point
of an offsite card, and a Linux-only filesystem defeats it. rustic and restic
both run on macOS and the repo format is portable, so the data is genuinely
recoverable there.

The cost is that exFAT has no journal, so a yank mid-write can damage the
filesystem and not just the repo. That's not a reason to switch — it's the
reason the interrupt handling below is load-bearing rather than decorative.
exFAT's lack of POSIX permissions and symlinks is irrelevant here: a rustic
repo is opaque pack files, and pack files are ~4–16MB, so exFAT's weak
small-file behaviour never gets exercised.

### Multiple cards, no nagging

N cards, each an independent repo with its own marker and last-backup
timestamp in `~/.local/state/sdbackup/`. `cards` prints them stalest-first
*when asked*. Nothing ever nags about rotation — one card is a valid setup.

### Interrupt and suspend safety

- `systemd-inhibit --what=sleep:idle:handle-lid-switch` around the run. Belt
  and braces alongside caffeine: caffeine depends on the compositor honouring
  an idle inhibitor, whereas `swayidle` fires `systemctl suspend` directly at
  600s (`home/default.nix:15-38`) and `systemd-inhibit` blocks that for
  certain.
- `trap` on `EXIT`/`INT`/`TERM` → warn loudly (there is no `rustic unlock`;
  see the implementation notes), so a yanked card doesn't
  strand a repo lock.
- `sync`, then an explicit **"SAFE TO REMOVE"** notification. Nothing before
  that point is safe to pull. Doubly true on exFAT.
- Pre-flight ETA from measured throughput: state records bytes and wall time
  per run, `--dry-run` gives bytes for *this* run, ETA is the quotient;
  refuse to start beyond `budgetMinutes` without `--force`. "60 gig in 15
  min" is ~67 MB/s — top of what a cheap card does, and it predates the
  exclude rewrite, so the budget gets checked rather than assumed.

### Exit codes — the interface that survives the port

```
0  ok            12 not due yet        30 backup failed
10 no card       20 repo locked        40 interrupted / card removed
11 bad marker
```

`#!/usr/bin/env bash`, `set -euo pipefail`, all state in one JSON file, no
associative arrays or `${var@Q}`-class bashisms that don't map to Go.

---

## Step 3 — Binds, all three sessions

**`Mod+B+Backspace` is not expressible.** Verified directly against niri
26.04:

```
$ printf 'binds { Mod+B+Backspace { spawn "true"; } }' | niri validate -c /dev/stdin
Error: × invalid keybind  ╰─▶ invalid modifier: B
```

niri's grammar is `<modifiers>+<key>` with exactly one non-modifier key, and
Hyprland's `bind` is `MODS, key, dispatcher` — neither does chords. Hyprland
could fake a two-step sequence with `submap`, but niri has no equivalent, so
that route splits the two sessions apart.

So the backup gets its own key: **`Mod+b`**, verified free against all 120
existing niri binds. A plain letter plus Mod, so it sits on the Preonic top
layer (CLAUDE.md's hard constraint), and `B` for backup is the mnemonic that
survives not using it for a month.

| bind | action |
|---|---|
| `Mod+Backspace` | lock, then (forked) reminder if due and no card |
| `Mod+Alt+Backspace` | lock + caffeine — **unchanged** |
| `Mod+b` | lock + caffeine + backup |

`Mod+Alt+Backspace` keeps meaning exactly what it means today; `Mod+b` is
that same pair with the backup added. `Mod+Shift+Backspace` stays untouched,
reserved for the future QMK Delete.

`on-lock` **locks first, unconditionally**, then forks the check. Backup
logic must never be able to prevent the screen locking.

**Hyprland** (`home/hyprland.nix:102-105`) has no lock bind at all today; it
gets both, via `hl.bind`.

**Plasma** has no plasma-manager input in `flake.nix`, no swayidle, and
noctalia doesn't run there — so its lock is Plasma's own, not `noctalia msg
session lock`. **Assumption:** add `plasma-manager` as a flake input and
declare the pair through `programs.plasma.shortcuts`, locking via `loginctl
lock-session` and using Plasma's own inhibitor in place of caffeine. That
costs one input but keeps all three sessions declarative, which is the
repo's ethos. The fallback, if you'd rather not add the input, is that Plasma
gets the command and the shortcut is set once by hand.

Notification delivery is confirmed, not assumed: `busctl --user list` shows
**noctalia owns `org.freedesktop.Notifications`** (pid 2096), so
`notify-send` reaches it once `libnotify` is in the closure. Under Plasma,
Plasma's own daemon owns the name.

---

## Prerequisites

- **Automounting is assumed already wired** before this goes live. Nothing
  declares `udisks2` or any automount today, and the
  `/run/media/stablefly/<label>` path in `just restic_init` is an inherited
  *Bluefin* assumption. The tool resolves cards by label/UUID + marker, so it
  doesn't care *which* path they land on — but they have to land somewhere.
- **`backup-excludes.txt` must be committed.** It's read via
  `builtins.readFile`, and flake builds see only git-tracked content, so the
  running system still has the old aggressive excludes.

## Files

- **New `modules/sdbackup.nix`** — the whole feature; imported from
  `hosts/laptop/default.nix`.
- **New `pkgs/sdbackup.nix` + `pkgs/sdbackup/sdbackup.sh`**.
- **`flake.nix`** — add `plasma-manager` input (per the assumption above).
- **`backup-excludes.txt`** — content unchanged; commit it.
- **Not touched:** `modules/backup.nix` stays the SFTP placeholder until its
  own rethink.

## Verification

1. `just verify` / `just check`, then `just build`.
2. **Bind merge check** — the module sets niri binds from outside
   `home/niri.nix`; confirm niri-flake merges the attrsets rather than
   conflicting. `just build`, then grep the generated niri config for all
   three of `Mod+Backspace`, `Mod+Alt+Backspace` and `Mod+b` — and check
   `Mod+Alt+Backspace` still reads lock + caffeine only.
3. **Glob-syntax diff** — restic's `--exclude-file` uses `filepath.Match`;
   rustic's `--glob-file` uses gitignore-style globs. Compare
   `rustic backup --dry-run --glob-file` against `restic backup --dry-run
   --exclude-file` and diff the file counts. This is the one place the rustic
   switch could silently change what's backed up.
4. After Step 1: `cd code/lecturer && git status` clean, and its `just`
   recipes still resolve through the symlinks.
5. `just restic_size` once the exclude file is committed — re-baseline before
   sizing a card.
6. `sdbackup enroll` on a real exFAT card. Then press `Mod+Backspace` **with
   no card inserted**: assert the screen locks anyway *and* the reminder
   appears.
7. `Mod+b` end-to-end, timed. Then the test that matters: **pull
   the card mid-run** — assert exit 40, the next `verify` clears the stale
   lock, and the repo still passes `check`. Then `fsck.exfat` the card, since
   exFAT has no journal.
8. **Cross-platform check** — mount the card on a macOS machine and
   `restic -r /Volumes/<label>/restic snapshots`. This is the reason for
   exFAT; it should be tested once rather than assumed.
9. `sdbackup verify` — `rustic check --read-data-subset=5%` *plus a spot
   restore of one known file*. The `rm -rf` is the reason: a backup that
   exits 0 but doesn't restore is exactly the failure already lived through.
   `just restic_check` already says it — "an untested backup is a hope".

## Open items

- **Password file divergence** — this uses `~/.config/restic/password` (runs
  as the user, in the session); `modules/backup.nix:37` uses
  `/etc/restic/password`. Unify when that module gets its rethink.
- **`~/restored_home/`** duplicates all 22 repos, so timings measured today
  are measuring ~2× the repos. Backed up as-is like any other data.

---

# Implementation notes — what the build disproved

Everything above is the plan as approved. Five of its specifics turned out to
be wrong when measured. The code is right; this section records why, so the
same mistakes don't get re-derived from the plan text.

### 1. `--glob-file` is an allowlist. It silently backs up nothing.

The plan said to pass `backup-excludes.txt` to `rustic --glob-file`. Doing
that backs up **zero files and still exits 0**. rustic's glob semantics are
inverted from both gitignore and restic's `--exclude-file`: a bare pattern
*includes*, and only a leading `!` excludes. Proof — a glob file containing
only `**/node_modules`, which matches nothing in the tree, still excluded
everything:

```
baseline (no glob-file)          -> processed 2 files
glob-file with **/node_modules   -> processed 0 files
```

**`--custom-ignorefile` is the correct flag.** It treats the file as a
`.gitignore`, which is the semantics `backup-excludes.txt` is already written
in. Verified against a synthetic home tree: exactly the intended 5 files
survived, including `.cache/JetBrains/*/LocalHistory` (the thing the `rm -rf`
destroyed) while `.cache/huggingface`, `Downloads/iso`, `node_modules`,
`.ollama/models` and `.local/share/containers` all dropped.

`--no-require-git` is not needed; behaviour is identical with and without.

**Guard added as a result:** a dry run matching 0 files now aborts the backup.
Backing up nothing is never correct for a home directory, and it is exactly
what a misconfigured exclude file looks like — otherwise silent.

### 2. rustic has no `unlock`, and auto-`repair` makes `verify` lie.

There is no `rustic unlock` — rustic is lock-free, so a yanked card leaves no
lock to clear. The plan's cleanup trap had nothing to do.

Worse, the plan's "repair index is the fix" is actively dangerous as an
automatic step. `repair index` rebuilds the index from the packs it can read,
so on genuinely damaged media it "succeeds" by dropping the reference to the
broken pack — after which `check` passes. Measured: corrupting one pack turned
a correct exit 30 into a lying exit 0.

So `verify` never repairs on its own. A failed check is reported as a failure;
`--repair` is opt-in for when you know the cause was a pulled card.

### 3. `--read-data-subset` requires `--read-data`.

`rustic check --read-data-subset 5%` alone is a usage error. Correct form is
`check --read-data --read-data-subset 5%`.

### 4. The dry run needs `--json-progress`, not `--json`.

`--json` emits nothing on a dry run, so the ETA silently computed 0 and the
break-budget check was inert. `--json-progress` emits NDJSON ending in a
`summary` line; `data_added_packed` is the figure that matters — bytes
actually written to the card, after dedup and compression.

### 5. Spot-restoring off plain `ls` proves nothing.

`rustic ls` does not mark directories, so "restore the first entry" picked a
*directory*, which restores successfully and verifies nothing. `ls --long`
exposes the mode, so `verify` now insists on a regular file with non-zero
size, and compares both length and sha256 against the live file.

---

## Step 1 (the moves) — done 2026-08-16

```
code/lecturer/texts         -> ~/Books/lecturer                 (374M, 36 files)
code/lecturer/working_texts -> ~/Documents/lecturer_working     (4.1G, 315 files)
```

Same-filesystem renames, so atomic; counts and byte totals verified identical
afterwards. The 8 `working_text` symlinks inside those directories are
lecturer's own (dated 2026-07-26 and 2026-08-16 11:58, i.e. pre-existing) and
each points at a different book, so they are 8 by necessity, not by choice —
they survived the move because they are relative. Only two symlinks were
created here: `texts` and `working_texts`.

This was not cosmetic.

**Before the move**, `~/code/lecturer` with the flags sdbackup uses came to
428 files / 3.8 MiB, while the same tree with nothing ignored came to 792
files / 4.4 GiB. That gap — 364 files, effectively all of the 4.4 GiB — was
scanned books and recorded audio that `--git-ignore` was dropping on the
floor, because they sat inside a git repo behind an ignore rule.

**After the move**, measured 2026-08-17 (all with the real flags unless
stated):

| | files | size |
|---|---|---|
| A. `~/code/lecturer` | 428 | 3.8 MiB |
| B. `~/code/lecturer`, **no ignore rules at all** | 9,868 | 308.3 MiB |
| C. `~/Books/lecturer` + `~/Documents/lecturer_working` | 359 | **4.4 GiB** |
| D. all three at once | **787** | **4.4 GiB** |

B is the row that matters and the one an earlier draft of this table got
wrong. It had reused the pre-move "792 files / 4.4 GiB" figure here, which
implied the books were still reachable from `lecturer/` and merely being
ignored. They are not: with every ignore rule disabled, `lecturer/` now tops
out at 308 MiB — that residue is `.venv` (9,378 files), nothing else. The
4.4 GiB is reachable *only* from `~/Books` and `~/Documents`, which is the
entire point of the move.

D confirms there is no double-counting: 787 = 428 + 359 exactly, and the
total is 4.4 GiB rather than 8.8 GiB. That holds because **rustic stores a
symlink as a symlink and does not follow it** — verified directly by backing
up a directory containing an absolute symlink to a 2 MB tree with no ignore
rules whatsoever, which stored `lrwxrwxrwx … link -> …/real/big` and copied
2 bytes. Worth stating explicitly, because measurement A alone cannot prove
it: `texts` and `working_texts` are in `.gitignore`, so A would look
identical whether rustic was skipping the symlinks or following them.

`lecturer/.gitignore` gained `texts` and `working_texts` **without trailing
slashes** — the entries are symlinks now, and `texts/` matches directories
only, so the old rule left them untracked.

## Still outstanding

- **Automounting is still not wired.** sdbackup finds cards by scanning
  `/run/media`, `/media`, `/mnt` for its marker (`SDBACKUP_SEARCH_PATHS`
  overrides), so it does not care which path they land on — but something has
  to mount them. Nothing in this config does yet.
- **No card has been enrolled.** Everything above is verified against real
  rustic repositories in temp directories, never against physical media.
  Untested on hardware: exFAT behaviour, real throughput (the ETA falls back
  to a pessimistic 20 MB/s until a run completes), and the pull-the-card-
  mid-write case.
- **The macOS cross-platform read is untested** — the entire reason for
  choosing exFAT over ext4.
- **plasma-manager writes more than asked.** Enabling it to declare two
  hotkeys also causes it to write `kuriikwsfilterrc` (web-shortcut defaults)
  and empty sections in `kdeglobals`, `powerdevilrc`, `kcminputrc`,
  `ksmserverrc`, `ksplashrc`. `overrideConfig` is false so nothing else is
  reset, and the values written match Plasma's own defaults, but it is more
  footprint than the feature needs.
- **Password file divergence** — sdbackup uses `~/.config/restic/password`;
  `modules/backup.nix:37` uses `/etc/restic/password`. Unify when that module
  gets its rethink.

### Addendum — keybind notation and chords (2026-08-17)

`Meta+Esc+B` was asked about and does not work, for the same reason
`Mod+B+Backspace` doesn't: niri accepts exactly one non-modifier key, and Esc
is not a modifier. (`Mod+Escape` alone is fine, but it is already bound to
`toggle-keyboard-shortcuts-inhibit` in home/niri.nix:339.)

The bind is written **`Mod+b`**, lowercase, deliberately. Measured against
niri 26.04:

```
Mod+B  +  Mod+b        -> "duplicate keybind"   (same bind; case is ignored)
Mod+B  +  Mod+Shift+b  -> config is valid        (genuinely different binds)
```

So the conventional capital implies a Shift that is never pressed. The
uppercase binds elsewhere in home/niri.nix and home/hyprland.nix are left as
they are — those mirror each compositor's shipped default config bind-for-bind,
which is their stated purpose.

Plasma keeps `Meta+B`: that string is a Qt `QKeySequence`, not an xkb keysym,
and Qt canonicalises it to uppercase on write regardless of what is declared.
