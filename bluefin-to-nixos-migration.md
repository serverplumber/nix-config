# Bluefin → NixOS Migration Runbook (v2)

Laptop, dual-disk. Replace the OS, keep all existing btrfs data in place.
Bootloader: GRUB (chosen for cross-disk Windows detection).

This document is written for handoff — §11 is the task list for an agent
working in the repo. Read §0 and §1 first; they contain hard invariants.

**Status (2026-08-10).** The tree in §4 is built, committed, and — since the
commit unblocked `flake lock` — **evaluated**. Four of five flake outputs
evaluate cleanly; `nixosConfigurations.laptop` throws on the
`hardware-configuration.nix` placeholder by design, which is the only
remaining failure and needs the ISO. See §8a for the evaluation results and
§8b for what the flake produces.

Nothing has been *built* or installed. The machine still runs Bluefin.

Decisions since v2 that changed the plan materially:

- **The desktop is no longer labwc.** niri + Hyprland + Plasma, all three
  offered by the greeter, with noctalia as the shell for the two tiling
  sessions. §7/§8's labwc blocks are superseded by **§7a**.
- **nixpkgs is the only package channel** — no flatpak, homebrew or
  AppImages. All 105 attribute names verified against nixpkgs-unstable.
- **Windows is reached via the firmware picker**, not GRUB. os-prober is off,
  so nothing in this procedure touches `nvme0n1` at all — O-1.
- **Five apps are sandboxed** with nixpak; browsers and hardware-facing apps
  deliberately are not — see `package-migration.md` §1c.
- **whisperx runs on the GPU** via a targeted second nixpkgs instance — O-12.

The code blocks in §5–§8 are commentary and lag the files. `hosts/`,
`modules/` and `home/` are the source of truth.

---

## 0. Hard invariants

1. **`nvme0n1` is Windows. Never partition, format, or write to it.**
   The single exception is os-prober, which mounts its partitions
   read-only during `grub-mkconfig`. See open problem O-1.
2. **The `home` subvolume on `nvme1n1p3` is live user data.** It is
   mounted, never created, never formatted, never copied.
3. **Nothing in this procedure is destructive until §10.** Until then the
   Bluefin deploy tree remains intact and bootable.

---

## 1. Known disk facts

| Device | Role | Action |
|---|---|---|
| `nvme0n1` p1–p5 | Windows, 954 GiB | Untouched. Not mounted. |
| `nvme1n1p1` | ESP, 599 MiB, 3 % used | NixOS `/boot` |
| `nvme1n1p2` | ostree `/boot`, 974 MiB, 79 % used | Unused by NixOS |
| `nvme1n1p3` | btrfs, 930 GiB, 432 GiB free, 53 % used | All Linux data |

Measured UUIDs (from `/dev/disk/by-uuid` on the running Bluefin system;
nothing in this procedure reformats either filesystem, so these are the
values the ISO will see — re-confirm per §2.3 anyway):

| Partition | UUID |
|---|---|
| `nvme1n1p1` (ESP, vfat) | `49A3-D385` |
| `nvme1n1p3` (btrfs) | `6f8449a5-f6b6-4f60-adb1-c9b6c58cac3a` |
| `nvme1n1p2` (old ostree `/boot`) | `1f942a43-9b8a-4299-b1bc-283c264309ec` |

Hardware, for the record: 13th Gen Intel Core i9-13900H, hybrid graphics —
Intel Iris Xe (`PCI:0:2:0`, `card0`, i915) + NVIDIA RTX 4070 Laptop / AD106M
(`PCI:1:0:0`, `card1`). The Bluefin image was `bluefin-dx-nvidia`, driver
580.95.05. See O-6.

Displays, measured while the current correct config was running:

| Connector | GPU | Mode | Scale | Position |
|---|---|---|---|---|
| `eDP-1` | Intel `card0` | 3840x2400@60 (only mode) | 2 | 0,1080 |
| `HDMI-A-1` | **NVIDIA `card1`** | 3840x2160@60, LG Ultra HD | 2 | 0,0 — primary |

The external port being on the NVIDIA side is load-bearing — see O-10.
`card0-DP-1..4` (Intel) and `card1-DP-5,6` (NVIDIA) are all disconnected.

Subvolumes on `nvme1n1p3`, per `findmnt`:

| Subvolume | Bluefin mount | Disposition |
|---|---|---|
| `root` | `/sysroot` (ro) | ostree deploy tree → delete in §10 |
| `var` | `/var` | system flatpaks, logs, local overrides → **inventory before deleting**. *Not* container images — see below |
| `home` | `/var/home` | **carried over as `/home`, untouched** |

`home` being a genuine top-level subvolume is the reason this migration
needs no data movement. It gets mounted, not migrated.

The single user is **`stablefly`** (uid 1000, gid 1000), home at
`/var/home/stablefly` → `/home/stablefly` after the migration. Earlier drafts
of this document used a different username; `stablefly` is the one that
matches the on-disk data. The uid and gid are pinned in
`hosts/laptop/default.nix` because 487 GiB of files are already owned by
1000:1000.

`var` is easy to overlook. It holds `/var/usrlocal/bin/overrides/swtpm`
among other hand-placed files (visible as a bind-mount over
`/usr/bin/swtpm` in the current `findmnt`), plus **system-scope flatpak
storage** and logs. It is plausibly a large share of the 53 % used.

Correction to an earlier assumption: **podman storage is not on `var`.**
`podman info` reports `GraphRoot=/home/stablefly/.local/share/containers/storage`
— 96 GiB of rootless images sitting on the `home` subvolume. They carry over
with zero action. It is the 53 system-scope flatpaks that live on `var` and
are lost. See O-7.

---

## 2. Pre-flight

### 2.1 Inventory `var` while Bluefin still boots

**Done 2026-08-07.** Output is in `~/migration-notes/`:

```bash
mkdir -p ~/migration-notes
flatpak list --app --columns=application > ~/migration-notes/flatpaks.txt   # 53
podman images                            > ~/migration-notes/images.txt     # 44
ls -la /var/usrlocal/bin/overrides/      > ~/migration-notes/overrides.txt  # swtpm only
rpm-ostree status                        > ~/migration-notes/rpm-ostree.txt
brew leaves                              > ~/migration-notes/brew-leaves.txt    # 26
brew list --formula                      > ~/migration-notes/brew-formulae.txt  # 196
lsblk -o NAME,SIZE,FSTYPE,UUID,MOUNTPOINT /dev/nvme1n1 > ~/migration-notes/disks.txt
```

Write these into `~` (the surviving subvolume), not `/tmp`.

**Completed 2026-08-09** (needed a real terminal — `sudo -n` is unavailable to
the agent):

```
$ sudo btrfs subvolume list /var
ID 256 ... path var
ID 257 ... path home
ID 258 ... path root          # exactly the three expected, nothing else

$ sudo du -sh /var/lib/flatpak /var/log
18G     /var/lib/flatpak      # 53 system flatpaks — all dropped, all reclaimed
4.1G    /var/log
```

So §10's `btrfs subvolume delete var` reclaims ~22 GiB of flatpak and log data
on top of the ostree tree. Nothing on `var` is being carried forward.

Triage of the inventory (what gets reinstalled from nixpkgs, what gets
dropped) is in **`package-migration.md`**. Decision on record: no flatpak, no
homebrew, no AppImages on NixOS — nixpkgs is the single source per binary.

### 2.2 Save what NixOS will not regenerate

- `~/.ssh`, `~/.gnupg` — already on `home`, no action, just confirm present
- Hand-edited files under `/etc` — **these do not survive**; NixOS builds
  `/etc` declaratively from the config

### 2.3 Ground truth from the ISO

Boot the **NixOS minimal ISO**. Not the graphical one.

```bash
mount -o subvolid=5 /dev/nvme1n1p3 /mnt/btrfs
btrfs subvolume list /mnt/btrfs      # expect: root, var, home
blkid /dev/nvme1n1p1                 # ESP UUID   → record
blkid /dev/nvme1n1p3                 # btrfs UUID → record
efibootmgr -v                        # confirm firmware boots nvme1n1p1
```

