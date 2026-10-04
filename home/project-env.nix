# Shared by ./project-workspace.nix (the terminal and agent launchers) and
# ./claude-code.nix (the Go language server and format hook), which is why it
# is a file of its own rather than a let-binding in either. Takes direnv as an
# argument so both callers pass the same config.programs.direnv.package.
{ pkgs, direnv }:
# Runs a command in the project's direnv environment, or plainly when there
# is none. Without this, helix's LSPs and the agent see the bare
# home-manager profile — a compositor-spawned window inherits the
# compositor's environment, which was fixed at login and has never been
# near the project.
#
# direnv rather than `nix develop <dir> -c`, for three reasons. It gives
# the *same* environment an interactive `cd` into that directory gives,
# rather than a second, subtly different one. It costs nothing on the 31
# of 37 projects here that have no .envrc. And `nix develop` cannot be
# applied blind: five projects have a flake and no .envrc, and a flake
# with no devShells.<system>.default makes `nix develop` fail outright —
# deciding that per project means evaluating the flake on every launch.
# A project that wants its devShell here adds a one-line .envrc, which is
# this machine's convention anyway (see programs.direnv in home/dev.nix,
# "the keystone").
#
# Three states, from `direnv status --json`:
#
#   allowed = 0        load it.
#   no .envrc at all   run plainly. NOT an error — `direnv exec` on a
#                      directory with no .envrc runs the command and exits
#                      0, so this branch exists only to skip the fork.
#   allowed = 1        blocked, awaiting `direnv allow`. Run plainly and
#                      say so. This branch is the reason the whole thing
#                      is not just `exec direnv exec`: on a blocked
#                      .envrc, `direnv exec` exits 1 WITHOUT running the
#                      command, so a freshly cloned repo would open a
#                      terminal that dies instantly and an agent that
#                      never appears.
#
# The blocked warning goes to stderr and is then painted over by whatever
# TUI follows it, so in practice it is a flash. Making it stick would mean
# a desktop notification, and there is no notify-send on this machine —
# not worth a package for a state you leave by running `direnv allow`.
#
# `direnv exec DIR CMD` does NOT chdir to DIR — verified; it loads that
# directory's environment and runs CMD in the *caller's* cwd. Harmless
# here because foot has already set --working-directory, but it means this
# script must never be relied on to place the command.
pkgs.writeShellApplication {
  name = "project-env";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.jq
    direnv
  ];
  text = ''
    dir=''${1:-}
    shift || true
    [ -n "$dir" ] && [ "$#" -gt 0 ] || {
      echo "usage: project-env <dir> <command> [args...]" >&2
      exit 2
    }
    [ -d "$dir" ] || { echo "project-env: no such directory: $dir" >&2; exit 1; }

    # `// "none"` covers both a missing foundRC and a null one.
    allowed=$(cd "$dir" && direnv status --json 2>/dev/null \
      | jq -r '.state.foundRC.allowed // "none"')

    case "$allowed" in
      0)
        exec direnv exec "$dir" "$@"
        ;;
      none)
        exec "$@"
        ;;
      *)
        echo "project-env: $dir/.envrc is blocked — run 'direnv allow' there." >&2
        echo "project-env: continuing without it; LSPs and tooling will be missing." >&2
        exec "$@"
        ;;
    esac
  '';
}
