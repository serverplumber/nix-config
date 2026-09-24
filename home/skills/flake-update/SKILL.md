---
name: flake-update
description: Run the update ritual for ~/code/nix-config — triage the messages a rebuild printed, work out what moving the pins would bring in, and re-test every workaround that was only ever waiting on an upstream fix. Use when rebuild/switch output is pasted or mentioned, before or after `just update`, when deciding switch vs boot, or on request ("what would an update bring", "is this workaround still needed", "check the kludges").
---

# Update this machine

Instructions to yourself. Read all of them before touching anything.

Three questions, one ritual, in this order:

1. **What did the last apply say?** A rebuild prints warnings; they are the only
   notice given that something this config writes has been renamed or deprecated.
2. **What would moving the pins bring in?** Which inputs moved, what breaks, and
   whether the apply will be `switch` or `boot` + reboot.
3. **Which workarounds are now unnecessary?** Every kludge here was written
   against a specific upstream defect. An update is the only moment those are
   worth re-testing, and nothing else will ever prompt it.

The order is not cosmetic. (1) can change the config, which changes what (2)
evaluates; (3) is only *decidable* once (2) has said which revs we would land
on. Never do (3) first.

## What is not yours

`just update`, `just switch`, `just boot`, `nixos-rebuild`. Denied at the
harness, and not to be asked about either — the decision of when to move the
pins and when to apply is the user's, and it is not a step in this task.

So this skill never performs the update. It does everything around it: the
triage, the prediction, the audit, the edits to the working tree. It ends by
saying which verb the apply will need and why. Not by offering to run it.

One more, specific to this skill: **never write the working tree's
`flake.lock`.** Anything that needs the new lock to exist gets a copy of the
repo under the scratchpad (`cp -a`, then `nix flake update` *there*). The lock
in `~/code/nix-config` moves when the user runs `just update` and at no other
time.

## Phase 0 — survey

```
bash ~/.claude/skills/flake-update/survey.sh          # state + inputs + kludges
bash ~/.claude/skills/flake-update/survey.sh warnings # ~60s, evaluates the closure
bash ~/.claude/skills/flake-update/survey.sh versions <attr>...
```

Read its header comment once; it records the mechanical facts, including that
`just have` — the recipe CLAUDE.md documents for exactly this — is broken today,
and what to use instead.

Start with the cheap three even when the user has pasted rebuild output. A
reboot already owed, or a unit already failed, reframes everything in the paste.

## Phase 1 — triage the messages

**The paste is the only source of activation lines.** `nixos-rebuild` run by
hand is not journalled, so `setting up /etc`, `restarting the following user
units`, `the following new units were started` and the final store path exist
only in the terminal the user ran it in. If those matter and there is no paste,
ask for it. Never reconstruct them.

**Evaluation warnings regenerate.** `survey.sh warnings` reproduces exactly what
the rebuild printed, without building anything. Use it rather than asking again.

Four buckets, and the bucket decides the action:

**Ours.** A warning naming an attribute or option *this repo writes*. Fix it,
now, in the working tree. Find the site by grepping the **stem**, not the
suggested replacement — the live example: *LibreOffice upstream has changed the
versioning, please use `libreoffice-stable`* is raised by our
`pkgs.libreoffice-fresh` in `home/gui.nix`, and grepping `libreoffice-stable`
finds nothing at all.

Before making the substitution, check both pins with `survey.sh versions
<old> <new>`: a replacement that exists only upstream breaks the build until the
lock moves, so it is an edit to sequence after the bump, not before.

**Not ours.** Raised inside nixpkgs or an input's own module, by something this
config merely depends on. Nothing to do. Do not silence it, do not work around
it — record it in the report as *not ours* so the next run does not spend a
second investigation on it.