### 2.4 Off-disk backup — **THE blocking prerequisite**

The old subvolumes are a rollback point against *this procedure*. They are not
a backup: they sit on the same SSD, so they survive a bad `nixos-install` and
nothing else. Same disk, same failure.

Two layers, and they are different tools:

| | What it protects against | Tool |
|---|---|---|
| btrfs snapshots | `rm -rf`, a bad change | snapper / btrbk — **post-migration** |
| off-machine copy | disk death, theft, fire | **restic** — needed *before* §3 |

Note a NixOS-specific twist for later: generations already give you system
rollback, so snapshotting `/` buys little here. The value is all in `/home`.

#### Doing it

```bash
just restic_init /run/media/stablefly/<drive>
just restic_check /run/media/stablefly/<drive>
```

Runs from Bluefin, before anything destructive, via the nix container — no
host install needed. Creates the repo if absent, then backs up `$HOME` using
`backup-excludes.txt`.

**The repo is portable.** `modules/backup.nix` appends to a repo of exactly
this shape after the migration, so this one-shot is also the first snapshot of
the permanent system rather than throwaway work.

Excludes are shared between the manual run and the NixOS job by reading the
same file, so they cannot drift. The big one is
`~/.local/share/containers` — 96 GiB of podman images, all pullable again.

#### Two things that are not optional

- **The password file is the repository.** Lose it and the data is gone; that
  is the encryption working. Store it somewhere that is not this laptop.
- **`just restic_check` before trusting it.** An unverified backup is a hope.

⚠️ `modules/backup.nix` ships with `repository = "sftp:CHANGEME:..."`. A
removable drive is the wrong target for a daily timer — the unit fails
whenever it is unplugged. Point the automated job at a NAS or object storage
and keep the USB drive for manual runs.

---

## 3. Disk operations

Total scope: two subvolume creations. Both required — see the note below.

```bash
mount -o subvolid=5 /dev/nvme1n1p3 /mnt/btrfs
btrfs subvolume create /mnt/btrfs/nixos
btrfs subvolume create /mnt/btrfs/nix
```

Splitting `/nix` keeps future snapshots of `/` cheap and meaningful — the
store is millions of small immutable files that snapshot logic should not
have to reason about.

Earlier drafts called the `nix` subvolume optional while `filesystems.nix`
declared it unconditionally. That combination boots nothing: `/nix` is in
`pathsNeededForBoot`, so a declared-but-missing subvolume fails in stage 1.
Both are now unconditional. Create it and declare it, or do neither.

**Do not** pass `nodatacow` to the `/nix` mount. Btrfs mount options other
than `subvol`/`subvolid` are filesystem-wide: the first mount wins, so a
per-subvolume `nodatacow` silently does nothing. It would also be wrong if
it worked — `nodatacow` implies `nodatasum` and disables compression,
trading zstd on highly compressible data for loss of checksums.

### Mount for install

```bash
mount -o subvol=nixos,compress=zstd,noatime /dev/nvme1n1p3 /mnt
mkdir -p /mnt/home /mnt/nix /mnt/boot
mount -o subvol=home,compress=zstd,noatime  /dev/nvme1n1p3 /mnt/home
mount -o subvol=nix,compress=zstd,noatime   /dev/nvme1n1p3 /mnt/nix
mount /dev/nvme1n1p1 /mnt/boot
```

---

## 4. Repo layout

As built, at the repo root (not in a nested `nixos-config/`):

```
nix-config/
├── flake.nix                           # 5 outputs — see §8b
├── flake.lock                          # 29 nodes; Hyprland pulls 13
├── justfile                            # every check/build/backup wrapped
├── backup-excludes.txt                 # shared by just + the NixOS job
├── .nix-config                         # nix.conf for the container
├── .gitignore
├── bluefin-to-nixos-migration.md       # this file
├── package-migration.md                # inventory triage + sandbox tiers
├── hosts/
│   └── laptop/
│       ├── default.nix                # portable config — boots in a VM
│       ├── machine.nix                # BARE METAL ONLY: imports the 3 below
│       ├── hardware-configuration.nix # PLACEHOLDER — throws until generated
│       ├── filesystems.nix            # hand-written, source of truth
│       └── boot.nix                   # GRUB, os-prober off — O-1
├── modules/
│   ├── desktop.nix                    # greetd/tuigreet 3-session picker — §7a
│   ├── niri.nix                       # niri-flake module, pkgs.niri package
│   ├── hyprland.nix                   # Hyprland flake + cachix
│   ├── plasma.nix                     # third session, known-good fallback
│   ├── noctalia.nix                   # shell's backing services + cachix
│   ├── audio.nix                      # pipewire
│   ├── hardware-keys.nix              # brightness/media key plumbing
│   ├── nvidia.nix                     # hybrid PRIME offload — O-6/O-10
│   ├── cuda.nix                       # CUDA cache only — O-12
│   ├── obs.nix                        # v4l2loopback for the virtual camera
│   ├── containers.nix                 # rootless podman — O-7
│   ├── network.nix                    # tailscale (+ ProtonVPN conflict note)
│   ├── printing.nix                   # CUPS + avahi discovery
│   ├── scanning.nix                   # SANE + sane-airscan
│   ├── nix-ld.nix                     # FHS loader for uv/foreign binaries — O-13
│   └── backup.nix                     # restic job
└── home/
    ├── default.nix
    ├── cli.nix                        # user CLI + GPU whisperx
    ├── dev.nix                        # direnv, forges, linters, JetBrains
    ├── gui.nix                        # 6 nixpak-sandboxed + the rest plain
    ├── niri.nix                       # typed settings, outputs, keybinds
    ├── hyprland.nix                   # matching keybinds
    └── noctalia.nix                   # shell, shared by both tiling sessions
```

`hardware-configuration.nix` is committed as a bare `throw` carrying the
generation command in its message. An empty stub would evaluate cleanly and
produce a system with no initrd modules — i.e. one that does not boot.

Generate the hardware file **with filesystems suppressed**, otherwise it
emits its own `fileSystems.*` and `swapDevices` attrs that collide with
`filesystems.nix` and fail evaluation:

```bash
nixos-generate-config --no-filesystems --root /mnt
# copy /mnt/etc/nixos/hardware-configuration.nix into hosts/laptop/
```

If the flag is unavailable in the ISO's version, generate normally and
delete the `fileSystems` and `swapDevices` blocks by hand.

**Flakes only see git-tracked files.** From the ISO:

```bash
git init && git add -A
```

Untracked files are invisible to the evaluator and produce confusing
"attribute missing" errors.

---

## 5. `flake.nix`

```nix
{
  description = "laptop";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }: {
    nixosConfigurations.laptop = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./hosts/laptop
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.stablefly = import ./home;
        }
      ];
    };
  };
}
```

---

## 6. `hosts/laptop/`

### `default.nix`

```nix
{ pkgs, ... }: {
  imports = [
    ./hardware-configuration.nix
    ./filesystems.nix
    ./boot.nix
    ../../modules/desktop.nix
    ../../modules/audio.nix
    ../../modules/hardware-keys.nix
  ];

  networking.hostName = "laptop";
  networking.networkmanager.enable = true;
  time.timeZone = "America/New_York";

  # Bluefin provided zram; NixOS does not by default.
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  users.users.stablefly = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" "audio" ];
    shell = pkgs.fish;
  };
  programs.fish.enable = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Match the release actually installed. Never bump this afterwards.
  system.stateVersion = "26.05";
}
```

### `filesystems.nix`

Substitute the two UUIDs recorded in §2.3.

