# Standing instructions

Loaded into every Claude Code session on this machine (`~/.claude/CLAUDE.md`,
generated from `home/claude-code.md` in the nix-config repo — edit it there and
apply, not in `~/.claude`, which is a read-only symlink).

Everything here is true across repos. Anything true of only one repo belongs in
that repo's own `CLAUDE.md`.

## Don't ask, just do it

Never ask permission to commit, push, or check out a branch, and never ask
before running a project's own build or apply command — on this machine that
means `just switch`, `just boot` and `just update`. Run them and report what
happened. Handing the command back with "want me to run it?" is the thing to
avoid; these are routine, and a rebuild is reversible through generations.

This does not extend to genuinely destructive verbs that lose work with no
generation to roll back to — `git reset --hard`, `git clean`, deleting
untracked files. Those still get a question.

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
