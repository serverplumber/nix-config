# Changelog

Notable changes to this configuration, newest first. The commit log has the
detail; this is the record of what changed in kind.

## 2026-10-05 — no longer a migration

This repo started as a migration from Bluefin to NixOS (first commit
`f59a5b8`, 2026-08-09). The laptop ran Bluefin, an image-based Fedora (ostree)
desktop, and was reinstalled as NixOS in place on the same disks: `/home`
and the rootless podman store were kept as existing btrfs subvolumes, Windows
on the other disk was left untouched, and every package was re-provisioned
from nixpkgs instead of flatpak, homebrew or AppImages. That migration is
finished: the laptop runs NixOS, and this is now simply its configuration.
The scaffolding that only existed to get it here is gone:

- The runbooks `bluefin-to-nixos-migration.md` and `package-migration.md`,
  and the SD-backup plan in `docs/planned/backup.md` (now `sdbackup`), are
  removed; comments that pointed into them now stand on their own. Last
  versions, readable with `git show <commit>:<path>`:
  - `bluefin-to-nixos-migration.md` — `9d5b5a8`
  - `package-migration.md` — `0cd59b7`
  - `docs/planned/backup.md` — `055af95`
  - `.nix-config` — `1aeadd5`
- The justfile calls the host `nix` directly. The `ghcr.io/nixos/nix` podman
  fallback, its `nix-store` volume recipes and `.nix-config` are removed.
- The pre-migration `just restic_init`, `restic_size` and `restic_check`
  recipes are removed. SD-card backups go through `sdbackup`.