```nix
let
  btrfsUUID = "6f8449a5-f6b6-4f60-adb1-c9b6c58cac3a";
  espUUID   = "49A3-D385";

  # Reminder: btrfs applies these filesystem-wide, first mount wins.
  # Listing them per-entry is cosmetic consistency, not per-subvolume config.
  btrfsOpts = [ "compress=zstd" "noatime" ];
in {
  fileSystems."/" = {
    device  = "/dev/disk/by-uuid/${btrfsUUID}";
    fsType  = "btrfs";
    options = btrfsOpts ++ [ "subvol=nixos" ];
  };

  # Pre-existing subvolume carried over from Bluefin. Never formatted.
  fileSystems."/home" = {
    device  = "/dev/disk/by-uuid/${btrfsUUID}";
    fsType  = "btrfs";
    options = btrfsOpts ++ [ "subvol=home" ];
  };

  # Only if /nix was split out in §3.
  fileSystems."/nix" = {
    device  = "/dev/disk/by-uuid/${btrfsUUID}";
    fsType  = "btrfs";
    options = btrfsOpts ++ [ "subvol=nix" ];
  };

  fileSystems."/boot" = {
    device  = "/dev/disk/by-uuid/${espUUID}";
    fsType  = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  swapDevices = [ ];   # zram only
}
```

### `boot.nix`

```nix
{ ... }: {
  boot.loader.grub = {
    enable      = true;
    efiSupport  = true;
    device      = "nodev";        # EFI install, no MBR target
    useOSProber = true;           # required for Windows on nvme0n1 — see O-1

    # ESP is ~600 MiB and copyKernels puts each generation's kernel and
    # initrd on it. Cap generations or /boot fills. See O-2.
    configurationLimit = 10;

    # /boot (vfat ESP) is a different filesystem from /nix (btrfs+zstd).
    # Copying kernels avoids relying on GRUB's btrfs+compression support.
    copyKernels = true;
  };

  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.efi.efiSysMountPoint = "/boot";
}
```

---

## 7. `modules/`

### `audio.nix`

Bluefin had this configured; NixOS boots silent without it.

```nix
{ ... }: {
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };
}
```

### `desktop.nix` — superseded

**labwc was dropped.** The desktop is now **niri + Hyprland, both installed,
chosen at the greeter**, with **noctalia** as the shell for either. See §7a.
The labwc config that used to live here is gone; `home/labwc.nix` was
deleted. Read the files, not this block.

### `hardware-keys.nix`

There is no DE handling function keys, so the plumbing is explicit. The
system side grants permission; the actual keybinds live in each compositor's
own config — `home/niri.nix` and `home/hyprland.nix` (§7a). Unchanged by the
compositor swap: both call the same three binaries.

```nix
{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    brightnessctl   # backlight
    wireplumber     # provides wpctl for volume
    playerctl       # MPRIS transport keys
  ];

  # udev rules so a member of the `video` group can set backlight
  # without setuid. User is already in `video` (see hosts/laptop).
  services.udev.packages = [ pkgs.brightnessctl ];
}
```

---

## 7a. Desktop: niri + Hyprland + noctalia

Supersedes the labwc plan in §7/§8. Files: `modules/{desktop,niri,hyprland,
noctalia}.nix` and `home/{niri,hyprland,noctalia}.nix`.

### Why both compositors

labwc was a *floating* compositor; niri and Hyprland are both tiling, and
niri's scrollable-column model in particular is something you either click
with immediately or bounce off. Rather than commit blind, both are installed
and `tuigreet` lists them as separate sessions — the choice happens at the
login prompt. Delete the loser's two files once it's decided.

**Plasma 6 is installed as a third session** (`modules/plasma.nix`), purely as
a known-good fallback: if niri and Hyprland both misbehave on first boot,
that's a working desktop to debug from instead of a TTY. It is by far the
heaviest thing in this config; delete it once the real desktop is trusted.
SDDM is explicitly disabled — greetd owns login for all three.

This is cheap specifically because **noctalia supports both natively**: the
bar, launcher, notifications, lockscreen and wallpaper are identical either
way. Only the compositor keybinds differ, and those are written to match
(same `hjkl`, same `Mod+Return`, same media keys).

### The two things that will silently not work

1. **noctalia must be started by the compositor, not by systemd.** Upstream
   deprecated the systemd-unit approach. It is `spawn-at-startup` in niri and
   `exec-once` in Hyprland. If you add a user unit *as well*, you get two
   shells; if the compositor is launched as bare `niri`/`Hyprland` instead of
   through its session wrapper, `graphical-session.target` never activates.
2. **Binary caches must be set before the inputs are first evaluated.**
   `hyprland.cachix.org` and `noctalia.cachix.org` are configured in
   `modules/hyprland.nix` and `modules/noctalia.nix`. Miss them and the first
   build compiles Hyprland and the shell from source on top of an already
   heavy install. niri-flake enables its own cache by default.

### Flake input note

`hyprland` deliberately does **not** use `inputs.nixpkgs.follows = "nixpkgs"`,
unlike every other input here. Upstream advises against it: overriding their
pinned nixpkgs invalidates every cache hit. `niri` and `noctalia` do follow.

### niri packaging

`sodiboo/niri-flake`, not the nixpkgs `programs.niri` module — the flake's
module *disables* the nixpkgs one, since both define the same option path.
Never enable both. What it buys: `programs.niri.settings` as typed Nix attrs
validated at build time rather than an unvalidated KDL string, plus
`niri.cachix.org` so nothing compiles. It also sets up polkit, an auth agent
and the keyring, which the Hyprland session then shares.

---

## 8. `home/`

### `default.nix`

```nix
{ ... }: {
  imports = [ ./cli.nix ./niri.nix ./hyprland.nix ./noctalia.nix ];
  home.username      = "stablefly";
  home.homeDirectory = "/home/stablefly";
  home.stateVersion  = "26.05";
  programs.home-manager.enable = true;
}
```

### `cli.nix`

```nix
{ pkgs, ... }: {
  programs.helix.enable = true;

  programs.starship = {
    enable = true;
    enableFishIntegration = true;
  };

  programs.eza = {
    enable = true;
    enableFishIntegration = true;
    icons = "auto";          # boolean form is deprecated upstream
  };

  home.packages = with pkgs; [
    vim
    uv
    glow
    mdformat
  ];
}
```

`mdformat` is packaged in nixpkgs. Do not also install it via `uv tool` —
one source per binary.

### `labwc.nix` — deleted

Replaced by `home/niri.nix`, `home/hyprland.nix` and `home/noctalia.nix`.
See §7a. The hand-written `rc.xml` no longer exists.

---

## 8a. Validating from Bluefin, without an ISO

There is no `nix` on the Bluefin host, but there is a **`ghcr.io/nixos/nix`
image and a populated `nix-store` podman volume**, both already on this
machine (the volume dates from 2026-07-19 and lives under
`~/.local/share/containers`, so it carries over the migration too). The
pattern is lifted from `~/code/krump/justfile`:

```bash
podman run --rm \
  -v "$PWD":/workspace:z \
  -v nix-store:/nix \
  --userns keep-id:uid=0,gid=0 \
  -e NIX_USER_CONF_FILES=/workspace/.nix-config \
  -w /workspace \
  ghcr.io/nixos/nix \
  nix --extra-experimental-features "nix-command flakes" <args>
```

`:z` is the SELinux relabel — the same class of problem as O-12's container
GPU failure, and the reason krump's justfile has it everywhere.

### Results of the first real evaluation, 2026-08-09

Run after the initial commit (flakes only see tracked files). Six real errors,
none of which `--parse` or `nixfmt` could have caught:

| Finding | Fix |
|---|---|
| **niri-flake's `niri-stable` AND `niri-unstable` both fail to evaluate** — `libdisplay-info_0_2` was removed from nixpkgs; the flake's package pin has drifted from ours | `programs.niri.package = pkgs.niri` in **both** `modules/niri.nix` and `home/niri.nix` |
| **niri options declared twice** — importing `niri.homeModules.niri` explicitly is *not* idempotent; the NixOS module pulls it in under a different key | import moved to the standalone `homeConfigurations` output only |
| `protonvpn-gui` renamed | → `proton-vpn` |
| `system.stateVersion` / `home.stateVersion` were `26.05` | → **`26.11`**, confirmed via `lib.trivial.release` |
| `nixfmt-rfc-style` deprecated | → `pkgs.nixfmt` |
| — | |

