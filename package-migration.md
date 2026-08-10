# Package migration — Bluefin channels → nixpkgs

Companion to `bluefin-to-nixos-migration.md`. **Nothing here is installed
yet.** This is a triage list for review.

Decision on record: **no flatpak, no homebrew, no AppImages on NixOS.**
nixpkgs is the single source per binary.

> ✅ **Attribute names verified 2026-08-09** against real nixpkgs-unstable,
> via the nix container (`just have <attr>...`). 105 candidates checked; the
> seven that were wrong are corrected inline below and called out in §0.
> Raw inventory: `~/migration-notes/`.

---

## 0. What the verification pass found

`just have <attrs>` evaluates each candidate against nixpkgs-unstable and
reports ok / MISSING / THROWS. Seven of 105 were wrong:

| Was | Is | Note |
|---|---|---|
| `greetd.tuigreet` | **`tuigreet`** | ⚠️ was in `modules/desktop.nix` — a broken greeter means no login at all, on any of the three sessions. Fixed |
| `jetbrains.idea-ultimate` | **`jetbrains.idea`** | JetBrains merged Community/Ultimate into one distribution; activate with your licence |
| `jetbrains.idea-community` | — | removed upstream for the same reason |
| `jetbrains.rubymine` | **`jetbrains.ruby-mine`** | hyphenated |
| `qflipper` | **`qFlipper`** | capital F |
| `stremio` | **`stremio-linux-shell`** | removed 2026-02-11 — depended on vulnerable qt5 webengine |
| `elixir` | **`beamPackages.elixir`** | top-level still works but warns; deprecated |

Everything else resolved. `niri-stable` and the nixpak wrappers come from
flake inputs rather than nixpkgs, so they are not in this count and remain
unverified until the flake locks.

---

## The sorting rule

Three buckets, because the bucket decides **where the package goes**, not
just what it is:

| Bucket | What it means | Where it lands |
|---|---|---|
| **User tools** | You'd want it on a machine you never wrote code on | `home/cli.nix`, `home/gui.nix` |
| **Dev tools** | Language-agnostic. You want it on `PATH` in every project | `home/dev.nix` |
| **Toolchains** | Compilers, runtimes, libraries. Version matters *per project* | **Not installed globally** — `devShells` |

The third line is the one that pays. A globally-installed Elixir or Node is
what makes two projects fight, and it's exactly what `devShells` + `direnv`
exist to replace. Everything in §3 should leave the global profile even
though it's on this machine today.

Inventory totals: 196 brew formulae (26 explicit), 53 system flatpaks, 2
AppImages, 2 JetBrains IDEs, 2 `uv` tools, 1 rpm-ostree layered package.

---

## 1. User tools

### 1a. CLI — → `home/cli.nix`

| Current | nixpkgs candidate | Notes |
|---|---|---|
| bat | `bat` | ✅ installed, 0.26.1 |
| eza | `eza` | ✅ installed via HM module |
| fd | `fd` | ✅ installed, 10.4.2 |
| ripgrep | `ripgrep` | ✅ installed, 15.2.0 |
| ugrep | `ugrep` | ✅ installed, 7.8.2 |
| dysk | `dysk` | ✅ installed, 3.6.1 |
| tealdeer | `tealdeer` | ✅ installed, 1.8.1 |
| television | `television` | ✅ installed, 0.15.9 |
| starship | `starship` | ✅ installed via HM module |
| glow | `glow` | ✅ installed |
| vim | `vim` | ✅ installed |
| nushell | `nushell` | ✅ installed, 0.114.1 — extra shell, login shell stays fish |

### 1b. GUI — **inventory, not a plan**

⚠️ **Default is DROP.** These 53 flatpaks are on the machine because Bluefin
makes flatpak the default install path, not because they were chosen. Most of
them have never been knowingly used. Nothing in this section gets installed
unless it is explicitly marked as wanted.

Read the table below as "here is what was on the old machine," and mark the
handful that are actually used. The nixpkgs column is only there so that
marking one is a one-step decision.


