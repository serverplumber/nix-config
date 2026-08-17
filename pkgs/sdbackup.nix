{
  lib,
  writeShellApplication,
  rustic,
  libnotify,
  jq,
  coreutils,
  gawk,
  gnused,
  util-linux,
  systemd,
  # The repo's single source of truth for exclusions, shared with
  # `just restic_init` and modules/backup.nix (CLAUDE.md: never duplicate it).
  # Passed in rather than referenced by relative path so this derivation stays
  # buildable on its own.
  excludeFile ? null,
  # Policy, baked in rather than passed per-invocation so that a `sdbackup run`
  # typed by hand in a terminal behaves identically to one fired from a keybind.
  budgetMinutes ? 20,
  dueAfterDays ? 7,
}:

# sdbackup — offsite backup to an SD card you carry.
#
# The script lives in ./sdbackup/sdbackup.sh as a real file rather than a Nix
# string. Two reasons: it stays directly runnable and testable outside Nix
# (`SDBACKUP_SEARCH_PATHS=/tmp/fake bash sdbackup.sh cards`), and when this is
# eventually rewritten as a single binary the port reads one ordinary shell
# script instead of unpicking a derivation.
#
# writeShellApplication runs shellcheck at build time, so a lint regression
# fails the build rather than the backup.

let
  # Build-time defaults. `:=` not `export`, so anything already in the
  # environment still wins — that is what makes the script testable.
  defaults = ''
    : "''${SDBACKUP_EXCLUDES:=${lib.optionalString (excludeFile != null) "${excludeFile}"}}"
    : "''${SDBACKUP_BUDGET_MINUTES:=${toString budgetMinutes}}"
    : "''${SDBACKUP_DUE_DAYS:=${toString dueAfterDays}}"
  '';

  # Drop the script's own shebang: writeShellApplication supplies one, and a
  # second would just sit in the middle of the file as a stray comment.
  body = lib.removePrefix "#!/usr/bin/env bash\n" (builtins.readFile ./sdbackup/sdbackup.sh);
in
writeShellApplication {
  name = "sdbackup";

  runtimeInputs = [
    rustic # the backup engine — reads .gitignore, writes restic-format repos
    libnotify # notify-send: the reminder path
    jq # marker files and state are JSON
    coreutils # date, sync, mktemp, numfmt, sha256sum, wc, uname
    gawk # parsing `rustic ls --long`
    gnused
    util-linux # flock (run lock), findmnt (card label)
    systemd # systemd-inhibit — keeps the 600s idle-suspend off the run
  ];

  text = defaults + body;

  meta = {
    description = "Offsite backup to a pocketable SD card, with card identity and break-sized runs";
    mainProgram = "sdbackup";
    platforms = lib.platforms.linux;
  };
}