Current status of every output:

| Output | Evaluates |
|---|---|
| `homeConfigurations.stablefly` | ✅ — validates nixpak, the niri schema, all 5 sandboxes |
| `nixosConfigurations.laptop-vm` | ✅ — validates all 13 system modules |
| `nixosConfigurations.installer` | ✅ |
| `devShells`, `formatter` | ✅ |
| `nixosConfigurations.laptop` | ❌ **by design** — the `hardware-configuration.nix` placeholder throws |

`nix flake check` therefore fails, and will keep failing, until the hardware
file is generated on the ISO. That single throw is the only remaining failure.

Nothing has been *built* — these are `.drvPath` evaluations, which force full
module evaluation and catch every option and type error without downloading
Plasma, two compositors, the NVIDIA driver and three JetBrains IDEs.

### What this can and cannot check

| Check | Needs network | Status |
|---|---|---|
| `nix-instantiate --parse` on every file | no | ✅ all 19 files parse |
| `nixfmt --check` | first run only | ✅ clean, idempotent (nixfmt 1.4.0) |
| `nix flake lock` — do the inputs resolve? | yes | see below |
| `nix flake check` / `nixos-rebuild build` | yes | ❌ blocked on `hardware-configuration.nix`, which needs the ISO |

The last row is the real limit. Full evaluation cannot pass until the
hardware file is generated against the actual disks, because the placeholder
`throw`s by design. Everything short of that is checkable here, which is far
more than "nothing has been evaluated" implied.

### Seeding the install from the shared store

The `nix-store` podman volume (shared with `~/code/krump`) lives at
`~/.local/share/containers/storage/volumes/nix-store/_data`, i.e. on
`/dev/nvme1n1p3[/home]` — **the subvolume that carries over**. Anything built
into it from Bluefin is still there after the migration.

That makes the ordering matter:

```bash
just vm     # or just iso — realises the expensive outputs into the volume
```

Run *before* migrating, this populates the shared store with Hyprland, CUDA
torch, Plasma and the rest. Then `nixos-install` on the ISO can copy from it
instead of the network.

From the ISO, with the home subvolume mounted at `/mnt/home`:

```bash
mkdir -p /tmp/seed
mount --bind /mnt/home/stablefly/.local/share/containers/storage/volumes/nix-store/_data /tmp/seed
nixos-install --flake /etc/nixos#laptop \
  --option extra-substituters "local?root=/tmp/seed"
```

⚠️ **Untested.** The store URI form and the bind layout are the parts to
verify — `local?root=X` expects `X/nix/store`, and the volume's `_data` *is*
the `/nix` directory, so the bind may need an extra level. Check with
`nix path-info --store "local?root=/tmp/seed" <some-path>` before relying on
it.

This does **not** replace the substituters in `modules/caches.nix`: the store
answers "do I already have this", the substituters answer "where do I get it
if not". Right now the volume holds 22,349 paths of which 20,464 are `.drv` —
recipes, not outputs — because evaluation instantiates without realising.

### Formatting

`nixfmt` is the formatter (RFC 166 style). Re-run it after any edit:

```bash
nix run nixpkgs#nixfmt -- $(find . -name '*.nix')
```

Note it collapses blank lines between adjacent comment blocks, welding two
unrelated comments into one. Do not fight it with blank lines — they get
eaten. Comment conventions for this repo:

```nix
  # Prose block explaining one thing.
  #
  # ***
  #
  # Prose block explaining a different thing. `***` is the separator, inside
  # the comment, so nixfmt cannot collapse it away.

  ### one line, one comment
  ### another line, another comment
```

`***` separates block comments; `###` marks line-by-line annotation. Applied
so far in `home/niri.nix` and `modules/nvidia.nix`, which are the two places
distinct topics sit adjacent.

---

## 8b. What this flake produces besides one system

`hosts/laptop/default.nix` holds only what is portable; everything true of
*this physical machine* is in `hosts/laptop/machine.nix`. That split is what
makes the VM output possible, and it is the thing to preserve — if a VM build
starts failing on hardware specifics, something leaked out of `machine.nix`.

| Output | `just` target | Use |
|---|---|---|
| `nixosConfigurations.laptop` | `build` / `switch` | the real machine |
| `nixosConfigurations.laptop-vm` | `vm` | **boot the desktop with no disks** |
| `nixosConfigurations.installer` | `iso` | live installer ISO carrying this flake |
| `homeConfigurations.stablefly` | `home` | the `home/` half on any nix machine, incl. macOS |
| `devShells.default` | `shell` | nixfmt, nix-tree, just |
| `formatter` | `fmt` | `nix fmt` works |

`just verify` runs the two checks that work *before* the hardware file
exists: `parse` (offline, and the only one that also works without git) and
`fmt-check`. `just have <attr>...` answers "does this package exist" against
real nixpkgs; `just nix <args>` is a passthrough with the flags baked in.

Backup targets: `just restic_init <dest>` and `just restic_check <dest>` —
see §2.4.

### On the ISO

`installer` builds a genuine bootable live ISO — the standard NixOS installer
environment, plus this flake at `/etc/nixos` and git/helix/gptfdisk/btrfs-progs
preinstalled. It is **not** your configured desktop running live; it is a
minimal environment whose job is to install that desktop. Boot it and run
`nixos-install --flake /etc/nixos#laptop`.

The commented `isoImage.storeContents` line is the knob that would bake the
whole system closure onto the ISO for a network-free install. Left off on
purpose: with Plasma plus two compositors plus the NVIDIA driver, that closure
is large enough to need a sizeable USB stick, and it must be re-measured
before being switched on.

A live ISO of the *actual* desktop is possible too, but it is a different and
much heavier build, and the NVIDIA driver makes it awkward. Not attempted.

---

## 9. Install

```bash
nixos-install --flake /path/to/nixos-config#laptop
reboot
```

Then iterate:

```bash
sudo nixos-rebuild switch --flake .#laptop
```

Commit each working state. Test risky changes with
`nixos-rebuild build-vm --flake .#laptop` before switching bare metal —
graphics, suspend and power management are where the friction is, not the
CLI layer.

---

## 10. Cleanup — only after several confident days

```bash
mount -o subvolid=5 /dev/nvme1n1p3 /mnt/btrfs
btrfs subvolume delete /mnt/btrfs/root
btrfs subvolume delete /mnt/btrfs/var     # AFTER §2.1 inventory is acted on
```

Do not delete `var` until the flatpaks and container images recorded in
§2.1 have been either reinstalled or consciously abandoned.

Until this section runs, the Bluefin deploy tree is byte-for-byte intact
and recovery means restoring boot entries, not restoring data. `/home` is
never written to at any point in this procedure.

---

## 11. Open problems

### O-1 — RESOLVED: os-prober disabled, Windows via firmware picker

**Decided 2026-08-09: `useOSProber = false`.** Windows had not been booted in
about a year, so the trade is one F-key at POST once in a while against
invariant 1 holding with no exception at all — os-prober was the only thing in
this entire procedure that would have touched `nvme0n1`, and now nothing does.
It also removes a Windows-disk mount from every `nixos-rebuild`, and removes
the Fast Startup / dirty-NTFS failure mode below entirely.

Original reasoning, kept because it explains the GRUB choice:

`useOSProber = true` is what makes Windows appear in the menu at all.
systemd-boot cannot do it: it only launches EFI binaries from the ESP it
was installed to, or an XBOOTLDR partition on the same physical disk.
Windows' bootloader is on `nvme0n1`'s own ESP, so it is invisible to
systemd-boot. This is why GRUB was chosen.

The cost is that os-prober mounts `nvme0n1`'s partitions read-only on
every `nixos-rebuild`. This sits in tension with invariant 1. Two
alternatives if that is unacceptable:

- `useOSProber = false` plus the firmware boot picker. Zero contact with
  the Windows disk, costs an F-key at POST.
