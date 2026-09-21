# Agent context — what gets loaded, when, and why

**Status: mostly implemented, partly aspiration.** The three tiers, the
routing rules and the `consolidate-memory` skill exist and have been run
once end to end (2026-09-20, twenty memories drained to zero). The fleet
section at the bottom describes a machine layout that does not exist yet.
Everything before it describes this repo as it stands.

This is a reference document, not a procedure. The procedure lives in
`home/skills/consolidate-memory/SKILL.md`.

## The problem

An agent's context is a budget, and every mechanism that puts text into it
spends from the same pot. The mechanisms have wildly different costs and
almost identical appearances, so it is easy to put a rule in the expensive
place by accident and never notice.

Worse, a long instruction file is followed *less* reliably than a short one.
Attention dilutes. So a low-value line does not merely cost its own tokens —
it makes the high-value lines around it quieter. Adding a rule is never free
and is sometimes negative.

## Three tiers

| Tier | Where | Cost | Holds |
|---|---|---|---|
| Always loaded | `~/.claude/CLAUDE.md` (from `home/claude-code.md`), a repo's own `CLAUDE.md` | Paid every session, forever | Standing rules, hazards, non-obvious constraints |
| On demand | `home/skills/*/SKILL.md` | Paid only when invoked | Procedures for occasional, specific work |
| Mutable inbox | `~/.claude/projects/<slug>/memory/` | Paid on recall | Nothing permanently — see below |

The machine-wide file is the expensive one and the important one. It is also
the thing none of the six `CLAUDE.md` files surveyed in `omacom/*` had, and
the reason they carry duplicated rules (see "What we found elsewhere").

**Auto-memory is an inbox, not a record.** It is written at runtime, one
directory per project, and nothing empties it. Left alone it accumulates
rules that go stale, contradict the files that already state them, and — the
expensive failure — quietly duplicate each other across projects, where no
single session can see the duplication. It must be drained on a schedule.
That is what the `consolidate-memory` skill is for.

## What earns a permanent line

Two tests, both cheap to apply and both easy to skip.

**Could this be worked out by reading the code?** If yes, do not write it
down — it will be read, and a second copy only creates something to drift.
The `agents/skills/` tour in `omacom/aether.nvim` fails this test almost
entirely: module-flow diagrams and a "Common Tasks" section that amounts to
*edit the file containing the thing you want to change*. Its sibling
`omacom/aether` passes it almost entirely, and the difference is visible at a
glance.

**Would you be annoyed to have to say this again in three months, in a fresh
session?** If no, it is a transient correction, not a standing rule. Writing
it down costs attention forever to fix something that was already fixed.

A rule that restates a default the agent would follow anyway is worse than
absent: it consumes budget and can cause over-application.

Include the reason. A bare prohibition does not generalise — the agent cannot
tell which neighbouring cases it covers. A reason does.

## Where a rule goes

| True of | Destination | Takes effect |
|---|---|---|
| This machine, every repo | `home/claude-code.md` | next `just switch` |
| One repo | that repo's `CLAUDE.md` | immediately |
| One session | nowhere — say it and move on | — |

Routing is the whole judgment. Compaction alone would have kept every one of
the twenty memories drained in the first run; six of them were deleted purely
because something already said it, better.

## Prose, tooling, or permissions

Three substrates, and picking the wrong one is the most common mistake here.

**Tooling** is strongest: enforced rather than requested, costs no context,
and applies to the human too. Formatting, lint, schema validation and
referential integrity all belong here. `nixfmt` via the `PostToolUse` hook in
`home/claude-code.nix` is the worked example: `just fmt`, `nix fmt` and the
agent cannot disagree about what correct formatting is, because they are the
same binary.

**Permissions** (`permissions.deny` / `allow` / absent) are for actions, not
judgment. They answer *may this command run*, never *should it, here, now*.
`deny` is a hard block with no prompt; `allow` is silent; absent prompts.

The failure mode worth remembering: `git commit` was in `deny` for a while.
That made an explicit "commit this" *fail*, when the actual objection had
always been to the agent volunteering or asking — never to committing when
asked. The wrong substrate turned a nuance into a wall. It now sits in
`allow`, with the nuance where nuance belongs:

> `git commit` **is** yours to run — but only when asked for it in that turn,
> in as many words. Never volunteer it.

**Prose** is for everything a linter cannot express and a permission cannot
capture: hazards, intent, scope, and the reason behind a rule. It is the
weakest substrate — it is advisory, and it is the one that dilutes — so
nothing belongs here that could have gone in the other two.

## What we found elsewhere

Surveyed 2026-09-20: the six `CLAUDE.md` files in `omacom/*` (Omarchy and
siblings). Worth reading `omacom/aether/CLAUDE.md` in full; it is the best of
them.