**Browsers & comms**

| Current | nixpkgs candidate |
|---|---|
| Brave | `brave` |
| Vivaldi | `vivaldi` (unfree) |
| Firefox | `firefox` |
| Thunderbird ESR | `thunderbird` |
| Signal | `signal-desktop` |
| Telegram | `telegram-desktop` |
| ProtonVPN | `protonvpn-gui` |
| Bitwarden *(AppImage)* | ✅ `bitwarden-desktop` 2026.7.0 — installed, unsandboxed (native messaging) |

⚠️ Four browsers. Also: the `WebApp-*.desktop` entries (gmail, Proton, Amazon,
Simplelogin) are Bluefin's browser-webapp shim with no NixOS equivalent —
they're bookmarks with icons. Recreate by hand or drop.

**Media & graphics**

✅ **VLC** `vlc` 3.0.23-2 — installed, unsandboxed (plays files from anywhere).
✅ **Stremio** `stremio-linux-shell` 1.1.4 — installed, **sandboxed**.
✅ **OBS Studio** — installed, see `modules/obs.nix`.

Not installed: `clapper`, `pinta`, `loupe`.

**Documents & office**

| Current | nixpkgs candidate |
|---|---|
| LibreOffice | `libreoffice-fresh` |
| Obsidian | `obsidian` (unfree) |
| Okular | `kdePackages.okular` |
| Papers | `papers` |
| GNOME Text Editor | `gnome-text-editor` |
| FocusWriter | `focuswriter` |
| GnuCash | `gnucash` |
| InvoiceNinja | ❌ not in nixpkgs — self-hosted web app, and you already have `localhost/invoiceninja` images. Run it from podman |

**Hardware & system**

| Current | nixpkgs candidate |
|---|---|
| PrusaSlicer | ✅ `prusa-slicer` 2.9.6 — installed |
| rpi-imager | `rpi-imager` |
| Impression | `impression` |
| GNOME Firmware | `gnome-firmware` (needs `services.fwupd.enable`) |
| Baobab | `baobab` |
| GNOME Logs | `gnome-logs` |
| Déjà Dup | `deja-dup` |
| qFlipper *(AppImage)* | **`qFlipper`** (capital F) — needs `dialout`, already in `extraGroups` |
| Zenmap | `zenmap` (7.99) — verified, exists |
| DistroShelf | `distroshelf` (1.4.8) — verified, exists |

**Scanning & OCR**

✅ **Skanpage** `kdePackages.skanpage` 26.04.3 — installed, with SANE wired up
in `modules/scanning.nix`.

Not installed: `simple-scan`, `ocrfeeder` — both exist, neither requested.

✅ Done: `hardware.sane.enable`, the `sane-airscan` backend for driverless
eSCL/WSD scanners, and `scanner`/`lp` in `extraGroups`. Group changes need a
fresh login, not just a rebuild.

**GNOME accessories**

`Calculator`→`gnome-calculator`, `Calendar`→`gnome-calendar`,
`Characters`→`gnome-characters`, `Clocks`→`gnome-clocks`,
`Contacts`→`gnome-contacts`, `Connections`→`gnome-connections`,
`File Roller`→`file-roller`, `Font Viewer`→`gnome-font-viewer`,
`Maps`→`gnome-maps`, `Nautilus Previewer`→`sushi`, `Weather`→`gnome-weather`

⚠️ These assume GNOME services that niri and Hyprland do not start.
Calendar/Contacts want `services.gnome.evolution-data-server` +
`programs.dconf.enable`; most want `gnome-keyring` and an XDG portal. The
Plasma session (`modules/plasma.nix`) brings KDE equivalents instead. Decide
the desktop before landing these — don't bulk-install and hope.

---

## 1c. Sandboxing — nixpak shortlist