- A pinned `boot.loader.grub.extraEntries` block chainloading the Windows
  EFI path directly. Avoids the probe, goes stale if Windows relocates
  its bootloader.

Known wrinkle: if Windows has Fast Startup or hibernation enabled, its
NTFS volumes are left dirty and os-prober may fail to read them. Disable
Fast Startup from within Windows if the entry never appears.

### O-2 — ESP capacity vs `copyKernels`

The ESP is 599 MiB with 587 MiB free. `copyKernels = true` puts each
generation's kernel and initrd there, so `configurationLimit = N` budgets
587/N MiB per generation. The original `10` assumed ~58 MiB each, which the
earlier "10–15 generations" estimate does not actually support on a machine
carrying NVIDIA kernel modules in the initrd.

Set to **5** as a conservative start. This is still a guess, not a
measurement: after a handful of generations run `df -h /boot`, divide, and
raise it if there is room.

### O-3 — `nvme1n1p2` orphaned

The old ostree `/boot`, 192 MiB, unreferenced by NixOS. Leaving it costs
nothing. Removing it means editing the partition table on the disk NixOS
boots from — not worth doing during migration.

### O-4 — backlight device naming

`brightnessctl` autodetects, but on hybrid-graphics laptops it sometimes
picks the wrong class. If the keys do nothing, check
`brightnessctl --list` and pin with `-d <device>` in the keybinds.

### O-5 — declared config replaces shipped defaults

Originally about labwc's `rc.xml`. The hazard survived the compositor swap
unchanged, in two places:

- **niri/Hyprland keybinds.** Declaring `binds` (niri) or `bind` (Hyprland)
  replaces the default keymap wholesale. Neither config here defines a
  workspace switcher, screenshot key, or session exit. Diff against each
  project's shipped default config and merge back what you miss.
- **`programs.noctalia.settings`.** Left as `{ }` on purpose. noctalia has an
  in-app settings UI that round-trips its own config file; anything declared
  in Nix overrides that and the UI stops being able to persist changes.
  Configure through the UI first, move settings into Nix once they've
  settled — not before.

### O-6 — hybrid NVIDIA graphics, absent from the original plan

§5–§8 as first written contained no graphics configuration at all. The
machine is `bluefin-dx-nvidia`: Intel Iris Xe + RTX 4070 Laptop (AD106M,
Ada), driver 580.95.05. Without `hardware.nvidia.modesetting.enable`, a
wlroots-style compositor gets no usable DRM device and first boot is a
black screen.

`modules/nvidia.nix` now configures PRIME **offload** (`nvidia-offload <cmd>`
runs a program on the dGPU; everything else runs on Intel) with
`powerManagement.finegrained` so the 4070 can idle off. Open choices:

- `open = true` assumes the open kernel modules are fine on Ada. They should
  be, but if suspend/resume misbehaves, flip to `false` and retest.
- Offload vs `prime.sync` — sync gives every app the dGPU at the cost of
  battery and hotplug quirks. Offload is the right laptop default; revisit
  only if external displays are wired to the NVIDIA card.
- `finegrained` is only valid with offload. If you switch to sync, drop it.
- Not configured: `hardware.nvidia-container-toolkit.enable`. Needed before
  the CUDA container images can see the GPU — see §5 of
  `package-migration.md`.

### O-7 — podman survives, flatpak does not

`podman info` puts the image store at
`~/.local/share/containers/storage` — rootless, 96 GiB, on the `home`
subvolume. It carries over untouched, and `modules/containers.nix`
deliberately configures **rootless** podman only; enabling a rootful daemon
would create a second empty store under `/var`.

The 53 flatpaks are `system` scope, so they are on `var` and are lost at §10.
That is intended (see O-8), but it means §10's "AFTER §2.1 inventory is acted
on" applies to flatpaks specifically, not to containers.

**The files carrying over is not the same as the store working.** Rootless
overlay layers are chowned into the user's subuid/subgid range, and that
mapping lives in `/etc/subuid` / `/etc/subgid` — which §2.2 correctly says
does not survive. Measured on Bluefin:

```
stablefly:524288:65536      # both /etc/subuid and /etc/subgid
```

NixOS's `autoSubUidGidRange` allocates from 100000, so it would **not** match.
`hosts/laptop/default.nix` pins `subUidRanges`/`subGidRanges` to 524288/65536.
Without that pin, podman cannot read the existing store and recovering means a
`podman system migrate` chown pass over all 96 GiB. Verify after first boot
with `podman images` — the pre-migration list should come back unchanged.

### O-8 — four package channels collapse into one

Bluefin accumulated 196 homebrew formulae (26 explicit), 53 system flatpaks,
2 Gear Lever AppImages, 2 JetBrains Toolbox IDEs, 2 `uv` tools and 1
rpm-ostree layered package. All of it moves to nixpkgs; the mapping and the
"drop this" calls are in `package-migration.md`.

Consequences not yet reflected in the scaffold:

- `nixpkgs.config.allowUnfree = true` will be needed (NVIDIA driver alone
  forces it, before Obsidian/JetBrains/Vivaldi).
- `/home/linuxbrew` stays on disk after the migration and must be deleted by
  hand. Same for `~/AppImages/` and `~/.local/share/JetBrains/Toolbox/` —
  those binaries are FHS-linked and will not run on NixOS.
- The GNOME accessory apps assume services niri/Hyprland do not start
  (evolution-data-server, dconf, gnome-keyring). Do not bulk-install.

### O-9 — RESOLVED: there are no VMs

Measured 2026-08-10. The `libvirt` group membership and the hand-placed
`swtpm` override looked like TPM-backed VMs. They were a failed experiment —
nothing was ever created:

```
virsh -c qemu:///system  list --all   -> empty
virsh -c qemu:///session list --all   -> empty
systemctl is-active  libvirtd         -> inactive
systemctl is-enabled libvirtd         -> disabled
du -sh /var/lib/libvirt               -> 0
find ~ -name '*.qcow2' -o -name '*.vmdk' ... (>10M)  -> nothing
```

`~/.config/libvirt/qemu/{nvram,save,snapshot,...}` exists but is entirely
empty, and its mtime is the moment the probe above ran — `virsh` created the
skeleton itself. Not evidence of prior use.

**Consequences:**

- No `virtualisation.libvirtd` in the config. Nothing to migrate.
- Nothing at risk in §10 — `/var/lib/libvirt` is empty, so deleting the `var`
  subvolume loses nothing here.
- The `libvirt` group is vestigial and is deliberately absent from
  `users.users.stablefly.extraGroups`.
- The `swtpm` override on `var` — the one hand-placed file that made this
  whole thread worth checking — was presumably layered so Windows 11 guests
  could satisfy the TPM 2.0 requirement. It was never used. It goes with the
  subvolume.

This closes the last unknown on `var`. Everything there is now accounted for:
18 GiB system flatpaks (all dropped), 4.1 GiB logs, the ostree deploy tree,
the swtpm override, and an empty libvirt skeleton. **Nothing on `var` is being
carried forward.**

### O-10 — which GPU the compositor renders on — **MEASURED, not open**

Measured on the running Bluefin system, which is configured correctly today:

```
card0 -> 0000:00:02.0  driver=i915     renderD128
card1 -> 0000:01:00.0  driver=nvidia   renderD129

card0-eDP-1      connected     3840x2400   <- laptop panel, on Intel
card1-HDMI-A-1   connected     3840x2160   <- LG Ultra HD, ON THE NVIDIA GPU
card0-DP-1..4    disconnected                 (Intel, likely USB-C DP-alt)
card1-DP-5,6     disconnected                 (NVIDIA)
```

**The HDMI port is wired to the 4070, and an external 4K display is on it.**
So the niri#3674 cross-GPU stutter is not a hypothetical for this laptop — it
is the default behaviour. `home/niri.nix` now sets:

```
debug { render-drm-device "/dev/dri/by-path/pci-0000:01:00.0-render" }
```

by-path rather than `renderD129`: the `renderD*` numbering is not guaranteed
stable across boots, the by-path symlink is.

