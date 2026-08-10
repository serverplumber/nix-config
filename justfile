# Justfile (bash mode)
# Requirements: just, podman (not docker) — or a host nix, which is preferred
# Usage: just check
#
# Pattern lifted from ~/code/krump/justfile. The nix-store podman volume is
# shared with that project; `just bootstrap` creates it if missing.
set shell := ["bash", "-eo", "pipefail", "-c"]

# -----------------------------
# Config
# -----------------------------
host            := "laptop"
user            := "stablefly"
nix_image       := "ghcr.io/nixos/nix"
podman          := "podman"
workspace       := "/workspace"
project_root    := justfile_directory()

nix_flags := "--extra-experimental-features nix-command --extra-experimental-features flakes"

_has-nix := `command -v nix || true`
_has-nix-store := `podman volume inspect nix-store &>/dev/null && echo "yes" || echo ""`

_default:
    @just --list

_need-nix-store:
    @[ -n "{{_has-nix-store}}" ] || just bootstrap

# Create the shared nix-store volume if it does not exist
bootstrap:
    #!/usr/bin/env bash
    if [ -z "{{_has-nix-store}}" ]; then
        echo "Bootstrapping nix-store volume..."
        {{podman}} run --rm -v nix-store:/nix {{nix_image}} cp -a /nix/. /nix/
        echo "nix-store volume ready."
    fi

# Run nix on the host if present, else in the container
_nix +args: _need-nix-store
    #!/usr/bin/env bash
    set -eo pipefail
    if [ -n "{{_has-nix}}" ]; then
        nix {{args}}
    else
        {{podman}} run --rm \
          -v {{project_root}}:{{workspace}}:z \
          -v nix-store:/nix \
          --userns keep-id:uid=0,gid=0 \
          -e NIX_USER_CONF_FILES={{workspace}}/.nix-config \
          -w {{workspace}} \
          {{nix_image}} \
          nix {{args}}
    fi

# === Passthrough =============================================================

# Run any nix command with flakes already enabled: `just nix search nixpkgs fd`
nix +args:
    just _nix {{nix_flags}} {{args}}

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

# === Backup ==================================================================

# One-shot pre-migration backup to an external drive.
#   just restic_init /run/media/stablefly/mydrive
#
# Runs from BLUEFIN, before anything destructive. Creates the repo if absent,
# then backs up $HOME using backup-excludes.txt — the same exclude list the
# NixOS job uses. The repo is portable: after the migration,
# modules/backup.nix keeps appending to a repo of exactly this shape.
restic_init dest: _need-nix-store
    #!/usr/bin/env bash
    set -euo pipefail
    pw="$HOME/.config/restic/password"
    if [ ! -f "$pw" ]; then
        echo "No password file at $pw"
        echo
        echo "Create one, then STORE IT SOMEWHERE ELSE TOO — lose it and the"
        echo "repository is unrecoverable by design:"
        echo
        echo "  mkdir -p ~/.config/restic"
        echo "  head -c 32 /dev/urandom | base64 > ~/.config/restic/password"
        echo "  chmod 600 ~/.config/restic/password"
        exit 1
    fi
    if [ ! -d "{{dest}}" ]; then echo "destination {{dest}} is not mounted"; exit 1; fi

    # $HOME and the destination are mounted at their real paths so restic
    # records real paths — a repo full of /data/... is painful to restore from.
    run() {
        if command -v restic >/dev/null; then
            RESTIC_PASSWORD_FILE="$pw" restic "$@"
        else
            {{podman}} run --rm -i \
              --security-opt=label=disable \
              -v nix-store:/nix \
              -v "$HOME":"$HOME":ro \
              -v "{{dest}}":"{{dest}}" \
              -v "{{project_root}}":"{{project_root}}":ro \
              -e RESTIC_PASSWORD_FILE="$pw" \
              --userns keep-id:uid=0,gid=0 \
              -w "$HOME" \
              {{nix_image}} \
              nix {{nix_flags}} run nixpkgs#restic -- "$@"
        fi
    }

    if ! run -r "{{dest}}/restic" cat config >/dev/null 2>&1; then
        echo "==> initialising repository at {{dest}}/restic"
        run -r "{{dest}}/restic" init
    fi

    echo "==> backing up $HOME (excludes: {{project_root}}/backup-excludes.txt)"
    run -r "{{dest}}/restic" backup "$HOME" \
        --exclude-file "{{project_root}}/backup-excludes.txt" \
        --exclude-caches \
        --one-file-system

    echo
    run -r "{{dest}}/restic" snapshots

