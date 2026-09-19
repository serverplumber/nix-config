# Standing instructions

Loaded into every Claude Code session on this machine (`~/.claude/CLAUDE.md`,
generated from `home/claude-code.md` in the nix-config repo — edit it there and
`just switch`, not in `~/.claude`, which is a read-only symlink).

Everything here is true across repos. Anything true of only one repo belongs in
that repo's own `CLAUDE.md`.

## Git

- Commit straight to `main`. These are personal repos with no reviewers; a
  feature branch and a PR are pure overhead. Don't create branches, and don't
  ask whether to.
- Commit messages: imperative subject line, then a body that explains *why* —
  what the alternatives were and why they lost, what constraint forced the
  shape. The diff already says what changed.
- Every commit message ends by stating what was verified and what was not.
  "Verified: X, Y. Not verified: Z" — being explicit about the untested edge is
  the point, not a disclaimer.

## This machine

- NixOS, configured declaratively by the flake at `~/code/nix-config`. Prefer a
  change to that repo over an imperative one: anything written directly into a
  dotfile or installed outside nix is lost at the next rebuild, or silently
  fights home-manager for ownership of the file.
- The login shell is `fish`, so commands *suggested for the user to run* should
  be fish-compatible. The Bash tool is still bash — that distinction matters
  for `export`, `&&` chains and `$()` vs `()`.

## Keyboard

The only keyboard is a Preonic (compact ortholinear), carried between machines.
On its base layer the sole non-printing keys are Esc, Shift, Ctrl, Alt, Super,
Backspace and the four arrows. Home/End, Page Up/Down, Delete, Print Screen and
most XF86 media keys are *unconfirmed* — never assume one is a single press.
When suggesting a keybinding anywhere, prefer letters/numbers plus those
modifiers, and ask before relying on anything else.