Display layout, transcribed from `~/.config/monitors.xml` into both
`home/niri.nix` and `home/hyprland.nix`:

| Output | Mode | Scale | Logical size | Position |
|---|---|---|---|---|
| `HDMI-A-1` (NVIDIA) | 3840x2160@60 | 2 | 1920x1080 | 0,0 — primary |
| `eDP-1` (Intel) | 3840x2400@60 | 2 | 1920x1200 | 0,1080 |

External above internal. GNOME names the external `HDMI-1`; the DRM connector
name both compositors want is `HDMI-A-1`.

### O-10a — `prime.offload` is questionable now that the display wiring is known

`modules/nvidia.nix` configures PRIME **offload** with
`powerManagement.finegrained = true`, chosen when nobody knew where the
external port went. That reasoning no longer holds cleanly:

- The dGPU currently reads `runtime_status: active` and cannot suspend while
  the LG is attached — its display engine is in use. `finegrained` therefore
  buys nothing whenever the laptop is docked.
- Offload means the compositor renders on Intel and the NVIDIA card is only a
  display sink for its own output. That is the stuttering path, which is
  exactly why O-10's `render-drm-device` override is needed.

Options, in order of how much they change:

1. **Leave as-is** (offload + `render-drm-device`). niri renders on the 4070,
   which fixes the external display but keeps the dGPU awake — so undocked
   battery life gets worse than Bluefin's. Hyprland has no equivalent knob
   configured, so its behaviour here is untested.
2. **`prime.sync = true`** instead of offload. Everything renders on the
   4070, Intel just drives eDP. Best for a permanently-docked dual-4K
   workflow, worst for battery, and `finegrained` must be dropped — it is
   only valid with offload.
3. **Keep plain offload, drop the override.** Best battery undocked, accept
   the stutter when docked.

**Decided: option 3 — plain offload, no render override.**

The laptop is docked most of the time, which initially argued for option 1.
It got overtaken by a better question: can the dGPU just follow the monitor?

It can, and that is what option 3 already does. With no render device pinned,
niri renders on the Intel iGPU and the 4070 is powered only when something
actually needs it — a display attached to it, or an app launched through
`nvidia-offload`. `powerManagement.finegrained` runtime-suspends it the rest
of the time. Plug the monitor in, the dGPU comes up because its display
engine is needed; unplug, it suspends. No configuration, no switching, no
session restart.

What is *not* possible is changing the render device dynamically. niri picks
it at compositor startup, as do KWin (`KWIN_DRM_DEVICES`) and Hyprland
(`AQ_DRM_DEVICES`); a dock event cannot flip it without restarting the
session and losing every window. So a "render on Intel undocked, NVIDIA
docked" scheme is not on the table — which is fine, because option 3 gets the
power behaviour without needing it.

