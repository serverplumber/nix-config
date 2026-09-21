---
name: consolidate-memory
description: Drain per-project auto-memory into the durable CLAUDE.md files — strip what the machine-wide rules already say, merge the same rule filed under many repos into one, route the residue, delete the rest. Runs across every project at once. Use when memory has piled up, when the same correction keeps recurring, or on request ("consolidate memory", "tidy your memory", "what have you remembered").
---

# Consolidate memory

Instructions to yourself. Read all of them before touching anything.

Auto-memory (`~/.claude/projects/<slug>/memory/`) is a mutable inbox: written at
runtime, one directory per project, never emptied. The `CLAUDE.md` files are the
durable record — version-controlled, reviewable in a diff, loaded every session.
This is the drain between them.

Two destinations:

| Scope | File | Takes effect |
|---|---|---|
| True on this machine, every repo | `~/code/nix-config/home/claude-code.md` | next `just switch` |
| True of one repo | that repo's `CLAUDE.md` | immediately |

Everything else is deleted, not filed.

## Run across every project, always

Not the current one. All of them, every time.

The duplication worth removing is mostly *between* projects, and is invisible
from inside any one of them. Several repos here independently filed their own
copy of the same git rules. One project at a time, you would delete krump's copy
as redundant on Monday and promote charpy's near-identical copy as if it were
new on Tuesday — two edits to the same file that should have been one merged
rule, with no vantage point from which to notice.

Load everything first. Never decide from partial state.

## Phase 0 — load

```
bash ~/.claude/skills/consolidate-memory/discover.sh
```

One call: every memory file on the machine, plus the machine-wide rules they get
measured against. Around 40KB. Do not read memory files individually — that is
the failure this skill exists to prevent. `--brief` gives paths only; use it for
a quick count, never as the basis for a decision.

The dump is large enough that the harness will usually persist it to a file
rather than inline it. Read that file — in slices if need be. Do not fall back
to opening memory files one at a time.

If it prints a **DRIFT** warning, stop. Source and live differ, so the rules you
would dedupe against are not the ones in force. Say so and ask before going on.

Project `CLAUDE.md` files are listed but not dumped. Read the one you need in
phase 3, once something has actually survived that far.

## Phase 1 — strip what the machine-wide file already says

Mechanical, cheapest, largest reduction. Do this before thinking about scope at
all: it shrinks the problem, and what survives is the part that needs judgment.

For every memory in every project: is this rule already in
`home/claude-code.md`? If yes → delete.

**Absorb before deleting.** Clause by clause, confirm the destination carries
every specific the memory holds. A memory deleted as "duplicated" routinely
contains one detail the destination lacks, and it vanishes silently. If it holds
a missing specific, the destination gains that clause *first*, then the memory
goes.

## Two gates before anything is promoted

Apply to every survivor, in phases 2 and 3 alike.

**Is it still true?** Anything naming a file, option, function or flag gets
checked against the tree now. Memories record what was true when written. Stale
and confident is worse than absent — correct it or delete it.

**Does it earn a permanent line?** A `CLAUDE.md` line costs attention in every
future session, and a long file is followed less reliably than a short one. If
it restates a default, or records a one-off slip already corrected, delete it.
The bar: would the user be annoyed to have to say this again in three months, in
a fresh session?

## Phase 2 — cluster the survivors across projects

Now compare what is left against itself, project to project.

N projects saying the same thing is **one machine-wide rule, not N project
rules**. Merge them into a single proposed clause for `home/claude-code.md`,
cite all N sources, and delete all N memories.

Near-duplicates matter more than exact ones. The same instruction phrased three
different ways in three repos is the strongest available evidence that it is a
standing preference rather than a local detail — treat divergent phrasings as
one rule to be stated once, properly, not as three separate findings.

## Phase 3 — route the residue

What survives phases 1 and 2 is genuinely specific to its project. It goes in
that repo's `CLAUDE.md`, or it goes away.

**Ask about destinations here, not earlier.** Only now is it known which
projects still hold anything needing a home — a project whose memory was wholly
consumed by phases 1 and 2 needs no `CLAUDE.md` and no question. For each
project with residue and no `CLAUDE.md`, ask:

