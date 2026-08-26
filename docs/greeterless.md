# Greeterless login — pick the session on the way *out*

**Status: design, not implemented.** `modules/desktop.nix` runs SDDM as of
2026-08-25. This is the alternative to fall back to if SDDM disappoints, and
it is deliberately not a small tweak to SDDM — it is a different shape.

Nothing here has been booted. The Nix below is written against real,
verified facts (flags checked against the actual `tuigreet` binary, paths
checked against the actual desktop files) but it has never been applied.
Treat it as a careful sketch, not a tested recipe.

## Context

Three greeters in three weeks, and each one broke differently:

| Greeter | Failure |
|---|---|
| tuigreet (NotAShelf fork), until 2026-08-10 | listed all 4 sessions twice |
| ReGreet, until 2026-08-25 | froze at the password prompt |
| — the nixpkgs regreet module | never created `/var/lib/regreet`, so it rendered but ignored input |
| — NixOS itself | `X-RestartIfChanged=false`, so greeter changes silently never applied |

Four failures, four different components, and **greetd was not any of them.**
greetd prompted correctly, spawned session workers correctly, and did PAM
correctly every single time. It is a small daemon that does one job. The
problem is that it is a *bring-your-own-greeter* system, so the integration is
our problem, and the greeter is where all the surface area lives.

SDDM is the "let someone else own the seams" answer. This document is the
other answer: **delete the graphical greeter entirely.**

The observation that makes it work is that the session picker and the password
prompt do not have to happen at the same moment. Picking a session needs a
rich UI. Authenticating needs a text field. If you move the pick to *shutdown*
— when you already have a working compositor and a launcher in front of you —
then boot only needs the text field, and a text field has nothing to livelock.

## The precondition you must not skip

**This machine has no full-disk encryption.**

```
/            /dev/nvme0n1p3[/nixos]   btrfs
/home        /dev/nvme0n1p3[/home]    btrfs
/nix         /dev/nvme0n1p3[/nix]     btrfs
/dev/mapper/ → control                 (no LUKS, no dm-crypt)
```

This matters because the obvious version of this idea — full autologin, no
prompt at all — is what Omarchy does, and **Omarchy's entire justification is
LUKS.** "Single-user system with full-disk encryption, so the passphrase at
boot is the real gate." That premise does not hold here. Right now the login
password is the only thing between a powered-off laptop and a live session
holding your SSH agent, keyring, and browser cookies. On a machine that
travels, deleting it is a real downgrade, not a neutral simplification.

So the design below **keeps the password prompt** and only deletes the
*graphics*. If FDE ever lands, revisit — full autologin becomes defensible
then, and the design collapses to something even simpler.

## Design

```
   shutdown                        boot
   ────────                        ────
   pick-next-session hyprland      greetd starts
        │                               │
        ▼                               ▼
   /var/lib/next-session           tuigreet --cmd "$(resolve)"
   contains "hyprland"                  │
                                        ▼
                                   password only, no session list
                                        │
                                        ▼
                                   Hyprland
```

Three moving parts: a state file, a greeter wrapper that reads it, and a
picker that writes it.

The state file holds a bare session *name* (`niri`, `hyprland`, `plasma`), not
a command. The wrapper resolves the name to a command by reading the `Exec=`
line out of the real `.desktop` file, so it can never drift from what the
sessions actually are. That indirection is the whole reason this stays
maintainable.

## Implementation

Add to `modules/desktop.nix`, replacing the `services.displayManager.sddm`
block:

```nix
let
  nextSession = "/var/lib/next-session";

  # Resolve a session name to its real command by reading the .desktop file
  # NixOS already generates. Never hardcode the Exec lines here — Hyprland's
  # is an absolute store path that changes on every update.
  greeter = pkgs.writeShellScript "tuigreet-fixed-session" ''
    set -u
    name=$(cat ${nextSession} 2>/dev/null || echo niri)

    desktop="${config.services.displayManager.sessionData.desktops}/share/wayland-sessions/$name.desktop"
    cmd=$(${pkgs.gnugrep}/bin/grep -m1 '^Exec=' "$desktop" 2>/dev/null | cut -d= -f2-)

    # Fall back to niri rather than handing tuigreet an empty --cmd, which
    # would drop you into a session that instantly exits.
    if [ -z "$cmd" ]; then
      cmd="niri-session"
    fi

    exec ${lib.getExe pkgs.tuigreet} \
      --remember \
      --asterisks \
      --time \
      --greeting "$name" \
      --cmd "$cmd"
  '';
in
{
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${greeter}";
      user = "greeter";
    };
  };

  # Owned by stablefly so the picker needs no sudo; world-readable because
  # the greeter runs as `greeter` and has to read it.
  systemd.tmpfiles.rules = [
    "f ${nextSession} 0644 stablefly users - niri"
  ];
}
```