Nix isolates at **build** time and does essentially nothing at **run** time.
A nixpkgs browser reads `~/.ssh`, `~/.aws`, and every git repo you own, same
as on any distro. [nixpak](https://github.com/nixpak/nixpak) closes that gap:
declarative bubblewrap wrapping with portals and `xdg-dbus-proxy` — flatpak's
security model, defined in the flake.

**Be precise about what this buys.** Browsers already sandbox themselves —
site isolation protects *the browser* from *the web*. nixpak protects *your
filesystem* from *the browser*. Different threat, and the one nix leaves open.

### Tier 1 — ✅ DONE, in `home/gui.nix`

Confirmed in extensive use, so these are wrapped and installed:

| App | nixpkgs | Network | Filesystem it can see |
|---|---|---|---|
| Obsidian | `obsidian` | yes | `~/Documents`, `~/.config/obsidian` |
| Signal | `signal-desktop` | yes | `~/.config/Signal`, `~/Downloads` |
| Telegram | `telegram-desktop` | yes | `~/.local/share/TelegramDesktop`, `~/Downloads` |
| Okular | `kdePackages.okular` | **no** | `~/Documents`, `~/Downloads`, its docdata + rc files |
| LibreOffice | `libreoffice-fresh` | **no** | `~/Documents`, `~/Downloads` |

Nothing else from `$HOME` — no `~/.ssh`, no `~/code`, no `~/.aws`.

⚠️ **Obsidian's vault path is a guess** (`~/Documents`). If the vault lives
elsewhere, add it to `rw` in `home/gui.nix` or Obsidian opens to an empty
picker.

**Okular is the strongest case in the file.** Untrusted PDFs from libgen go
into poppler — a large C++ parser with a long CVE history. No network means a
successful exploit has nowhere to phone home and nothing to exfiltrate to, and
it also kills PDFs that fetch remote content or run embedded JS on their own.

⚠️ **Printing will break.** CUPS is reached over a socket the sandbox cuts. If
you print from Okular, that needs a hole punched for it.

Papers was also "dunno" — not installed, and Okular covers PDFs anyway.

### Tier 2 — installed, NOT sandboxed

Brave, Vivaldi and Firefox are installed from nixpkgs the ordinary way in
`home/gui.nix`. They keep full access to `$HOME`, exactly as on any other
distro. Sandboxing them is parked — a working system and getting back to
coding come first.

Being precise about what that costs: all three still run their own internal
sandbox (site isolation), which protects *the browser* from *the web*. What
is absent is the outer cage that would protect `~/.ssh` and `~/code` from
*the browser*. That is the gap, and it is a deliberate one.

Upside of deferring: the throwaway Brave conferencing profile needs camera,
mic and screenshare, which was the hardest thing in this whole section to get
through a sandbox. Unsandboxed it is just the normal portal path and should
work out of the box.

Thunderbird is not installed — it was never confirmed as used.

| App | Why | What will fight you |
|---|---|---|
| **Brave** | primary browser, incl. the throwaway conferencing profile | GPU access, **camera/mic/screenshare via pipewire portal**, native messaging (Bitwarden extension ↔ desktop app) |
| Firefox | secondary | same, minus conferencing |
| Thunderbird | attachments are untrusted input | needs a downloads dir; native messaging |

The conferencing profile is the hardest case in the whole list: camera, mic
and screen capture are exactly what a sandbox exists to block, and getting
them through cleanly is portal work. Do Brave *last*, after the model is
familiar — not first because it is the most interesting.

### Tier 3 — do not sandbox

The sandbox fights the purpose. These need raw hardware or system-wide
capture:

- **OBS** — screen capture, camera, virtual devices
- **qFlipper, rpi-imager, Impression** — raw USB / block devices
- **PrusaSlicer** — USB to the printer, plus GPU
- **anything CLI** — different threat model; devshells and containers already
  cover it
- **Dolphin** — a file manager's job is seeing all of `$HOME`
- **OBS** — installed, with `v4l2loopback` wired up in `modules/obs.nix`

### Known casualty

Bitwarden's browser extension talks to the desktop app over **native
messaging**, which is a local socket the sandbox will cut. Verify that path
before sandboxing either half, or accept using the web vault in-browser.

---

## 2. Dev tools — ✅ landed in `home/dev.nix`

Language-agnostic, wanted on `PATH` everywhere. These *should* be global —
that's exactly what distinguishes them from §3.

| Current | nixpkgs candidate | Notes |
|---|---|---|
| direnv | `direnv` | **The keystone.** Pair with `nix-direnv`; HM module `programs.direnv`. This is what makes §3 practical. Also the one rpm-ostree layered package |
| gh | `gh` | |
| glab | `glab` | |
| shellcheck | `shellcheck` | |
| mdformat | `mdformat` | **already present** |
| markdown-oxide | `markdown-oxide` | Markdown LSP, pairs with helix |
| yq | **`yq-go`** | ⚠️ nixpkgs `yq` is the *Python jq wrapper*. brew's is mikefarah's Go tool = `yq-go` |
| ruff *(uv tool)* | `ruff` | Python linter, but language-agnostic enough to keep global |
| helix | `helix` | **already present** via HM module |
| uv | `uv` | **already present.** Manages per-project Python, so it's a dev tool — not a toolchain |

**IDEs** — dev tools, but heavy and unfree:

| Current | nixpkgs candidate |
|---|---|
| IntelliJ IDEA (Ultimate) | ✅ **`jetbrains.idea`** 2026.2.0.1 — installed |
| GoLand | ✅ **`jetbrains.goland`** 2026.2.0.1 — installed |
| PyCharm | ✅ **`jetbrains.pycharm`** 2026.2 — installed |
| RubyMine | ❌ **dropped** — not writing Ruby |
| JetBrains Toolbox | **Dropped.** nixpkgs packages the IDEs directly and keeps them updated — Toolbox only ever existed to work around distros that couldn't. This is the "nix has a better option" case |

---

## 3. Toolchains — **do not install globally**

Everything here is on the machine today via brew, and everything here should
leave the global profile. Per-project `flake.nix` + `devShells`, activated by
`direnv`. This is the whole argument for the migration on the dev side.

| Current | Belongs in | Notes |
|---|---|---|
| `beamPackages.elixir` | devshell | Pulls erlang. Per-project version pinning is the entire point. Top-level `elixir` warns as deprecated |
| node | devshell | The global npm tree is already empty — nothing depends on it being global |
| llvm, llvm@20 | devshell | Two versions installed side by side today. That's the problem statement |
| gcc | devshell | |
| python@3.14 | devshell | `uv` handles the Python side; the devshell supplies the interpreter and native libs |
| pytorch, numpy, onnx, protobuf | devshell / container | ML stack — see below |

### The ML/CUDA subset — deferred

`openai-whisper` (brew), `whisperx` (uv tool), the brew `pytorch`/`numpy`/
`onnx` stack, and ~55 GiB of CUDA container images (`nvcr.io/nvidia/pytorch`
22 GB, `sglang` 19.7 GB, `vllm` 10.5 GB).

Deferred by decision. **O-12** in the runbook already records what was
established: the SELinux finding, the nvidia-container-toolkit 1.17.8 CDI
trap, and that the CUDA binary cache moved to `cache.nixos-cuda.org`. Three
paths exist — pure-nixpkgs `cudaSupport`, devshell + `uv` wheels, or
containers — and choosing between them blocks nothing else here.

**Correction:** `whisperx` IS in nixpkgs (3.8.6) — verified with `nix search`
against real nixpkgs, not assumed. Earlier notes here claimed otherwise. It is
installed from `home/cli.nix`; no `uv tool`, and it does not depend on the
`nix-ld` decision. GPU acceleration still does depend on the deferred CUDA
choice — expect CPU inference until O-12 is resolved.

---

## 3b. Dev environments — expected to be rebuilt, not migrated

Decision on record: **no dev environment is expected to survive the
migration except the uv Python workflow**, and that survives because
`uv.lock` is the real state and it is in git. Venvs are derived artifacts;
`uv sync` rebuilds them. Budget ~15 minutes per project, and treat anything
worse than that as a genuine edge case rather than the norm.

So the seven `pyvenv.cfg` files under `~/code` are not a migration problem —
they are directories to delete. Recorded only because two of them point
somewhere surprising:

- `harper/back` → `/opt/homebrew/opt/python@3.11/bin`, a **macOS** path. That
  venv is already dead on this machine, migration or not.
- `cyclone` → `/root/.local/share/uv/python/…`, i.e. built under `sudo`
  against root's uv. Pre-existing oddity, worth knowing before you rebuild it.

### The one thing that is not free

uv ships python-build-standalone interpreters, and those always request an
FHS loader:

```
[Requesting program interpreter: /lib64/ld-linux-x86-64.so.2]
```

NixOS has no such path, so a freshly downloaded uv Python will not execute
either — deleting the old interpreters does not dodge this. Pick one:

```nix
programs.nix-ld.enable = true;    # keeps uv's normal workflow intact
```

or set uv to prefer a nixpkgs-provided interpreter and give up uv's Python
version management. `nix-ld` is the smaller concession and is **not currently
set**. It was previously noted only as a JetBrains Toolbox workaround, and
Toolbox has since been dropped — uv is the better reason to keep it.

---

## 4. Drop entirely

**Flatpak infrastructure** — meaningless without flatpak: Flatseal, Ignition,
Warehouse, Bazaar, Gear Lever, flatpak-external-data-checker.

**GNOME-shell-specific** — the target desktop is niri/Hyprland: Extension
Manager, Refine.

**Never used** — Mission Center, InvoiceNinja.

**Dropped by decision (2026-08-08):**

- `chezmoi` — never used; came in with Bluefin. home-manager is the dotfile
  manager.
- `devcontainer` — devcontainers aren't earning their keep. The `krump-dev`,
  `cyclone-dev`, `invoice-dev` and `vsc-*`/`jb-*` images in the podman store
  are the residue of that experiment and can go with them.
- **JetBrains Toolbox** — nixpkgs packages `jetbrains.idea-ultimate` and
  `jetbrains.rubymine` directly and tracks upstream versions. Toolbox existed
  to solve a problem NixOS doesn't have.

**Dropped from §1a by decision (2026-08-09):** `zoxide`, `atuin`,
`trash-cli`, `uutils-coreutils`, `stress-ng`. Not overlooked — declined.

Consequence worth knowing: atuin's shell history database sits in `~` and
survives the migration, but with atuin gone nothing will read it. Delete
`~/.local/share/atuin` if you want the space back.

**Superseded by the migration:** `bash-preexec` (only ever existed to support
atuin under bash — doubly irrelevant now), and the 170 non-leaf brew formulae,
which are dependency closure that vanishes with the prefix.

**Directories to delete by hand afterwards.** These sit on `home` and survive
the migration, but nothing on NixOS will run them:

```
/home/linuxbrew
~/AppImages
~/.local/share/JetBrains/Toolbox
```

---

---

## 5. Cross-cutting, before anything lands

- **`nixpkgs.config.allowUnfree`** is already set (the NVIDIA driver forces
  it). It also covers `obsidian`, `vivaldi`, `jetbrains.*`.
- **`programs.nix-ld.enable`** is not set and probably should be — see §3b.
  Without it, uv's downloaded Pythons cannot execute.
- **`/home` is a live subvolume** full of existing config. home-manager moves
  conflicting files aside via `backupFileExtension = "hm-bak"` (set in
  `flake.nix`), but expect that to fire a lot on the first switch.

## 6. Suggested order

1. **§2 dev tools + `direnv`/`nix-direnv` first.** Small, low-risk, and it
   unblocks §3 — no point emptying the global toolchain profile before the
   thing that replaces it works.
2. **§1a CLI.** Also low-risk, and it restores daily muscle memory.
3. **§1b GUI** — browser and editor first, enough for a usable desktop.
4. **§3 toolchains**, one project at a time, as you actually touch each repo.
5. **Defer** the GNOME accessories until the compositor is settled, and the
   ML/CUDA subset until you come back to it.
