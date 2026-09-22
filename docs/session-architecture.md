# Session architecture — what starts what, and why uwsm is not here

**Status: decisions, recorded. One design at the end that is not built.**
Everything in "What we run" and "uwsm" was verified on this machine on
2026-09-22 and describes the system as it stands. The Omarchy material was
read out of `omacom/omarchy` on 2026-09-21 and has not been re-checked
since; treat version-specific details there as of that date. The agent
console section is a sketch — nothing in it has been written or booted.

Companion to `docs/agent-context.md`. That file is about what an agent
*reads*; this one is about how the session and the things inside it get
*started*, including the agent itself.

## What we run

Three sessions, chosen at the greeter (§7a of
`bluefin-to-nixos-migration.md`), and the launch chain differs per session:

| | starts as | session target | apps land in |
|---|---|---|---|
| niri | `niri-session` → `niri.service` | `graphical-session.target` (`BindsTo=`) | the compositor's cgroup, `session.slice` |
| Hyprland | `start-hyprland` | `hyprland-session.target`, started by home-manager's `systemd.enable` | same |
| Plasma | its own systemd startup | its own | its own |

The important line is the third column, and it is the same for both tiling
sessions: **every app you launch is a child of the compositor**, inside one
cgroup. Nothing separates Chromium from the bar from the terminal.

Two facts that follow, both of which surprise people:

- The kernel OOM killer and `systemd-oomd` see one session-sized blob.
  There is no per-app granularity to act on, and no per-app attribution in
  `systemd-cgtop`.
- Killing the compositor kills everything in it. That is usually what you
  want, and it is why the agent console below needs deliberate work to
  escape it.

Terminal: **foot, standalone — not server mode.** `programs.foot.server` is
never set (`home/gui.nix:572`), there is no `foot-server.service`, and every
launch path names the binary directly: `home/niri.nix:151`,
`home/hyprland.nix:316` and `:359`, the `helix-in-foot` wrapper at
`home/gui.nix:626`, `modules/mime.nix:125`. One process per window. This
matters more than it looks — see "Working directory" below.

## uwsm

Omarchy's session chain is SDDM → **uwsm** → Hyprland, and `uwsm app --`
wraps every app launch. This repo deliberately does not use it
(`modules/hyprland.nix:13`). The reasoning is worth writing out properly,
because the module comment compresses it to three lines and one of the
three is weaker than it reads.

### The three things uwsm does

1. **Runs the compositor as a systemd user unit** bound to
   `graphical-session.target`, with proper `graphical-session-pre` ordering
   and clean teardown.
2. **Exports the session environment** into the systemd user manager and
   the dbus activation environment.
3. **Puts each app in its own systemd scope**, via `uwsm app --`.

### We already have the first two

Not by accident — both compositors ship it upstream.

`niri.service` (installed by the niri module, verified 2026-09-22) is a
complete session unit already:

```
BindsTo=graphical-session.target
Before=graphical-session.target
Wants=graphical-session-pre.target
Wants=xdg-desktop-autostart.target
Slice=session.slice
Type=notify
```

Hyprland gets `hyprland-session.target` plus the environment export from
home-manager's `systemd.enable`, left at its default on purpose
(`home/hyprland.nix:87`).

So adopting uwsm would replace two working mechanisms with a third that
does the same job, and the only thing actually gained is (3).

### The one real delta, and what it would cost

Per-app scopes are a genuine feature: `systemd-oomd` kills the runaway app
rather than reaping something in the compositor's lineage, resource limits
become per-app, and `systemd-cgtop` tells the truth.

But scopes only exist for apps launched through the wrapper. Getting full
coverage here means rewriting every spawn in `home/niri.nix`,
`home/hyprland.nix`, `modules/mime.nix` and the `helix-in-foot` wrapper —
**and it still would not cover the launcher**, because noctalia execs
`.desktop` entries itself. Omarchy could adopt uwsm cleanly because they had
already funnelled everything through `bin/omarchy-launch-*`; we would be
building that funnel first, for this one benefit.

