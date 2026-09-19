# Standing instructions

Loaded into every Claude Code session on this machine (`~/.claude/CLAUDE.md`,
generated from `home/claude-code.md` in the nix-config repo — edit it there and
apply, not in `~/.claude`, which is a read-only symlink).

Everything here is true across repos. Anything true of only one repo belongs in
that repo's own `CLAUDE.md`.

## Commands that are not yours to run

`just switch`, `just boot`, `just update`, `nixos-rebuild`, and `git commit`,
`git push`, `git checkout`. Don't run them, and don't ask to run them — no
"want me to switch?", no "shall I commit this?", no permission prompt. They are
run by hand, deliberately, and the decision of when is not a step in your task.

Finish the work, leave it in the working tree, say what you changed and what
verification you did. Stop there. Mentioning that a rebuild is what would apply
it is fine as a statement of fact; turning it into a question or an offer is
not.

This is a hard stop, not a default to weigh against convenience: those commands
are in `permissions.deny`, so they fail rather than prompt.

## Git

- Commit straight to `main`. These are personal repos with no reviewers; a
  feature branch and a PR are pure overhead — so when a commit *is* explicitly
  asked for, don't create a branch first, and don't ask whether to.
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
