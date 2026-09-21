# Standing instructions

Loaded into every Claude Code session on this machine (`~/.claude/CLAUDE.md`,
generated from `home/claude-code.md` in the nix-config repo — edit it there and
apply, not in `~/.claude`, which is a read-only symlink).

Everything here is true across repos. Anything true of only one repo belongs in
that repo's own `CLAUDE.md`.

## Commands that are not yours to run

`just switch`, `just boot`, `just update`, `nixos-rebuild`, `git push` and
`git checkout`. Don't run them, and don't ask to run them — no "want me to
switch?", no permission prompt. They are run by hand, deliberately, and the
decision of when is not a step in your task.

Finish the work, leave it in the working tree, say what you changed and what
verification you did. Stop there. Mentioning that a rebuild is what would apply
it is fine as a statement of fact; turning it into a question or an offer is
not.

## Committing

`git commit` **is** yours to run — but only when asked for it in that turn, in
as many words. Never volunteer it, never offer it, and never tack it onto the
end of another task: finishing a piece of work is not a reason to commit it.

When it is asked for, write the message. That is the point of handing it over,
so don't ask what to put in it and don't ask whether to go ahead with what is
staged — write it and commit. Message style is under Git below.

## Explaining is the default; doing is the exception

Much of this user's work is deliberate practice — they write the code and the
value is in the writing. Default to explaining, reviewing and verifying.

- "Explain X", "how do I X", "why is X" want an answer, not a fix. Describing
  the correct state is fine; changing files is not. First-person-plural framing
  ("let's do X first") is an invitation to walk through it, not authorization
  to edit.
- "Look through", "get your bearings", "have a look" mean read and report.
  Don't build, run, or start anything.
- Only write or edit their code when the current turn says so in as many words
  ("you do it", "write that for me", "scaffold this"). An explicit ask is
  scoped to the thing asked about, not an invitation to tidy nearby.
- Answer about what was asked and stop. Noticing an adjacent problem is fine;
  volunteering it is not.
- Don't report what their tooling already shows — unused variables, type
  errors, anything red in the IDE or caught by a build. Save it for what needs
  reasoning or execution to find: logic bugs, wrong-but-compiling code, spec
  mismatches.
- Answer from knowledge first. Run something only when the answer genuinely
  depends on a measured fact, and say why.

## Git

- Commit straight to `main`. These are personal repos with no reviewers; a
  feature branch and a PR are pure overhead — so when a commit *is* explicitly
  asked for, don't create a branch first, and don't ask whether to. Unrelated
  work still goes in separate commits.
- Commit only what is already staged. Untracked files are untracked on purpose:
  note that they exist rather than folding them in, even when the phrasing
  ("commit the added files") seems to invite it.
- Commit messages: imperative subject line, then a body that explains *why* —
  what the alternatives were and why they lost, what constraint forced the
  shape. The diff already says what changed. No conventional-commit prefixes.
- Every commit message ends by stating what was verified and what was not.
  "Verified: X, Y. Not verified: Z" — being explicit about the untested edge is
  the point, not a disclaimer.
- Commit as `serverplumber <7907191+serverplumber@users.noreply.github.com>`.
  The personal email never goes into git config, a commit trailer, or anything
  else committed or published, even though session context exposes it.
- Nothing committed may disclose why a project exists or who it is for. Ignore
  rules get bare paths and no explanatory comment — a comment saying *why* a
  file is hidden publishes the very fact the rule was protecting. Exclusions
  that are themselves sensitive belong in `.git/info/exclude`, which is never
  committed.

## This machine

- NixOS, configured declaratively by the flake at `~/code/nix-config`. Prefer a
  change to that repo over an imperative one: anything written directly into a
  dotfile or installed outside nix is lost at the next rebuild, or silently
  fights home-manager for ownership of the file.
- The login shell is `fish`, so commands *suggested for the user to run* should
  be fish-compatible. The Bash tool is still bash — that distinction matters
  for `export`, `&&` chains and `$()` vs `()`.
- The user edits in Helix, whose `:reload-all` frequently fails to refresh open
  buffers, so their view of a file can lag what is on disk. When they report a
  change as missing or reverted, read the file and show the lines before
  re-explaining or redoing anything. State the disk contents plainly — this is
  an editor artifact, not a disagreement about what happened.
- Work here is solo and sequential, and the token budget rules out parallel
  workflows. Do it inline: no subagents, no parallel exploration, no design
  that assumes concurrent lines of work. Prefer targeted reads and greps over
  broad sweeps — the budget is better spent on the work than on rediscovering
  context.
- `just` is the task runner, never `make`. Builds must be hermetic, with nix as
  the toolchain source: an unpinned CI toolchain is worse than no CI. Don't add
  CI scaffolding unprompted; when it is wanted, drive it through nix calling a
  single `just` entry point.
- Prefer a small, well-tested leaf library to a hand-rolled data structure.
  Before concluding one doesn't fit, look for its extension point — "the policy
  I want is missing" is usually not the same as "wrong library".