Partial adoption is worse than neither: scopes for some apps and not others
gives you a resource view that is confidently wrong.

### The decision

**Not adopted.** Two reasons, in order of weight:

- **The benefit is one item and the coverage is hard.** Above.
- **Session choice is our mechanism, and it happens at the greeter.** uwsm
  changes the `wayland-session` entry, which is exactly the surface three
  greeters have already broken on (`modules/desktop.nix`, greeter history).
  Adding a layer between SDDM and the compositor is a bad trade for cgroup
  hygiene on a machine with that record.

**A third reason used to be recorded here and was wrong** — worth keeping,
because the mistake is an easy one to make again. The comment read that
uwsm "manages the session as systemd units, which is the opposite of the
compositor-autostart model noctalia wants (§7a)". It is not the opposite:
uwsm does not stop `spawn-at-startup` / `exec-once` from starting the shell
as a child of the compositor. What §7a forbids is noctalia's own
*deprecated systemd unit* (`home/niri.nix:100`, `home/hyprland.nix:279`) —
a different thing that uwsm neither needs nor provides. Two mechanisms were
conflated because both have "systemd" in the description. Corrected in
`modules/hyprland.nix` on 2026-09-22.

Unrelated to any of this, and worth recognising rather than debugging cold:
**`hyprland-uwsm.desktop` is already installed**, because the Hyprland
package ships it regardless of `withUWSM`. It is inert — `TryExec=uwsm`,
and `uwsm` is not on PATH — so the greeter should hide it.

## Launching an agent with context

Omarchy's drop-down agent console is the most interesting thing in the
distro and the part most worth stealing from. What follows is how theirs
works, then what ours would have to do differently.

### How Omarchy does it

**The console** is `special:scratchpad` dressed up
(`default/hypr/qconsole.lua`): `dim_special = 0.6` behind it, slide-from-top
animation, and `on_created_empty` seeding it with `omarchy-agent`. The panel
is sized *by workspace gaps* rather than a window rule, because window-rule
size expressions resolve once at map time and go stale on a rescale — so it
subscribes to monitor and workspace events and recomputes. That detail is
the tell for how much care is in this file.

**Starting** is a normalization table. No default agent ships; fourteen CLIs
exist as lazy mise stubs, and `bin/omarchy-agent` maps each one's spelling
of "don't stop to ask" and "here is a prompt":

```
claude       → --permission-mode auto           prompt: -- "$prompt"
codex        → --approve-for-me                 prompt: -- "$prompt"
opencode     → --auto                           prompt: --prompt
agy          → --dangerously-skip-permissions   prompt: --prompt-interactive
cursor-agent → --yolo --trust                   prompt: agent -- "$prompt"
```

Everything launches through `omarchy-launch-tui --app-id=org.omarchy.agent`
— a fixed app-id rather than the per-binary default, so window rules can
target "the agent window" whichever agent you picked. Worth stealing
outright if we ever build this; it costs nothing.

**Context** arrives two ways. Ambient: `default/agents/skills/` is symlinked
into six harness locations by `omarchy-provision-user`, looping over the
directory so a third skill needs no edit. One-shot: `omarchy agent prompt
"..."` seeds a session while keeping it interactive.

**The crash path combines both, and is the best-designed piece.**
`omarchy-crash-watch` follows the systemd-coredump journal and raises a
toast whose click runs `omarchy-agent-crash <pid> <comm> <exe> <signal>` —
via `--exec`, so a hostile process name stays a discrete argument. The
script looks the timestamp up live from `coredumpctl`, builds a prompt
carrying the five facts, and then, rather than inlining the method, points
at the `diagnose-crash` skill, with a fallback line giving the literal path
for harnesses with no skill mechanism.

That is `docs/agent-context.md`'s always-loaded-versus-on-demand split
applied to a prompt: five facts inline, the method by reference, and a
degradation path when the reference cannot be resolved.