- **Create it, and stage it** — write it, then `git add` so it lands in the next
  commit. Staging only; committing is never yours.
- **Create it, ignored locally** — write it and append to `.git/info/exclude`,
  so it exists for the user and git never sees it. `.git/info/exclude`, never
  `.gitignore`: the ignore is local and must not become part of the repo.
- **Create it, leave it alone** — neither staged nor ignored.
- **No CLAUDE.md here** — promotion is off for that project; its residue can
  only be kept as memory or deleted.

Where a project has more than one `CLAUDE.md`, ask which receives the
promotion rather than assuming the root — a repo may deliberately keep its only
one in a subdirectory.

## Phase 4 — propose once, globally

One proposal covering every project. Before writing anything:

- the **diff** for each destination file, machine-wide first;
- the **delete list**, each with a one-line reason — `already in
  claude-code.md:NN`, `merged into <clause> with krump, charpy`, `stale — <flag>
  gone`, `restates a default`;
- what is **left alone**, and why.

Then stop. Nothing in phase 5 happens without an explicit yes.

## Phase 5 — apply, per destination

Global analysis, staged application: confirm once per destination file, not once
for the whole sweep. Order matters.

1. Write the destination file(s).
2. Stage or locally-exclude each newly created `CLAUDE.md`, per phase 3.
3. Rewrite each `MEMORY.md` so its pointers match what survives. An empty inbox
   means an empty `MEMORY.md`, not a stale index.
4. **Delete memory files last** — never before their content is in a
   destination, or the rule briefly exists nowhere.

### The drain/switch gap is expected

A machine-wide promotion only reaches `~/.claude/CLAUDE.md` at the next
rebuild, so between applying and switching those rules live in neither place.
This is a known and accepted property of the design, not a problem to solve and
not a question to re-ask each run: **always drain completely**, then close the
run by reminding the user that `just switch` is what makes the promotions live.
Don't offer to run it, and don't hold deletions back waiting for it.

A newly written `CLAUDE.md` will likewise not have been exercised in a real
session yet. Also expected, also accepted. Mention it once at most; don't hedge.

### Leave the other repos dirty on purpose

A `CLAUDE.md` written into another project stays uncommitted. The user picks it
up the next time they work in that repo, and its dirty status is the reminder
that something landed there — committing it from here would remove exactly that
signal. Only the nix-config side is ever a commit candidate, and only if asked.

## Improve this skill as you use it

The skill is sourced from `~/code/nix-config/home/skills/consolidate-memory/`
and installed from there, so it is editable — and editing it is part of running
it, not a separate task.

When a run turns up something the skill should already have known — a tool that
behaves differently than assumed, a destination shape not anticipated, a class
of memory the phases route badly, a step that plainly needed doing and was not
written down — fold it back in before finishing:

- a mechanical fact or a footgun goes in `discover.sh`'s header comment;
- anything touching the order or the judgment goes in the phases above.

Report what changed and why, with the rest of the run. The edit lands in that
repo's working tree like any other change and only reaches `~/.claude/skills/`
at the next rebuild — so the run that learns a lesson is never the run that
benefits from it. Write it down anyway.

Keep additions short. This file competes for attention with everything else
loaded into a session, and the same rule applies to it as to any `CLAUDE.md`: a
lesson worth adding is worth stating in two lines. If it is growing, something
in it has stopped earning its place — cut that instead.

## Hard rules

- **Never commit, push or checkout.** `git add` is the furthest this goes, and
  only where that option was chosen. Denied at the harness level anyway.
- **Never rebuild.** Report that a machine-wide promotion needs `just switch`;
  do not offer to run it.
- **Never edit a `CLAUDE.md` unasked.** Propose the diff, get a yes, then write.
- **Promoting machine-wide edits a different repo.** Run from anywhere else, a
  machine-wide rule still means editing `~/code/nix-config`. Name the repo you
  are about to touch, and leave the change in its working tree.
- **Orphaned memory** (project directory moved or gone) is reported, never
  deleted on your own initiative — the directory may simply be elsewhere.
