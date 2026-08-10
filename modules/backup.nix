{ lib, ... }:
let
  # Single source of truth, shared with `just restic_init`. Read at eval time
  # so the manual pre-migration run and the automated job can never disagree
  # about what is skipped.
  #
  # lib.splitString, not builtins.split — the latter interleaves regex-match
  # groups (lists) among the strings, which then blow up on any string op.
  excludes = lib.filter (l: l != "" && !(lib.hasPrefix "#" l)) (
    lib.splitString "\n" (builtins.readFile ../backup-excludes.txt)
  );
in
{
  services.restic.backups.home = {
    # ⚠️ SET THIS. A removable drive is the wrong target for a daily timer —
    # the unit fails every time it is unplugged. Options, best first:
    #   - a NAS over SFTP:  "sftp:user@host:/srv/backup/laptop"
    #   - object storage:   "s3:s3.eu-central-1.amazonaws.com/bucket"
    #   - rclone anything:  "rclone:remote:path"
    # Keep the external USB drive for the manual `just restic_init` run.
    repository = "sftp:CHANGEME:/srv/backup/laptop";

    # ***

    # NEVER inline the password. /nix/store is world-readable, so a literal
    # here would be a plaintext secret readable by every user and every build.
    # Create this file out of band:
    #
    #   sudo install -d -m 0700 /etc/restic
    #   sudo sh -c 'head -c 32 /dev/urandom | base64 > /etc/restic/password'
    #   sudo chmod 0400 /etc/restic/password
    #
    # AND WRITE IT DOWN SOMEWHERE ELSE. Lose this file and the repository is
    # unrecoverable — that is the encryption working as designed, not a bug.
    # sops-nix or agenix is the better long-term answer.
    passwordFile = "/etc/restic/password";

    initialize = true;

    paths = [ "/home/stablefly" ];
    exclude = excludes;

    timerConfig = {
      OnCalendar = "daily";
      # Catch up after the laptop has been asleep or off, rather than silently
      # skipping the window.
      Persistent = true;
      RandomizedDelaySec = "30m";
    };

    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 5"
      "--keep-monthly 12"
      "--keep-yearly 3"
    ];
  };

  # ***

  # Restic reads a live filesystem, so a file written mid-backup can be caught
  # half-done. For a laptop home directory that is normally acceptable. The
  # rigorous fix is snapshot-then-back-up-the-snapshot: add a
  # `backupPrepareCommand` that takes a read-only btrfs snapshot and point
  # `paths` at that instead.
  #
  # Deliberately not done yet — it needs the post-migration nixos/home
  # subvolume layout to exist.
}
