# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A NixOS flake config for `stablefly`'s laptop, migrated from Bluefin (an
ostree/Fedora image). **The migration is done and the machine is running
NixOS** — this is no longer a from-scratch build. Current work is bug
fixing and polish (desktop/greeter behavior, package corrections, shell
integration, fonts, etc.), tracked via normal commits.

`bluefin-to-nixos-migration.md` and `package-migration.md` are historical
runbooks from the migration itself (disk layout, invariants, the
package-mapping decisions). They're useful background on *why* things are
built the way they are, but treat them as a record of past decisions, not
as an active task list — don't infer that the migration is still in
progress from their "status" headers.

## Commands

All commands go through `just` (see `justfile`). It transparently uses a
host `nix` if present, otherwise runs `nix` inside a `ghcr.io/nixos/nix`
podman container with a shared `nix-store` volume — so these work
identically on and off NixOS.

- `just verify` — `parse` + `fmt-check`; the fast pre-flight (works even
  without git or network).
- `just check` — full `nix flake check`. Needs git-tracked files.
- `just fmt` — format all `.nix` files with nixfmt (the repo's `nix fmt`
  formatter too).
- `just build` — build the laptop system closure without applying it.
- `just vm` / `just run-vm` — build and boot `laptop-vm` (same config, no
  real disks). niri cannot render in the VM (no EGL); Hyprland and Plasma
  can be tested there.
- `just iso` — build the live installer ISO carrying this flake.
- `just switch` — `nixos-rebuild switch` on the real machine. Applies to
  the whole system: home-manager is imported as a NixOS module, not used
  standalone, so there is no `home-manager` CLI on PATH and no home-only
  apply. (`just home` still *builds* the home half on its own.)
- `just boot` — `nixos-rebuild boot`: stage for the next boot and touch
  nothing running. The **required** verb when the kernel or the nvidia
  driver moves; see "Updating" below.
- `just diff` — build the closure and `nvd diff` it against the running
  system, then say whether to `switch` or `boot`. Runs automatically
  after `just update`.
- `just needs-reboot` — is the running system still `/run/current-system`?
  Exits 1 when an earlier `switch` left a reboot owed.
- `just have <attr>...` — check whether nixpkgs attribute names exist
  (`ok` / `MISSING` / `THROWS`) before wiring them into a module.
- `just show` / `just lock` / `just update` — flake introspection/pin
  management.

No test suite; correctness is `just verify` / `just check` / `just build`
succeeding, plus (for anything touching the desktop) actually booting
`just vm` or applying to the real machine.

### Updating

`just update` → read what `just diff` prints → `just switch` **or**
`just boot` + reboot. Never reflexively `switch` after an update.

`switch` is wrong whenever `kernel`, `kernel-modules` or `initrd` moved,
and `just diff` exists to catch exactly that. Activation repoints
`/run/opengl-driver` at the new userspace nvidia driver while the old
kernel module stays loaded — it *cannot* be unloaded, `nvidia_drm` is
pinned by the running compositor. The result is `Driver/library version
mismatch`: `nvidia-smi` dies, and
`nvidia-container-toolkit-cdi-generator.service` (see `modules/nvidia.nix`)
fails and wipes `/var/run/cdi` via `RuntimeDirectory=`, so rootless GPU
containers break too. `nixos-rebuild` prints no warning about any of this
and exits non-zero, so the switch looks simply broken.

Note that `kernel-modules` is the signal that matters: the nvidia module
is built into that closure, so a driver-only bump changes it even when the
kernel itself is unchanged.

`just boot` avoids the whole window by never repointing
`/run/current-system` — the same staging model as the ostree deployments
this machine migrated from.

## Architecture

- `flake.nix` defines four outputs sharing `commonModules` (`hosts/laptop`
  + home-manager): `laptop` (real machine), `laptop-vm` (same config,
  QEMU-friendly overrides inlined in `flake.nix`), `installer` (live ISO
  carrying this flake), and standalone `homeConfigurations.stablefly`.