# Verify a repo actually restores. An untested backup is a hope, not a backup.
restic_check dest:
    #!/usr/bin/env bash
    set -euo pipefail
    export RESTIC_PASSWORD_FILE="$HOME/.config/restic/password"
    if command -v restic >/dev/null; then
        restic -r "{{dest}}/restic" check --read-data-subset=5%
    else
        {{podman}} run --rm -i --security-opt=label=disable \
          -v nix-store:/nix -v "{{dest}}":"{{dest}}" \
          -e RESTIC_PASSWORD_FILE -v "$HOME/.config/restic":"$HOME/.config/restic":ro \
          --userns keep-id:uid=0,gid=0 {{nix_image}} \
          nix {{nix_flags}} run nixpkgs#restic -- -r "{{dest}}/restic" check --read-data-subset=5%
    fi

# === Check & format ==========================================================

# Parse every .nix file. Works offline AND without git — the only check that does.
parse: _need-nix-store
    #!/usr/bin/env bash
    set -eo pipefail
    run() { if [ -n "{{_has-nix}}" ]; then sh -c "$1"; else
        {{podman}} run --rm -v {{project_root}}:{{workspace}}:z -v nix-store:/nix \
          --userns keep-id:uid=0,gid=0 -w {{workspace}} {{nix_image}} sh -c "$1"; fi; }
    run 'fail=0
         for f in $(find . -name "*.nix" | sort); do
           if out=$(nix-instantiate --parse "$f" 2>&1 >/dev/null); then echo "ok    $f"
           else echo "FAIL  $f"; echo "$out" | head -5; fail=1; fi
         done; exit $fail'

# Format all .nix files in place
fmt:
    just _nix {{nix_flags}} run nixpkgs#nixfmt -- $(cd {{project_root}} && find . -name '*.nix')

# Fail if anything is unformatted (CI-shaped)
fmt-check:
    just _nix {{nix_flags}} run nixpkgs#nixfmt -- --check $(cd {{project_root}} && find . -name '*.nix')

# Full flake evaluation. NEEDS git-tracked files and a real hardware-configuration.nix.
check:
    just _nix {{nix_flags}} flake check

# parse + fmt-check, the two that work before the ISO exists
verify: parse fmt-check

# === Build ===================================================================

# Build the full system closure without applying it
build:
    just _nix {{nix_flags}} build .#nixosConfigurations.{{host}}.config.system.build.toplevel

# Build a bootable VM of the desktop — no real disks, no hardware file
vm:
    just _nix {{nix_flags}} build .#nixosConfigurations.{{host}}-vm.config.system.build.vm
    @echo "run it with: ./result/bin/run-{{host}}-vm-vm"

# Build the live installer ISO carrying this flake
iso:
    just _nix {{nix_flags}} build .#nixosConfigurations.installer.config.system.build.isoImage
    @echo "ISO at: ./result/iso/"

# Build the standalone home-manager profile (works on any nix machine)
home:
    just _nix {{nix_flags}} build .#homeConfigurations.{{user}}.activationPackage

# === Apply — bare metal only =================================================

# Apply to THIS machine. Only meaningful once running NixOS.
switch:
    sudo nixos-rebuild switch --flake {{project_root}}#{{host}}

# Apply the home-manager half only
home-switch:
    home-manager switch --flake {{project_root}}#{{user}}

# === Utilities ===============================================================

# Show every output this flake exposes
show:
    just _nix {{nix_flags}} flake show

# Resolve inputs / write flake.lock
lock:
    just _nix {{nix_flags}} flake lock

# Bump every input
update:
    just _nix {{nix_flags}} flake update

# Enter this flake's devShell (nixfmt, nix-tree, just)
shell:
    just _nix {{nix_flags}} develop

# Interactive nix shell in the container, workspace mounted
naked-nix: _need-nix-store
    {{podman}} run -it --rm \
      -v {{project_root}}:{{workspace}}:z \
      -v nix-store:/nix \
      --userns keep-id:uid=0,gid=0 \
      -e NIX_USER_CONF_FILES={{workspace}}/.nix-config \
      -w {{workspace}} \
      {{nix_image}}

# Garbage collect the shared store
gc:
    just _nix {{nix_flags}} store gc