**Two things not to copy.** Every desktop-launched agent runs in
bypass-permissions mode, and the Quake console starts one the first time you
hit the key. And the skills are symlinks into a package-owned tree, so
`omarchy update` rewrites the instructions the agent is reading, without
asking. The Nix equivalent — `home.file` symlinks into the store — looks
identical and is not the same thing, because the content is pinned by the
flake and changes when you decide it does.

### Working directory

Omarchy's `bin/omarchy-cmd-terminal-cwd` does `hyprctl activewindow` → pid →
`pgrep -P` first child → `readlink /proc/$shell/cwd`, with a sanity check
that the child's exe is in `/etc/shells`. It carries a kitty special-case,
because kitty is one process for many windows and the PID walk finds "the
most recently spawned shell anywhere" instead of the focused one.

**`foot --server` is in that same category, and worse** — every footclient
window reports the server's PID over Wayland, and unlike kitty, foot has no
query side to its IPC. footclient asks the server for a window; there is
nothing to ask back.

We run foot standalone, so the plain `/proc` walk works here today. This is
the thing to remember: **switching foot to server mode silently breaks
cwd inheritance**, and there is no fix on foot's side. If server mode ever
becomes attractive, the replacement is to push rather than pull — a fish
hook writing cwd to a file keyed by window, since fish is the one thing
that already knows. The push version survives the mode change; the pull
version does not.

### Environment — do not copy it

The tempting next step after cwd is to lift `/proc/<pid>/environ` from the
focused shell. **It does not do what it looks like it does.** That file is
the snapshot taken at `exec`. direnv and `nix develop` mutate the *shell's*
environment afterward and never write back to it. So a copy faithfully
reproduces the login environment and silently omits the dev shell — the
only part worth having.

Re-derive from the cwd instead: `direnv exec <dir> <agent>`, or
`nix develop <dir> -c <agent>`. Same result, declaratively, and the agent
lands in the environment the project declares rather than whatever the
shell has drifted into.

### Detaching

Omarchy's agent dies with its window; the console *is* the process. To make
it survive, the agent must not be the window's child —
`systemd-run --user --scope`, or a tmux session with the console as a view
onto it.

This is uwsm's per-app-scope idea applied at exactly one launch point, where
we control the path and the benefit is concrete. **Take the technique, skip
the session manager.** It is also the only part of the uwsm story that has a
real use here.

Once the agent is detached, "one agent at a time" becomes a UI choice rather
than a constraint — both compositors take arbitrarily many named special
workspaces, so `special:agent-<project>` is available later. Start with one
anyway.

### When the focused window is not a terminal

Do not build per-app integration for this. Helix has no remote protocol to
integrate with, and Helix runs *inside* foot regardless, so the real gap is
browsers and GUI apps — and there the honest answer is that you do not want
that app's context, you want the project you were last in. Track the
last-focused terminal off the compositor's event socket and fall back to it.

For file-level context specifically, Helix sets the terminal title to the
open file, so `hyprctl activewindow -j | jq .title` (or niri's
`niri msg focused-window`) may get it with no integration at all. **Not
verified on this machine** — one command to check before relying on it.

## Open items

- Neither this file nor `docs/agent-context.md` is referenced from
  `CLAUDE.md`, which by that file's own argument makes both dead files.
  **Deliberately still open.** The likely answer is not a pointer per doc
  but a convention: a `docs/open_problems.md` in every project, as the one
  file the always-loaded tier points at. That convention is being worked
  out and should be settled once, for all repos, rather than patched here.
- Whether Helix's terminal title is actually readable per-window, per the
  last section above. One command, never run.

## Rules for this document

It records *decisions and their reasons*, and survey findings that informed
them. It does not restate what a module header already says — where the
reason lives in `modules/*.nix`, this file points at the line.

Anything here describing Omarchy is a snapshot with a date on it, not a
dependency. If a detail matters enough to rely on, re-read the source and
re-date it rather than trusting this file.