- `hosts/laptop/` — machine-specific: `default.nix` (portable — boots fine
  in the VM too) imports every module in `modules/`; `machine.nix` +
  `hardware-configuration.nix` + `filesystems.nix` + `boot.nix` are the
  real-disk-only parts, imported only by `nixosConfigurations.laptop`.
- `modules/` — one NixOS module per concern (desktop, each compositor,
  audio, nvidia, containers, backup, caches, …). Each file's header comment
  explains *why* it's shaped the way it is — read those before editing
  rather than guessing.
- `home/` — home-manager config for the `stablefly` user, imported both
  under the NixOS config and standalone (`homeConfigurations.stablefly`).
- Desktop choice happens at the greeter, not in config: niri, Hyprland and
  Plasma are all installed; `modules/desktop.nix` owns the SDDM
  greeter/session wiring; noctalia is the shared shell (bar/launcher/
  notifications/lockscreen) for the two tiling sessions.
- `modules/caches.nix` and `.nix-config` both configure extra binary
  caches (Hyprland, noctalia, CUDA) and must be kept in sync **by hand** —
  one is a NixOS module (configures the machine *being built*: laptop and
  the installer ISO), the other is a plain `nix.conf` read by the
  container builder (configures the machine *doing* the building). See the
  comment block in `modules/caches.nix` for the three contexts that need
  this.
- `modules/backup.nix` reads `backup-excludes.txt` as its single source of
  truth for restic exclusions, shared with the manual `just restic_init`
  recipe — never duplicate the exclude list.
- nixpkgs is the only package source: no flatpak, homebrew, or AppImages.
  Five apps are sandboxed via `nixpak` (see `package-migration.md` §1c for
  which and why); browsers and hardware-facing apps deliberately aren't.
- `pkgs/` holds locally-packaged derivations not in nixpkgs (currently
  `ant-cli.nix`).
- uid/gid for `stablefly` (1000) and the subuid/subgid ranges
  (524288:65536) are pinned rather than auto-allocated, because `/home` and
  the rootless podman store are pre-existing data from Bluefin that must
  keep their existing ownership — see the comments in
  `hosts/laptop/default.nix`.

## Keyboard

The primary — effectively only — input device is a **Preonic**, a compact
ortholinear keyboard, carried everywhere and used as if it were the sole
keyboard on any machine. This is a hard constraint on every keybinding
decision in `home/niri.nix`, `home/hyprland.nix`, and anywhere else binds
get defined.

On its top (base) layer, the only non-printing keys are: **Esc, Shift,
Ctrl, Alt, Meta/Super, Backspace, arrow keys (Left/Right/Up/Down)**, and
one unidentified key at the bottom-left (mapped to something, unknown
what — ask before relying on it). Everything else on that layer types a
character. Notably:

- **Home/End, Page Up/Down, Print Screen, and Delete are unconfirmed** —
  never got a straight answer on these, don't assume either way. Binds
  that use them (niri's own defaults include several — Home/End,
  Page_Down/Page_Up, Print, Ctrl+Alt+Delete) may or may not be a direct
  press; ask before relying on one, same as the bottom-left key.
- Volume keys (XF86Audio{Raise,Lower,Mute}Volume) are present. Status of
  the rest of the XF86 media/backlight set is unconfirmed — check before
  relying on one.
- `\` (backslash) sits right below Backspace, an actual physical key.
- Shift+Backspace is plain Backspace today, not Delete — there's a
  standing plan (not yet done) to remap it to Delete on the QMK layer.
  Binds that reserve Shift+Backspace for that future Delete meaning (e.g.
  `home/niri.nix`'s lock binds deliberately skip it) should keep doing so.

Net effect: prefer letter/number keys plus the five modifiers above for
anything meant to be reachable at a glance. `home/niri.nix`'s binds block
has a concrete example — the vi-style H/J/K/L remap (H/L = focus column
left/right, J/K = focus workspace down/up, Shift+J/K = move column to
workspace down/up) done specifically because hjkl + modifiers is what's on
the top layer.