**Activation noise.** The unit lines are read for two things only: did anything
*fail*, and did anything restart that must not have. On this machine the ones
that must not are `nvidia-container-toolkit-cdi-generator.service` (see
`modules/nvidia.nix` and the justfile's `boot` comment), the compositor, and
SDDM. `the following new units were started` naming a unit nobody here added
means an input started shipping one — worth a look, not an alarm.

**Reboot owed.** `survey.sh state` answers it. A reboot owed from an *earlier*
switch explains nvidia and kernel symptoms that otherwise look like new damage.

## Phase 2 — what an update would bring

`survey.sh inputs` marks each root input `=` (head equals the pin — nothing to
review, skip it entirely) or `→` (moved).

For a moved input, the range is read differently depending on which one:

- **The small inputs** — `home-manager`, `niri`, `noctalia`, `nixpak`, `sidra`,
  `plasma-manager`, `hyprland`. A few weeks is a readable commit list:
  `mcp__plugin_hm_github__list_commits` with `since` set to the locked date from
  the survey. Read for one class of thing: **options this repo sets being
  renamed, removed, or given new defaults.** That is what actually breaks a
  rebuild here. `home-manager` and `niri` (niri-flake) are the two that do it.
- **nixpkgs.** The range is thousands of commits; never list it. Ask
  package-shaped questions instead — `survey.sh versions <attr>...` prints the
  locked and upstream versions side by side.

Then answer the question the user actually has to act on: **which verb.** It is
decided by `kernel`, `kernel-modules` or `initrd` moving, and `just diff` is
what decides it — but only after the lock has moved, which is the user's step.
Before that, the cheap predictor is:

```
survey.sh versions linuxPackages.kernel linuxPackages.nvidiaPackages.stable
```

Either one moving means the apply is `just boot` + reboot, not `switch`.
(`boot.kernelPackages` is left at the nixpkgs default here — nothing in the repo
sets it, so `linuxPackages.kernel` is the right attribute to read. The nvidia
driver is `boot.kernelPackages.nvidiaPackages.stable`, from `modules/nvidia.nix`.)
Say so in the report: it is the difference between a one-minute apply and a
reboot, and knowing which is coming is most of why anyone asks.

If something can only be answered by actually moving the lock — an assertion, a
mass rebuild, an option that vanished — do it on a **copy** under the
scratchpad, never in the working tree. `nix eval` on the copy's toplevel
`drvPath` answers "does it still evaluate" in about a minute and builds nothing.

## Phase 3 — the kludge audit

`survey.sh kludges` is the inventory: marker words, upstream tickets,
structural overrides, local derivations, and the oldest dated claims. Expect
false positives in the marker-word section; it is a starting list, not a verdict.

**Read the whole comment around every hit.** This repo writes down why a
workaround exists, what was measured, and when — that comment *is* the spec for
the removal test, and usually names the state you would have to reproduce.
Deleting code whose comment you skimmed is how a fix gets re-broken.

Three kinds, three ways to check:

- **Ticket-bearing** (`niri#3384`, `smithay#1143`, `noctalia#4360`): read the
  ticket with `mcp__plugin_hm_github__issue_read` / `pull_request_read`. Closed
  is *not* enough. The fix has to be in the rev we would land on — and for a
  nixpkgs-side fix, merged to master is not the same as being in
  `nixos-unstable`, which lags master by the channel-blocking test run.
- **A measured claim** ("this build fails in the sandbox", "niri exposes no HDR
  config", dated): re-measure it. Do not reason about whether it is still
  plausible — the date on the comment is the previous measurement, and only a
  new measurement supersedes it.
- **Structural** (an `overrideAttrs`, a `mkForce`, a `doInstallCheck = false`, a
  derivation in `pkgs/`): ask what it substitutes for. A local derivation is a
  bet that nixpkgs lacks the package; `survey.sh versions <attr>` settles that
  bet in one call.

### The removal gate

All three, or it stays:

1. the fix is in the pin we will actually be running;
2. the removal is verifiable **here**, from a shell or by a build;
3. the verification actually ran, in this session.

Most kludges here fail (2), and that is the normal outcome, not a failure of the
audit: they cover suspend/resume, the external display on the dGPU, HDR content,
a docked GPU. **You cannot clear those. Do not remove them.** Re-date the
comment instead — `checked 2026-09-24 against niri 26.09: #3384 still open` is a
genuinely valuable line, and it is what stops the next run re-reading the same
ticket from scratch.

Two more limits:

- **A removal never lands before the bump.** Until `flake.lock` in the working
  tree holds the new rev, a removal is a *proposal*, not an edit — the old pin
  is what is running and the kludge is still load-bearing. Check the lock; if it
  has not moved, write the diff into the report and leave the file alone.
- **Clearing one kludge is not a licence to tidy.** In particular the
  duplication between `home/niri.nix` and `home/hyprland.nix` is deliberate
  (one of the two compositors will be dropped; unifying them now is work that
  gets thrown away). Remove the kludge, not its neighbourhood.

And preserve what you delete: the comment being removed holds the reason the
code existed. That goes in the commit message body — what the defect was, what
closed it, what was verified — per this repo's commit convention. Never let a
kludge leave without a record of what it was for.

## Phase 4 — report

One report, four short sections:

- **Messages** — each one, with its bucket and what was done.
- **Inputs** — which moved, what is in the interesting ranges, **and which verb
  the apply will need** with the reason.
- **Kludges** — cleared (with the evidence), left with a re-dated comment (with
  the reason), left untouched.
- **Needs the user** — `just update`, then read what `just diff` prints, then
  `just switch` or `just boot`. State which one is expected. Do not offer to run
  any of them.

Then stop. The working tree stays dirty; that is the handover.

## Improve this skill as you use it

Sourced from `~/code/nix-config/home/skills/flake-update/` and installed from
there, so editing it is part of running it. A mechanical fact or a footgun goes
in `survey.sh`'s header comment; anything touching the order or the judgment
goes in the phases above. Report what changed with the rest of the run.

The edit only reaches `~/.claude/skills/` at the next rebuild, so the run that
learns a lesson is never the run that benefits from it. Write it down anyway.
Keep additions to a couple of lines; if this file is growing, something in it
has stopped earning its place — cut that instead.

## Hard rules

- **Never** `just update`, `just switch`, `just boot`, `nixos-rebuild`,
  `git push`, `git checkout`. Not even as an offer.
- **Never write the working tree's `flake.lock`.** Trials go in the scratchpad.
- **Never remove a kludge you could not verify.** Re-date its comment.
- **Never commit** unless asked for it in that turn; then write the message
  yourself, ending with what was verified and what was not.
- **Never invent activation output.** Ask for the paste.