**Adopted — `CLAUDE.md` as a one-line redirect.** `omacom/omarchy`'s entire
`CLAUDE.md` is `@AGENTS.md`. The content is tool-agnostic; the Claude-specific
file is a one-line adapter. Status: **proposed here, not done.** It matters
more for a fleet than for one laptop, because more than one tool will touch
it.

**Adopted — the always-loaded file is an index, not a document.** Their
`AGENTS.md` opens with seven pointers into `agents/skills/*.md`, one per kind
of task, and the depth is only read when doing that work. We reached the same
split independently with `consolidate-memory`; the difference is mechanism,
not shape. Theirs is plain markdown read on instruction and works in any
agent. Ours loads automatically and does not.

**Adopted — state the anti-drift rule inside the document.** The registry's
version is the best-phrased of the six:

> Mirror Omarchy, don't reinvent: slug derivation, denied-on-install files …
> are copied from `omacom/omarchy` into `packages/schema/src/constants.ts`.
> Change behaviour there, with a test.

It names the upstream, names the local mirror, and says where a change goes.
`modules/caches.nix` ↔ `.nix-config` is exactly this pair and currently says
only "keep in sync by hand". `modules/backup.nix` ↔ `backup-excludes.txt`
already does it properly.

**Adopted — name the tool that enforces the rule.** `state-of-omarchy`:
"referential integrity … is enforced by `pnpm survey:lint`, **not by
hand-checking**." Saying which command settles it converts a request into a
check.

**Not adopted — the durable record outside git.** `omacom/aether` points its
real documentation at `~/Documents/bjarne/projects/Aether`, "deliberately
outside git". That is the inbox/record split with the record unversioned and
unreachable: a dead pointer for every contributor, and a machine-local
absolute path committed to a public repo. The record belongs in the flake.

**Not adopted — inlining a tool's own instructions.** `state-of-omarchy`
pastes the Svelte MCP server's usage docs into its always-loaded file, paid
for every session whether or not any Svelte is written. An MCP server ships
its own instructions; let it.

**The thing they got wrong, twice.** Two sibling repos open with the same
paragraph, ending "Applies to every repo in this project" — the author knew
it was mis-scoped and duplicated it anyway, because there was no shared file
to put it in. The secrets rule is duplicated across the same two repos.
Four duplications in a six-file sample.

That is the argument for the machine-wide file in one observation. A
per-repo-only world cannot dedupe, so it copies.

## What changes when this is a distro

The intent for this repo is a Nix-based meta-distro managing every machine in
the house — laptop, router, the 3D printer in the corner, whatever follows —
most likely on top of [clan.lol](https://clan.lol), which does fleet
inventory, secrets and networking over flakes. **Nothing here has been
evaluated and no fleet exists yet.** What follows is what the context model
above has to grow to survive that, not a plan for building it.

**"Machine-wide" splits into three.** Today there is one machine, so
`home/claude-code.md` can mean both "how this user works" and "how this box
is built". Those separate the moment there is a second host: preferences that
follow the user everywhere, facts about a *class* of host (every headless
one, every one with a GPU), and facts about exactly one box. The routing
table above grows a row; the skill's phase 2 already merges across scopes and
will need to merge across hosts too.

**The blast radius inverts.** A bad `switch` on this laptop is an
inconvenience with a keyboard in front of it. A bad switch on the router
takes out the network *and* the means of fixing it remotely; on the printer it
is a physical-hazard question, not a config question. So the tiering has to
become per-host, and the default has to invert: for any host that is not the
one in front of you, nothing applies without an explicit ask. `just boot`
over `just switch` stops being nvidia-specific advice and becomes the house
default for remote hosts.

**Hazard docs become the main genre.** The most valuable thing in this repo's
`CLAUDE.md` today is the `boot`-versus-`switch` note — a failure that is
invisible, is not warned about, and costs an afternoon. Every device class
will have one or two of those, and they are exactly the content that cannot
be derived from the code. Write them the same way: what breaks, why it is not
obvious, what it costs, and which verb avoids it.

**Memory is keyed by project path, not by host.** A session working on the
router from this checkout files its memories under nix-config's inbox. That
is survivable — routing by scope already handles it, and the drain is global
— but the inbox will stop being a per-project signal and become a single
queue. Worth revisiting once there is a second host, not before.

**The redirect stops being cosmetic.** One laptop with one agent can afford a
Claude-specific file. A fleet will be touched by more than one tool, and
`AGENTS.md` with thin per-tool adapters is the shape that survives that.
This is the strongest argument for doing the omarchy steal, and the reason to
do it before there is a second machine rather than after.

## Rules for this document

It describes the shape of the system. It does not restate what
`home/claude-code.md` says, what `SKILL.md` says, or what any module header
comment says — if a rule is stated in one of those, this file points at it
and does not copy it.

If it grows past what someone will read in one sitting, something in it has
stopped earning its place. Cut that rather than adding a summary.