Note what is **not** there: no `--sessions`. That flag is the session
enumerator, and the enumerator is exactly what double-listed under the
NotAShelf fork. With a fixed `--cmd` there is no list to get wrong.

(For the record, nixpkgs today ships `tuigreet` = **apognu/tuigreet 0.9.1**,
the upstream, not the NotAShelf fork that caused the original bug. Flags above
were read out of that binary's `--help`, not guessed.)

## The picker

```nix
pick-next-session = pkgs.writeShellScriptBin "pick-next-session" ''
  set -eu
  case "''${1:-}" in
    niri|hyprland|plasma) printf '%s\n' "$1" > ${nextSession} ;;
    *) echo "usage: pick-next-session {niri|hyprland|plasma}" >&2; exit 1 ;;
  esac
  echo "next session: $1"
'';
```

Deliberately argument-driven rather than menu-driven, because noctalia already
owns the launcher on this machine (`modules/desktop.nix`: "No wmenu, no
swaybg"). Wire it to whatever menu you like, or bind the three cases directly.

For binds in `home/niri.nix` and `home/hyprland.nix`, remember the Preonic
constraint from `CLAUDE.md` — letters and the five modifiers, nothing exotic:

```
Mod+Shift+N  →  pick-next-session niri     && <quit compositor>
Mod+Shift+H  →  pick-next-session hyprland && <quit compositor>
Mod+Shift+P  →  pick-next-session plasma   && <quit compositor>
```

Plasma's logout menu is not scriptable the same way; from Plasma just run
`pick-next-session` from a launcher before logging out.

## Verifying it

1. `just build` — catches option and syntax errors.
2. `cat /var/lib/next-session` — should exist, mode 0644, owned by stablefly.
3. `pick-next-session plasma && cat /var/lib/next-session` → `plasma`.
4. **Restart the greeter explicitly.** `just switch` alone will *not* do it:

   ```
   sudo systemctl restart greetd
   ```

   greetd carries `X-RestartIfChanged=false` upstream, so a rebuild never
   restarts it — that is deliberate (it stops a routine rebuild yanking your
   desktop away) and it is also how an entire afternoon got lost on 2026-08-25
   thinking a fix had not worked when it had.
5. Log out and confirm the greeting line shows the name you picked.

## Failure modes

**Chosen session is broken.** tuigreet will keep launching the same broken
`--cmd` on every login. Escape: `Ctrl+Alt+F2` to a TTY, log in, `echo niri >
/var/lib/next-session`. Worth confirming that VT switch works on the Preonic
before relying on it — per `CLAUDE.md` the function-key row is unconfirmed.

**State file deleted or empty.** The wrapper falls back to `niri`. Covered.

**Name doesn't match a `.desktop` file.** `grep` finds nothing, `cmd` is
empty, the wrapper falls back to `niri`. Covered — this is why the empty check
is there rather than trusting the file.

**greeter user can't read the file.** Symptom is always falling back to niri
regardless of what you picked. Check the mode is `0644`, not `0600`.

## Why not full autologin

Genuinely simpler — greetd's `initial_session` runs a session at boot with no
prompt, so you would not need tuigreet at all. Rejected for two reasons:

1. **No FDE** (see above). It is the whole argument.
2. **The keyring stops unlocking.** gnome-keyring and kwallet are both in this
   machine's PAM stack (`/etc/pam.d/login`) and both unlock from the password
   PAM sees at login. With no password, they stay locked. Omarchy hits this
   exactly and works around it by stripping `pam_gnome_keyring` and running a
   passwordless keyring — a real cost, not a footnote.

Keeping a two-second text prompt buys out of both problems.

## Reverting to SDDM

`git revert` the commit, `just switch`, reboot. Or keep both and flip with a
`lib.mkForce`. The two are mutually exclusive — `services.greetd.enable` and
`services.displayManager.sddm.enable` both want to own
`systemd.services.display-manager`, and NixOS will tell you so.

## Loose end worth knowing

nixpkgs has a `noctalia-greeter` package. This config already runs noctalia as
its shell for both tiling sessions (`modules/noctalia.nix`), so a greeter from
the same project is the one option that would satisfy the "greeter as a
first-class part of the desktop you actually run" argument — the thing that
made Entrance feel solid for years under Enlightenment. Not investigated. It
would need the same scrutiny regreet failed: what does it render with, and
what happens to it on a hybrid Intel+NVIDIA box.