The remaining risk is the cross-GPU copy for the external display
(niri#3674). Mitigating it: GNOME does the same copy today and is smooth
(measured below). If niri turns out not to be, uncommenting one line in
`home/niri.nix` restores option 1 — at the cost of the automatic power
behaviour, permanently.

#### No compositor does per-output rendering — this is not a niri weakness

Worth recording, because it is easy to assume the current GNOME setup is
doing something cleverer than it is. It isn't. Every compositor here
composites on **one** GPU and copies to displays attached to the other:

| Compositor | Renders on | Knob to change it |
|---|---|---|
| mutter (GNOME) | primary GPU | udev tag `mutter-device-preferred-primary`; `MUTTER_DEBUG_MULTI_GPU_FORCE_COPY_MODE` picks the copy path |
| KWin (Plasma) | iGPU | `KWIN_DRM_DEVICES` |
| niri | one GPU | `debug { render-drm-device }` |
| Hyprland | one GPU | `AQ_DRM_DEVICES` |
| cosmic-comp | one GPU | improving; hybrid NVIDIA still reported rough |

[mutter's own docs](https://github.com/GNOME/mutter/blob/main/doc/multi-gpu.md)
spell this out: it composites for all displays on the primary GPU and copies
to secondaries, with three selectable copy modes. KWin behaves the same way
and multi-GPU output support is
[still an open work item](https://invent.kde.org/plasma/kwin/-/work_items/13).

**Measured on this machine:** there is no `mutter-device-preferred-primary`
udev tag and no GPU-selection env var anywhere in `/etc`. So GNOME is
currently rendering on the **Intel** iGPU and copying every frame to the 4070
for the LG — the exact arrangement predicted to stutter — and it is smooth.

Two things follow. First, cross-GPU copy is not inherently broken on this
hardware; mutter's copy path is simply well tuned, and niri#3674 is about
niri's being less so. Second, **option 3 (plain offload, no override) may
well be fine** and is worth one A/B test on first boot before accepting the
battery cost of options 1 and 2. Do not treat the override as proven — treat
it as the safe default for a docked machine.

### O-10b — background, and the Hyprland side

Distinct from O-6, which is about the driver. O-10 is about the compositor
picking a DRM device on a hybrid box.

Upstream closed the niri issue
([niri#3674](https://github.com/niri-wm/niri/issues/3674)) but
`render-drm-device` remains undocumented, so it is worth knowing the option
exists at all — it lives in the `debug` block and nothing signals that it
addresses monitor stutter.

Hyprland asks more here: its NVIDIA page is a page of environment variables
and kernel parameters. `modules/hyprland.nix` sets only `NIXOS_OZONE_WL`,
which is a starting point, not a verified working set, and it has **no
equivalent of niri's `render-drm-device`** configured — so the docked
external display is the first thing to check in that session. If Hyprland
misbehaves and niri does not, this is the difference; do not conclude the
driver config in `modules/nvidia.nix` is wrong.

### O-12 — CUDA under PRIME offload (whisperx RESOLVED)

O-10a's power argument only holds if compute still works when the dGPU is
asleep. It does, but two details are easy to get wrong.

**CUDA needs no wrapper.** `nvidia-offload` is a *graphics* shim — it sets
`__NV_PRIME_RENDER_OFFLOAD` and `__GLX_VENDOR_LIBRARY_NAME` so GL/Vulkan
select the dGPU. CUDA does not go through GLX. A CUDA process opens the
driver directly and runtime PM resumes the suspended GPU on device open, so
`nvidia-smi`, PyTorch and the rest run unprefixed. Undocked, the only cost is
a wake latency on the first call; docked, the GPU is already up because the
LG is on it, so there is none.

**Anything that polls `nvidia-smi` defeats option 3.** Every call wakes the
GPU. A GPU-usage widget in the noctalia bar, or a monitoring loop, will keep
the 4070 out of D3cold permanently and quietly undo the reason O-10a chose
plain offload. If undocked battery life looks wrong, check for a poller
before touching the graphics config.

**Containers need the toolkit, now enabled.** The 55 GiB of CUDA images
(`nvcr.io/nvidia/pytorch` 22 GB, `sglang` 19.7 GB, `vllm` 10.5 GB) carry over
on the `home` subvolume (O-7) but cannot see the GPU without
`hardware.nvidia-container-toolkit.enable = true`, which was missing until
now. It generates `/var/run/cdi/nvidia-container-toolkit.json`; podman
consumes it as:

```bash
podman run --device nvidia.com/gpu=all ...
```

CDI is specifically what makes this work under **rootless** podman, which is
the only kind configured here.

⚠️ Known breakage to watch for: nvidia-container-toolkit **1.17.8** on
nixos-unstable fails with `unresolvable CDI devices nvidia.com/gpu=all`
([nixpkgs#420638](https://github.com/NixOS/nixpkgs/issues/420638)); 1.17.6
works. If the first GPU container fails with exactly that message, it is this
and not the driver.

#### SELinux blocks GPU containers on the Bluefin side — measured 2026-08-08

Measured on the running system, not inferred. Not the toolkit, not the
images, not ostree — **SELinux labelling**.

```bash
podman run --rm --device nvidia.com/gpu=all \
  docker.io/nvidia/cuda:12.3.0-base-ubuntu22.04 nvidia-smi
# -> Failed to initialize NVML: Insufficient Permissions

podman run --rm --security-opt=label=disable --device nvidia.com/gpu=all \
  docker.io/nvidia/cuda:12.3.0-base-ubuntu22.04 nvidia-smi
# -> full output, RTX 4070, driver 580.95.05, CUDA 13.0
```

Bluefin inherits Fedora's SELinux policy and runs `Enforcing`. Rootless
podman plus the NVIDIA device nodes trips the container labelling rules, and
the resulting error names permissions without naming SELinux — which is why
it reads as "CUDA is broken" rather than "add one flag".

**NixOS does not enable SELinux by default**, so this specific failure should
simply not occur and no flag should be needed. Verify with the same
`nvidia-smi` invocation *without* `--security-opt` after the migration; if it
still fails, the cause is the toolkit version trap above, not labelling.

Consequence for §10: whatever their history, the images respond correctly to
the flag today. Do not discard them before re-testing on NixOS.

#### RESOLVED 2026-08-10 — whisperx runs on the GPU

`pkgs.whisperx` links a CPU-only torch. Fixed by instantiating a **second**
nixpkgs with `cudaSupport = true` and taking whisperx from it
(`home/cli.nix`), rather than turning cudaSupport on globally.

Three things made this cheap, all measured rather than assumed:

| Path | In `cache.nixos-cuda.org`? |
|---|---|
| `python3.14-whisperx-3.8.6` | ✅ 200 |
| `ctranslate2-4.8.1` (CUDA) | ✅ 200 |
| `python3.14-torch-2.12.0` (CUDA) | ✅ 200 |

So the whole chain is a download, not a build — torch alone is 215 MB, and
compiling it locally would have been hours. `modules/cuda.nix` adds the
substituter and key.

⚠️ **The cache moved.** `cuda-maintainers.cachix.org` 404s for current paths;
`cache.nixos-cuda.org` is live. Key:
`cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M=`

Two deliberate non-choices, both about preserving cache hits:

- **No global `cudaSupport`.** It would rebuild ffmpeg, opencv and everything
  else carrying the flag — mostly *not* in the CUDA cache — to accelerate one
  program.
- **No `cudaCapabilities = [ "8.9" ]`** despite the 4070 being Ada. Narrowing
  it would cut build size but changes every derivation hash, turning every
  cache hit into a local build. The defaults are what the cache holds.

Verify on first boot:

```bash
python -c 'import torch; print(torch.cuda.is_available())'
whisperx --device cuda <file>
```

Undocked, the first call wakes the dGPU and it suspends again afterwards —
that is O-10a working, not a fault.

Still not configured globally: `nixpkgs.config.cudaSupport`. It rebuilds a large part of the
package set against CUDA and is only worth it for host-native CUDA Python.
The container path above avoids needing it.

### O-11 — HDR is enabled today and is not carried over

`~/.config/monitors.xml` sets `<colormode>bt2100</colormode>` on `eDP-1`:
the internal panel is running HDR under GNOME right now. Neither
`home/niri.nix` nor `home/hyprland.nix` configures HDR, so **the first boot
into either session is an SDR regression on a panel that currently does
better**.

Both projects have HDR support at varying maturity (Hyprland via its colour
management protocol, niri more recently). Neither is configured here because
neither was verified. If the panel looks washed out or dim after migrating,
this is why — not the driver.


### O-13 — RESOLVED: nix-ld enabled for uv

Dev environments are **expected to be rebuilt, not migrated** — decided, not
a problem. `uv.lock` is in git, `uv sync` recreates venvs, ~15 minutes per
project. The seven `pyvenv.cfg` files under `~/code` are directories to
delete, not state to carry.

The one part that is not free: uv ships python-build-standalone interpreters,
and they always request an FHS loader.

```
$ readelf -l ~/.local/share/uv/python/cpython-3.13.1-*/bin/python3.13
  [Requesting program interpreter: /lib64/ld-linux-x86-64.so.2]
```

NixOS has no such path, so a **freshly downloaded** uv Python will not run
either — deleting the old interpreters does not avoid this. **Now set**, in
`modules/nix-ld.nix`, with a starter `libraries` list covering what native
Python wheels reach for most often:

```nix
programs.nix-ld.enable = true;
```

The `libraries` list is the part that takes iteration — run the thing, read
`libfoo.so.N: cannot open shared object file`, add the package that ships it.
`nix-index` is the tool for that lookup.

The alternative is pointing uv at a nixpkgs interpreter, which gives up uv's
Python version management. `nix-ld` was previously noted only as a JetBrains
Toolbox workaround; Toolbox has since been dropped, so uv is now the reason
it earns its place.

Two pre-existing oddities found while checking, unrelated to the migration:
`harper/back`'s venv points at `/opt/homebrew/opt/python@3.11/bin` (a macOS
path — already dead), and `cyclone`'s was built under `sudo` against root's
uv.

---

## 12. Handoff

### Invariants for anyone working in this repo

- `nvme0n1` is never a target of any command. Windows lives there.
- `fileSystems."/home"` mounts an existing subvolume. It is never
  formatted, never `mkfs`'d, and no disko or partitioning tooling belongs
  in this flake.
- `system.stateVersion` and `home.stateVersion` are historical markers.
  Never bump them.
- The user is `stablefly`, uid/gid 1000, both pinned. Do not let NixOS
  allocate them.
- nixpkgs is the only package channel. No flatpak, no homebrew, no AppImages.

### Tasks

Done on the Bluefin side (2026-08-07):

- [x] Scaffold the tree in §4 — files exist at the repo root
- [x] Fill the two UUIDs in `hosts/laptop/filesystems.nix`
- [x] Confirm `time.timeZone` → `America/New_York`
- [x] §2.1 inventory captured into `~/migration-notes/`
- [x] Recorded `/etc/subuid` + `/etc/subgid` (`stablefly:524288:65536`) and
      pinned them — only capturable while Bluefin boots
- [x] Package triage written up in `package-migration.md`
- [x] `nixpkgs.config.allowUnfree = true` — the NVIDIA driver forces it

**For you to run, not the agent:**

- [x] `git add -A` — repo is clean/fully tracked as of 2026-08-14
      (`git status --short` empty). Still re-run after every new file **or
      new flake input** — a new input is the least obvious trigger, and it
      changes `flake.lock`.

Machine has booted for real since; these are no longer blocked:

- [x] Generate `hardware-configuration.nix` with `--no-filesystems` and
      replace the placeholder — done, file has zero `fileSystems.*` blocks
- [x] `just vm` / `just iso` — moot now that the real machine is running
- [x] `initialPassword = "changeme"` — **by design, not outstanding.** The
      literal value is the point: it forces a `passwd` run on first login
      rather than shipping a real password in `/nix/store` (world-readable).
      `passwd` has been run. Nothing to change in the file.
- [ ] **`modules/backup.nix`'s `repository` needs a rethink, not a fill-in.**
      Decided 2026-08-14: backups go to SD cards carried off-machine, not
      SFTP/S3/rclone — cheap, fast, physically separate from the laptop. That
      doesn't fit the module as written: it's built around a daily systemd
      timer, and a removable-drive target makes that timer fail every time
      the card isn't inserted (the module's own comment already flags this).
      The other open question is a safety check: before writing, confirm the
      inserted card is *the* backup card and not some random SD/microSD —
      idea on the table is a signature file written to the card at init time,
      checked before every backup, refuse if absent.

      **Trigger design, decided 2026-08-14:** a systemd timer, not manual —
      fired during idle time (the intent is it fires while away from the
      machine, e.g. a gym or coffee break) rather than on a fixed calendar
      slot. On each fire:
      - Card present + signature valid → run the backup. Expected to be
        quick (restic is incremental after the first run) — budget "a long
        coffee break, at most," so the unit should have a timeout well under
        that and something should notice if a run runs long, not just silently
        let it ride.
      - Card absent, or present without a valid signature → **don't fail
        silently.** Raise a desktop notification reminding the user the
        backup card isn't in the machine. This is the actual point of the
        signature check: it's not just refusing to write to the wrong drive,
        it's the trigger for the "you forgot the card" reminder.

      Needs, technically: an idle-detection condition (systemd-logind idle
      state, or noctalia's own idle/lock handling if it exposes one — not
      yet checked which this desktop already has), a notification path from a
      *system* service to the user's session (a system-level
      `services.restic` unit doesn't have a desktop session to notify by
      default — needs `notify-send` routed to the user's D-Bus session, or
      running the check as a user-level systemd unit instead of system-level
      so it inherits the session bus for free), and a run-time budget/timeout
      on the backup step itself.

      **Not implementing this in the nix-config repo yet.** Plan as of
      2026-08-14: write the signature-check tool as a small standalone Go
      executable, in a separate repo, as a Go-learning project — then pull
      it in here the way `pkgs/ant-cli.nix` pulls in Anthropic's `ant` CLI
      (fetch the source, `buildGoModule`, wire it into `home/cli.nix` or a
      new `just` recipe). Until that exists, `modules/backup.nix` stays as
      the SFTP-shaped placeholder it is today — do not build a Nix-native
      version of the signature check as a substitute.
- [ ] **Point Obsidian's sandbox at the real vault.** `~/Documents/obsidian_vault`
      still exists only as the empty placeholder (`home/gui.nix` creates it
      with a `.keep`) — no vault has been dropped in as of 2026-08-14.
- [ ] Resolve O-1 through O-13 as they surface on real hardware — most are
      marked RESOLVED in §11 already; O-11 (HDR) is the one still genuinely
      open, see checklist below.

Done and verified (2026-08-09/10):

- [x] `flake lock` — all 5 inputs resolve
- [x] `homeConfigurations`, `laptop-vm`, `installer`, `devShells`, `formatter`
      all evaluate
- [x] 105 package attribute names verified; 7 were wrong, all corrected
- [x] `system.stateVersion` = `26.11`, measured not guessed
- [x] nix-ld enabled (O-13); whisperx on GPU (O-12); os-prober off (O-1);
      libvirt confirmed unused (O-9)

---

## Checklist

Re-verified against the live system 2026-08-14 (machine has been running
NixOS for days — this is no longer a pre-install checklist, it's a status
check). One naming note first: **the `nvme0n1`/`nvme1n1` labels below are
not stable across boots** — NVMe controller enumeration order can flip them,
which is exactly why `filesystems.nix` mounts by UUID rather than device
path. Seeing the live root on a different `nvmeXn1` than this doc recorded
during migration is expected, not a violation of invariant 1 — trust the UUID,
not the number.

- [x] `btrfs subvolume list` recorded — exactly `root`, `var`, `home`
- [x] `var` contents inventoried (flatpaks, overrides) — `~/migration-notes/`
- [x] Confirmed podman's 96 GiB store is on `home`, not `var`
- [x] btrfs UUID recorded — `6f8449a5-f6b6-4f60-adb1-c9b6c58cac3a`
- [x] ESP UUID recorded — `49A3-D385`
- [ ] `efibootmgr -v` confirms the ESP in boot order — not independently
      re-verified 2026-08-14 (`efibootmgr` isn't on `PATH` in a normal shell,
      needs root); `/boot/efi` is mounted and the machine boots, which is
      strong indirect evidence, but nobody has run the actual command
- [ ] **Irreplaceable data exists off this disk** — still outstanding, now
      blocked on the SD-card backup redesign above rather than a placeholder
      fill-in. Still the one genuinely irreversible-if-skipped item in the
      whole procedure.
- [x] Windows disk never mounted or written — confirmed 2026-08-14: only one
      physical disk's partitions appear in `mount` output (root/nix/home/boot
      all resolve to the same UUID-identified disk); the other NVMe drive is
      untouched
- [x] `nixos` subvolume created — confirmed, root is mounted `subvol=/nixos`
- [x] `hardware-configuration.nix` carries no `fileSystems` — confirmed, zero
      `fileSystems.*` blocks in the file
- [x] Repo is a git repo with everything staged — confirmed, `git status`
      clean 2026-08-14
- [x] Flake evaluates — 4 of 5 outputs clean as of the last full check (not
      re-run this session per standing preference not to run `just check`
      unprompted)
- [ ] `whisperx --device cuda` actually uses the GPU (O-12) — not re-tested
      this session; config (`hardware.nvidia-container-toolkit.enable`,
      `cudaPkgs.whisperx` in `home/cli.nix`) is in place
- [ ] `programs.nix-ld` lets a uv-managed python run (O-13) — `nix-ld` is
      enabled and `uv python list` runs fine under it, but the 2026-08-14
      cleanup deleted the old uv-downloaded interpreters
      (`~/.local/share/uv/python`) along with the stale `uv` binary itself,
      so this specifically needs a fresh `uv python install` test, not just
      re-reading the old result
- [x] Printing works (CUPS + avahi) — both services confirmed `active`
      2026-08-14; scanning (SANE) not independently tested this session
- [x] Install completed, first boot reached — machine has been the daily
      driver for days (per `CLAUDE.md`)
- [x] `/home/stablefly` contents verified present and owned by uid 1000 —
      confirmed 2026-08-14
- [ ] Windows boots via the FIRMWARE PICKER (no GRUB entry by design — O-1) —
      config matches design (`useOSProber = false`), actually booting into
      Windows to confirm is a physical test nobody's run
- [x] External port wiring measured — HDMI-A-1 is on the NVIDIA GPU (O-10)
- [ ] Both displays come up at 3840x2400 / 3840x2160, scale 2, external above
      — needs a docked visual check
- [ ] External display does not stutter with NO render override (O-10a). If
      it does, uncomment `debug.render-drm-device` in `home/niri.nix`
- [x] dGPU suspends when undocked — confirmed 2026-08-14:
      `/sys/bus/pci/devices/0000:01:00.0/power/runtime_status` reads
      `suspended` right now (machine currently undocked)
- [ ] **tuigreet/ReGreet lists THREE sessions: niri, Hyprland, Plasma** —
      unexercised, not investigated further by choice: no code has been
      written yet on this machine that isn't niri/Hyprland exploration, so
      Plasma-as-fallback has never actually been logged into. It's expected
      to just work when needed; the missing `plasma.desktop` in
      `/run/current-system/sw/share/wayland-sessions/` noted 2026-08-14 is
      worth a look *if and when* Plasma is actually needed as a fallback,
      not before.
- [ ] noctalia's bar appears in each session (if not: check it is spawned by
      the compositor, not systemd — §7a)
- [x] zram active — confirmed 2026-08-14 (`zramctl`: 15.5G zstd swap).
      Audio and the media/brightness keys are not independently re-verified
      this session.
- [ ] `nvidia-offload glxinfo` runs on the dGPU; suspend/resume survives —
      not re-tested this session (would wake the dGPU for no reason right now)
- [ ] `podman run --device nvidia.com/gpu=all ... nvidia-smi` works rootless
      (O-12; if it says "unresolvable CDI devices", it's the 1.17.8 bug) —
      not re-tested this session
- [x] Rootless `podman images` still lists the pre-migration images — subuid
      pin confirmed correct (`524288:65536` in both `/etc/subuid` and
      `/etc/subgid`), and `podman images` returns 43 images against the
      44 recorded pre-migration — consistent with the pin working
- [x] `/home/linuxbrew`, `~/AppImages`, JetBrains Toolbox removed — done
      2026-08-14, see `package-migration.md` §4 for the full list (it grew
      well past the original three items)
- [ ] Old `root` and `var` subvolumes deleted — **deliberately not deleted
      yet.** Explicitly gated on the SD-card backup being working, not on
      agent verification — deleting these two is the actual point of no
      return for the old Bluefin data, and that shouldn't happen before a
      real off-machine backup exists. Revisit once the backup redesign above
      lands. (Unrelated to `/home/linuxbrew`'s leftover empty directory
      entry — that one holds no data and is safe to clear any time with
      `sudo rmdir /home/linuxbrew`.)
