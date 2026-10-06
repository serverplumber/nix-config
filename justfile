# Justfile (bash mode)
# Requirements: just, nix
# Usage: just check
set shell := ["bash", "-eo", "pipefail", "-c"]

# -----------------------------
# Config
# -----------------------------
host            := "laptop"
user            := "stablefly"
project_root    := justfile_directory()

nix_flags := "--extra-experimental-features nix-command --extra-experimental-features flakes"

_default:
    @just --list

# === Passthrough =============================================================

# Run any nix command with flakes already enabled: `just nix search nixpkgs fd`
nix +args:
    nix {{nix_flags}} {{args}}

# Does this attribute exist? `just have kdePackages.dolphin yazi whisperx`
have +attrs:
    #!/usr/bin/env bash
    set -eo pipefail
    list=$(printf '"%s" ' {{attrs}})
    just nix eval --impure --raw --expr "
      let
        f = builtins.getFlake \"github:NixOS/nixpkgs/nixos-unstable\";
        pkgs = import f { system = \"x86_64-linux\"; config.allowUnfree = true; };
        lib = f.lib;
        check = n:
          let r = builtins.tryEval (
            let v = lib.attrByPath (lib.splitString \".\" n) null pkgs;
            in if v == null then \"MISSING \" else \"ok      \" + (v.version or \"?\")
          );
          in (if r.success then r.value else \"THROWS  \") + \"  \" + n;
      in lib.concatStringsSep \"\n\" (map check [ ${list} ])
    "
    @echo

# === Check & format ==========================================================

# Parse every .nix file. Works offline AND without git — the only check that does.
parse:
    #!/usr/bin/env bash
    set -eo pipefail
    fail=0
    for f in $(find . -name "*.nix" | sort); do
      if out=$(nix-instantiate --parse "$f" 2>&1 >/dev/null); then echo "ok    $f"
      else echo "FAIL  $f"; echo "$out" | head -5; fail=1; fi
    done
    exit $fail

# Format all .nix files in place
fmt:
    nix {{nix_flags}} run nixpkgs#nixfmt -- $(cd {{project_root}} && find . -name '*.nix')

# Fail if anything is unformatted (CI-shaped)
fmt-check:
    nix {{nix_flags}} run nixpkgs#nixfmt -- --check $(cd {{project_root}} && find . -name '*.nix')

# Full flake evaluation. NEEDS git-tracked files and a real hardware-configuration.nix.
check:
    nix {{nix_flags}} flake check

# parse + fmt-check, the two that work before the ISO exists
verify: parse fmt-check

# === Build ===================================================================

# Build the full system closure without applying it
build:
    nix {{nix_flags}} build .#nixosConfigurations.{{host}}.config.system.build.toplevel

# Build a bootable VM of the desktop — no real disks, no hardware file
vm:
    nix {{nix_flags}} build .#nixosConfigurations.{{host}}-vm.config.system.build.vm
    @echo "built. run it with: just run-vm"

# Actually boot the VM built by `just vm`. The disk image persists between
# runs under ./vm; `just vm-reset` deletes it.
run-vm:
    #!/usr/bin/env bash
    set -euo pipefail
    [ -L result ] || { echo "no ./result — run 'just vm' first"; exit 1; }
    mkdir -p vm
    NIX_DISK_IMAGE={{project_root}}/vm/{{host}}.qcow2 ./result/bin/run-{{host}}-vm

# Throw away the VM's disk image and start clean next boot
vm-reset:
    rm -f {{project_root}}/vm/{{host}}.qcow2
    @echo "disk image removed"

# Build the live installer ISO carrying this flake
iso:
    nix {{nix_flags}} build .#nixosConfigurations.installer.config.system.build.isoImage
    @echo "ISO at: ./result/iso/"

# Build the standalone home-manager profile (works on any nix machine)
home:
    nix {{nix_flags}} build .#homeConfigurations.{{user}}.activationPackage

# === Apply — bare metal only =================================================

# Runs automatically after `just update`. Builds the closure (with no
# ./result symlink, so it will not clobber the one `just run-vm` reads),
# shows an nvd package diff against the running system, then picks the
# apply path.
#
# The test is whether kernel, kernel-modules or initrd moved. kernel-modules
# is the load-bearing one: the nvidia kernel module is built into that
# closure, so a driver-only bump changes it even when the kernel itself is
# unchanged — which is exactly the case that makes `switch` break the GPU.

# What would applying change — and is `switch` or `boot` the right verb?
diff:
    #!/usr/bin/env bash
    set -eo pipefail
    if [ ! -e /run/current-system ]; then
        echo "not running NixOS — nothing to compare against."
        exit 0
    fi
    echo "building {{host}} to compare..."
    new=$(nix {{nix_flags}} build --no-link --print-out-paths \
            {{project_root}}#nixosConfigurations.{{host}}.config.system.build.toplevel)
    echo
    if command -v nvd >/dev/null 2>&1; then
        nvd diff /run/current-system "$new" || true
    else
        echo "(nvd not on PATH — skipping the package diff)"
    fi
    echo
    staged=0
    for f in kernel kernel-modules initrd; do
        if [ "$(readlink -f /run/current-system/$f)" \
           != "$(readlink -f "$new"/$f)" ]; then
            echo "  $f moved"
            staged=1
        fi
    done
    echo
    if [ "$staged" = 1 ]; then
        echo "==> run 'just boot', then reboot."
        echo "    a live 'just switch' would desync the nvidia userspace"
        echo "    driver from the loaded kernel module."
    else
        echo "==> run 'just switch'. this change needs no reboot."
    fi
    # Independent of the above: an EARLIER switch may already have left the
    # running kernel behind, in which case the reboot is owed either way.
    if ! just needs-reboot >/dev/null 2>&1; then
        echo
        echo "    note: a reboot is already owed from a previous switch —"
        echo "    'just needs-reboot' for details."
    fi

# Apply to THIS machine. Only meaningful once running NixOS.
switch:
    sudo nixos-rebuild switch --flake {{project_root}}#{{host}}

# The path to take whenever `just diff` reports that kernel/kernel-modules/
# initrd moved. `switch` there is actively harmful: activation repoints
# /run/opengl-driver at the new userspace driver while the OLD nvidia kernel
# module stays loaded — it cannot be unloaded, nvidia_drm is pinned by the
# running compositor. That mismatch kills nvidia-smi and makes
# nvidia-container-toolkit-cdi-generator.service fail (it wipes
# /var/run/cdi via RuntimeDirectory=, so GPU containers break too), and the
# only cure is the reboot you were going to need regardless.
#
# `boot` never repoints /run/current-system, so the loaded module and the
# driver on the path stay in agreement until you reboot. This is the same
# staging model as the ostree deployments this machine came from.

# Stage for the NEXT boot, touching nothing that is currently running.
boot:
    sudo nixos-rebuild boot --flake {{project_root}}#{{host}}
    @echo "staged for next boot. reboot to activate."

# Answers "did a past `switch` leave me owing a reboot", which is not the
# same question as "is there a staged generation" — after `just boot`,
# current-system is deliberately untouched and this still reports clean.
# Exits 1 when a reboot is owed, so it composes in shell conditionals.

# Does the RUNNING system still match /run/current-system?
needs-reboot:
    #!/usr/bin/env bash
    set -eo pipefail
    if [ ! -e /run/booted-system ]; then echo "not running NixOS"; exit 0; fi
    owed=0
    for f in kernel kernel-modules initrd; do
        if [ "$(readlink -f /run/booted-system/$f)" \
           != "$(readlink -f /run/current-system/$f)" ]; then
            echo "  $f differs from the booted system"
            owed=1
        fi
    done
    [ "$owed" = 0 ] && echo "booted system is current" && exit 0
    echo "reboot required to finish a previous switch"
    exit 1

# === Utilities ===============================================================

# Show every output this flake exposes
show:
    nix {{nix_flags}} flake show

# Resolve inputs / write flake.lock
lock:
    nix {{nix_flags}} flake lock

# Bump every input, then say which apply path the result needs
update: && diff
    nix {{nix_flags}} flake update

# Enter this flake's devShell (nixfmt, nix-tree, just)
shell:
    nix {{nix_flags}} develop

# Garbage collect the store
gc:
    nix {{nix_flags}} store gc
