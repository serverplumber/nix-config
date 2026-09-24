{
  config,
  inputs,
  pkgs,
  ...
}:
let
  # hyprctl from the flake input, NOT pkgs.hyprland. home/hyprland.nix runs
  # the compositor from inputs.hyprland; pkgs.hyprland is a different version
  # (0.56.2 vs 0.56.0 at time of writing), and naming it here pulled a whole
  # second Hyprland into the system closure just to get a ~200KB IPC client.
  hyprPkgs = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system};

  # Every project lives one level under here. Depth 1 and no deeper: at depth 2
  # the list is 184 entries, which is a scrolling list rather than a picker.
  projectRoot = "${config.home.homeDirectory}/code";

  # ---------------------------------------------------------------- the pieces
  #
  # Deliberately several small programs rather than one. The failure this is
  # shaped around is an agent dying: when that happens the workspace is still
  # perfectly good, and what's wanted is `project-agent <name>`, not tearing
  # the whole thing down and rebuilding it. Same for wanting a second terminal
  # in a project, or a browser window that was closed by accident.
  #
  # So: three leaf scripts that each launch exactly one thing and know nothing
  # about compositors, one script that knows about compositors and nothing
  # about projects (project-ws), and one orchestrator that composes them.
  #
  # Absolute store paths throughout, for the same reason as home/niri.nix and
  # home/hyprland.nix: a compositor does not reliably inherit the
  # home-manager profile's PATH, and a bare name that fails to resolve fails
  # silently — the key simply does nothing. writeShellApplication's
  # runtimeInputs gives the same guarantee for what the scripts call
  # internally, so the only places a literal store path is spelled out are the
  # keybinds at the bottom of this file.

  # Recency order, and "recency" has to mean the newest file *inside* the
  # project. A directory's own mtime is useless here: it changes only when an
  # entry is added or removed from that directory, so a project you've been
  # editing in all week still reports the mtime of whenever you last created
  # a file in its root.
  #
  # Walking every file is therefore the honest way to do it, and it turns out
  # to be cheap: ~230ms over 26k files, measured on this machine. No cache —
  # a cache would need invalidating and 230ms does not need saving.
  #
  # Two fd details that are load-bearing:
  #
  #   --strip-cwd-prefix=never  fd's default is `auto`, and `auto` is not
  #                             stable across output modes — piped to `head`
  #                             it strips the `./`, piped through `-0 |
  #                             xargs` it does not. The awk below indexes a
  #                             fixed path component, so the prefix has to be
  #                             predictable. It also needs `=`: the value is
  #                             optional, so `--strip-cwd-prefix never` eats
  #                             `never` as the search pattern and matches
  #                             nothing.
  #   -E .git                   excluded because .git churns constantly (every
  #                             fetch rewrites refs), which would make every
  #                             repo look equally fresh. NOT used as a filter
  #                             for what counts as a project — plenty of these
  #                             directories have no repo yet.
  #
  # The awk splits on the first space rather than taking $2, so paths
  # containing spaces still land under the right project. `p[3] != ""`
  # requires the file to be at least one level deep, which is what
  # distinguishes a project directory from a loose file sitting in the root
  # (~/code has a few: a stray .zip, an .rpm).
  #
  # That guard also drops directories that contain no files at all, so the
  # second half unions in every remaining depth-1 directory and appends it
  # alphabetically. Verified on this machine: 35 directories rank by recency,
  # 2 are empty and come last, 37 total, which matches `fd -t d --max-depth 1`.
  projectList = pkgs.writeShellApplication {
    name = "project-list";
    runtimeInputs = [
      pkgs.fd
      pkgs.coreutils
      pkgs.findutils
      pkgs.gawk
    ];
    text = ''
      root="''${PROJECT_ROOT:-${projectRoot}}"
      cd "$root"

      ranked=$(
        fd -t f -H -E .git --strip-cwd-prefix=never -0 \
          | xargs -0 -r stat --format '%Y %n' \
          | awk '{ i = index($0, " "); split(substr($0, i + 1), p, "/")
                   if (p[3] != "" && $1 > m[p[2]]) m[p[2]] = $1 }
                 END { for (d in m) print m[d], d }' \
          | sort -rn \
          | cut -d' ' -f2-
      )

      all=$(
        fd -t d -H --max-depth 1 --strip-cwd-prefix=never \
          | sed -e 's:^\./::' -e 's:/$::' \
          | sort
      )

      {
        printf '%s\n' "$ranked"
        comm -23 <(printf '%s\n' "$all" | sed '/^$/d') \
                 <(printf '%s\n' "$ranked" | sed '/^$/d' | sort)
      } | sed '/^$/d'
    '';
  };

  # noctalia's launcher, in dmenu mode: newline-separated items on stdin, the
  # selection on stdout. Chosen because it is already the launcher bound to
  # Mod+D in both sessions — it looks and behaves like the rest of the desktop
  # and adds no dependency (fuzzel, wofi, rofi would each add one).
  #
  # It is a flat list picker, not a file browser: it does no filesystem
  # walking of its own, which is why project-list exists as a separate program
  # at all.
  #
  # UNVERIFIED: whether a no-match returns the typed text. Nothing here
  # depends on it — the orchestrator checks that the selection is a real
  # directory and refuses otherwise.
  projectPick = pkgs.writeShellApplication {
    name = "project-pick";
    runtimeInputs = [
      projectList
      config.programs.noctalia.package
    ];
    text = ''
      project-list | noctalia dmenu --prompt "Project"
    '';
  };

  # ------------------------------------------------------- compositor plumbing
  #
  # The only file here that knows which compositor is running. Everything else
  # is portable.
  #
  # A project workspace occupies a NUMBERED slot and *displays* the project
  # name. Both halves matter: Mod+1..9 already exist in both sessions
  # (home/hyprland.nix's bind loop, home/niri.nix's focus-workspace 1..9), and
  # a workspace you can only get back to by pressing Mod+A and picking from a
  # list again is a poor way to return to the thing you are working in. So the
  # workspace is claimed by number and *renamed*, never created as a
  # name-only workspace.
  #
  # VERIFIED live on Hyprland 0.56.0 — renaming a numbered workspace keeps it
  # numbered, which is the fact the whole feature rests on:
  #
  #   hl.dsp.workspace.rename({ workspace = 1, name = [[zz-probe]] })
  #   -> {"address":"1","type":"numbered","name":"zz-probe","windows":1}
  #
  # so Mod+1 still reaches it and the bar shows "zz-probe" rather than "1".
  #
  # Which slot, on the monitor focused when the key is pressed:
  #
  #   1. the focused workspace, if it is empty AND numbered AND unclaimed;
  #   2. otherwise the lowest free number — 1..9 first, since those are the
  #      ones with binds, then upward.
  #
  # "unclaimed" is load-bearing and is NOT the same as "numbered". Once this
  # feature has run, a workspace can be numbered *and* named, so an empty
  # numbered workspace may well be an existing project workspace (or sidra)
  # whose windows have all been closed; renaming one would silently steal it.
  # Hyprland reports an untouched workspace's number as its name
  # ({"address":"2","name":"2"}), so `.name == .address` is exactly the test
  # for "nobody has claimed this", and it keeps working after the rename.
  #
  # Hyprland reaps an empty renamed workspace as soon as focus leaves it
  # (verified: named workspace 5, last window closed, gone from
  # `hyprctl workspaces` the moment focus moved away), so the number goes back
  # into the pool on its own and `exists` stops reporting the project as open
  # — the same lifetime the name-only workspaces had. The guard above is still
  # needed for the window where such a workspace IS the focused one, which is
  # exactly the case rule 1 looks at.
  #
  # Both sessions get the same behaviour by different routes, because the
  # capability genuinely differs — the same split as the sidra workspace in
  # home/niri.nix and home/hyprland.nix:
  #
  #   Hyprland  workspace numbers are global, not per-monitor, and a workspace
  #             that does not exist yet is created on the focused monitor —
  #             which is what makes "on the monitor we were looking at" fall
  #             out for free. hl.exec_cmd(cmd, rules) takes window rules at
  #             spawn time, so the window is placed by the compositor when it
  #             maps, whatever the focus is doing by then. `silent` keeps focus
  #             where it is. Verified live: the window lands on the numbered
  #             workspace and the active workspace does not change.
  #
  #   niri      has no spawn-time rule for a *runtime* workspace name (window
  #             rules are config-level, and these names are only known when the
  #             key is pressed). So the window is placed after the fact: snapshot
  #             the window ids, spawn, wait for a new one, move it by id. That
  #             is why `spawn` blocks under niri and returns immediately under
  #             Hyprland.
  #
  # Claiming the slot differs too. Hyprland materialises a numbered workspace
  # the moment anything references it, so `ensure` focuses the target number
  # (creating it on the focused monitor) and then renames it. niri's
  # workspaces are positional and already exist — it keeps one empty workspace
  # at the end of every monitor's strip — so `ensure` only has to name one,
  # which `set-workspace-name --workspace <ref>` does without focusing it.
  projectWs = pkgs.writeShellApplication {
    name = "project-ws";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      pkgs.util-linux
      pkgs.niri
      hyprPkgs.hyprland
    ];
    text = ''
      usage() {
        echo "usage: project-ws <exists|ensure|focus|windows|spawn> <workspace> [cmd...]" >&2
        exit 2
      }

      op=''${1:-}
      ws=''${2:-}
      [ -n "$op" ] && [ -n "$ws" ] || usage
      shift 2

      # These are set by the compositor in the environment of everything it
      # spawns, so a keybind-launched process always sees the right one.
      if [ -n "''${NIRI_SOCKET:-}" ]; then
        compositor=niri
      elif [ -n "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
        compositor=hyprland
      else
        echo "project-ws: no niri or Hyprland session in the environment" >&2
        exit 1
      fi

      # ---------------------------------------------------------------- niri
      #
      # niri needs no rename trick: its workspaces are positional, so a named
      # workspace still sits at an index and `focus-workspace <idx>` still
      # reaches it. What changes here is only *which* one gets the name.
      #
      # The price is that an index is not a stable handle the way a Hyprland
      # workspace number is: niri renumbers on every add and remove, so a
      # project sitting at index 3 becomes index 2 when the workspace above it
      # empties out. Not fixed here, and not fixable from this side — the name
      # is the stable handle (everything below refers to workspaces by name),
      # and the number is a convenience that is correct whenever you look at
      # the bar.
      niri_exists() {
        niri msg -j workspaces | jq -e --arg n "$ws" 'any(.[]; .name == $n)' >/dev/null
      }

      niri_focus() {
        niri msg action focus-workspace "$ws"
      }

      # The same list as hyprland_windows, one app-id per line.
      #
      # ASSUMED, not tested, for the same reason as niri_target's count: a
      # window carries .workspace_id and a workspace carries no window list,
      # so this is that same join, keyed here by name rather than by the
      # focused output. If the assumption is wrong the symptom is Mod+A
      # opening a second copy of everything onto a workspace that already has
      # it, rather than anything silent.
      niri_windows() {
        local wins
        wins=$(niri msg -j windows)
        niri msg -j workspaces | jq -r --arg n "$ws" --argjson wins "$wins" '
          (first(.[] | select(.name == $n) | .id) // empty) as $id
          | $wins[] | select(.workspace_id == $id) | .app_id // ""
        '
      }

      # The index to claim on the focused output, or nothing if there is none.
      #
      # niri has no "numbered vs named" distinction — every workspace has an
      # idx — so the Hyprland rule "empty AND numbered AND unclaimed" reads
      # here as "empty AND unnamed". Same protection, same reason: an empty
      # *named* workspace is sidra or a project whose windows were closed.
      #
      # ASSUMED, not tested (niri is not the running session): that a
      # workspace's window count is `niri msg -j windows` grouped by
      # .workspace_id — there is no count on the workspace object itself.
      # The alternative, .active_window_id being null, is one field rather
      # than a join, but it is a proxy for "has focus history" rather than
      # for "has windows", so the join is the honest reading.
      niri_target() {
        local all wins
        all=$(niri msg -j workspaces)
        wins=$(niri msg -j windows)

        # Workspace carries both is_active (active on its own output) and
        # is_focused (the one globally focused). is_focused is the one that
        # matters: the new workspace should land on the monitor being looked
        # at, not on whichever one happens to be first.
        printf '%s' "$all" | jq -r --argjson wins "$wins" '
          (reduce ($wins[] | .workspace_id) as $id ({}; .[$id | tostring] += 1)) as $count
          | (first(.[] | select(.is_focused)) // empty) as $f
          | [ .[]
              | select(.output == $f.output)
              | select((.name // "") == "")
              | select((($count[.id | tostring]) // 0) == 0) ] as $free
          | (if ($free | any(.id == $f.id)) then $f.idx
             else ($free | sort_by(.idx) | .[0] | .idx?)
             end)
          | select(. != null)
        '
      }

      niri_ensure() {
        if niri_exists; then return 0; fi

        local idx
        idx=$(niri_target)
        if [ -z "$idx" ]; then
          # Two ways to land here, and they want different fixes, so the
          # (failure-path only) extra query is worth it. niri guarantees a
          # trailing empty workspace per output, so "no candidate" means that
          # one is named already — every empty workspace on this output
          # belongs to something else, and renaming one would steal it.
          if ! niri msg -j workspaces | jq -e 'any(.[]; .is_focused)' >/dev/null; then
            echo "project-ws: niri reported no focused workspace" >&2
          else
            echo "project-ws: no free workspace on the focused output" >&2
          fi
          return 1
        fi

        # ASSUMED, not tested: that an Index reference resolves against the
        # focused output rather than globally. niri's own default binds map
        # Mod+1..9 to `focus-workspace 1..9` as per-monitor indices, and the
        # binary rejects an index above 255 ("workspace index must be between
        # 0 and 255"), so a reference is clearly not the global workspace id.
        # If this turns out to be wrong the symptom is a workspace on the
        # other monitor getting the name — and it matters more now than it did
        # when this claimed the *last* index on the output, because a low
        # index like 2 exists on both monitors and so fails silently rather
        # than out of range.
        niri msg action set-workspace-name --workspace "$idx" "$ws"
      }

      niri_spawn() {
        local before after new waited id

        before=$(niri msg -j windows | jq -r '.[].id' | sort)
        setsid --fork "$@" >/dev/null 2>&1 </dev/null

        # 30s: a cold browser start is the slow case. Any window that appears
        # in that span gets moved, so a window opened by hand at the same
        # moment would be swept along too — acceptable for a key that is
        # pressed and then waited on.
        waited=0
        while [ "$waited" -lt 150 ]; do
          after=$(niri msg -j windows | jq -r '.[].id' | sort)
          new=$(comm -13 <(printf '%s\n' "$before" | sed '/^$/d') \
                         <(printf '%s\n' "$after" | sed '/^$/d'))
          if [ -n "$new" ]; then
            while read -r id; do
              [ -n "$id" ] || continue
              niri msg action move-window-to-workspace \
                --window-id "$id" --focus false "$ws"
            done <<< "$new"
            return 0
          fi
          sleep 0.2
          waited=$((waited + 1))
        done

        echo "project-ws: no window appeared for: $*" >&2
        return 1
      }

      # ------------------------------------------------------------ Hyprland
      #
      # Lua, not the old string dispatchers — Hyprland 0.56 configures and
      # dispatches in Lua and the string forms are gone. Long-bracket strings
      # ([[...]]) rather than quotes so store paths need no escaping; a
      # workspace name containing ]] would break this, and project directory
      # names do not contain it.
      #
      # hyprctl exits 0 whatever happens — a bad dispatch prints
      # "warning: hl.workspace.rename: no such workspace" and still returns
      # success — so nothing below trusts an exit status; `ensure` re-queries
      # instead.

      # A project workspace is numbered AND named, so `.type` is "numbered"
      # here, not "named": match on the name alone.
      hyprland_exists() {
        hyprctl -j workspaces \
          | jq -e --arg n "$ws" 'any(.[]; .name == $n)' >/dev/null
      }

      # The app-ids of the windows on this workspace, one per line; nothing at
      # all when the workspace does not exist. `.workspace.name` on a client
      # is the *name* of a renamed numbered workspace, not its number —
      # verified live, where the window this was written from reports
      # workspace.name = nix-config — so this needs none of hyprland_addr's
      # `name:` care.
      hyprland_windows() {
        hyprctl -j clients \
          | jq -r --arg n "$ws" '.[] | select(.workspace.name == $n) | .class // ""'
      }

      # Project name -> workspace address, empty if there is no such workspace.
      #
      # Every reference below goes through this, and the `name:` selector is
      # gone from this file entirely. VERIFIED live, the hard way: `name:` only
      # ever matches a workspace of type "named", so spawning with
      # `name:zz-probe` while workspace 1 was renamed to zz-probe created a
      # SECOND, genuinely-named workspace and put the window on that, leaving
      # the project workspace half-populated with no error anywhere.
      hyprland_addr() {
        hyprctl -j workspaces \
          | jq -r --arg n "$ws" 'first(.[] | select(.name == $n) | .address) // ""'
      }

      # An address as a Lua workspace selector. Ours are always numeric, but a
      # workspace named by hand (sidra) is addressed by its name, and `focus
      # sidra` typed at a shell should keep working.
      hyprland_sel() {
        case "$1" in
          *[!0-9]* | "") printf '[[name:%s]]' "$1" ;;
          *)             printf '%s' "$1" ;;
        esac
      }

      # The exec-rule form of the same thing. `1 silent` is verified live:
      # the window lands on workspace 1, creating it on the focused monitor,
      # and the active workspace does not change.
      hyprland_rule() {
        case "$1" in
          *[!0-9]* | "") printf 'name:%s silent' "$1" ;;
          *)             printf '%s silent' "$1" ;;
        esac
      }

      hyprland_focus() {
        local addr
        addr=$(hyprland_addr)
        if [ -z "$addr" ]; then
          echo "project-ws: no workspace named '$ws'" >&2
          return 1
        fi
        hyprctl dispatch "hl.dsp.focus({ workspace = $(hyprland_sel "$addr") })" >/dev/null
      }

      # The number to claim. See the block comment above for the rule; the
      # `.name == .address` test is what keeps an emptied-out project
      # workspace from being handed to a different project.
      #
      # The `.address | test(...)` guard is belt and braces: it keeps anything
      # whose address is not a plain integer (special workspaces) out of the
      # arithmetic regardless of what `.type` says.
      hyprland_target() {
        local wss mons
        wss=$(hyprctl -j workspaces)
        mons=$(hyprctl -j monitors)

        printf '%s' "$mons" | jq -r --argjson ws "$wss" '
          def numeric: .type == "numbered" and (.address | test("^[0-9]+$"));
          first(.[] | select(.focused)) as $m
          | ($m.activeWorkspace.address) as $cur
          | ([$ws[] | select(.address == $cur)] | first) as $curws
          | ([$ws[] | select(numeric) | select(.windows > 0 or .name != .address)
                    | (.address | tonumber)]) as $claimed
          | def free: . as $n | select(($claimed | index($n)) == null);
            if ($curws != null and ($curws | numeric)
                and $curws.windows == 0 and $curws.name == $curws.address)
            then ($cur | tonumber)
            else (first(range(1;10) | free) // first(range(10;256) | free))
            end
        '
      }

      # Focus first, then rename: rename refuses a workspace that does not
      # exist ("no such workspace"), and focusing is what brings a numbered
      # workspace into being — on the focused monitor, which is the placement
      # this whole feature wants. It also means the workspace is already
      # focused for the spawns that follow, so the orchestrator's final focus
      # is a no-op in the common case.
      #
      # Both branches of the target rule survive this: if the focused
      # workspace was already the target, the focus is a no-op and the rename
      # is the whole operation.
      hyprland_ensure() {
        local n
        n=$(hyprland_target)
        if [ -z "$n" ]; then
          echo "project-ws: no free workspace number" >&2
          return 1
        fi

        hyprctl dispatch "hl.dsp.focus({ workspace = $n })" >/dev/null
        hyprctl dispatch \
          "hl.dsp.workspace.rename({ workspace = $n, name = [[$ws]] })" >/dev/null

        # hyprctl cannot report failure, so ask. Anything that went wrong here
        # (the workspace vanished between the two calls, a name collision)
        # shows up as the name not being on workspace $n.
        if ! hyprland_exists; then
          echo "project-ws: failed to name workspace $n '$ws'" >&2
          return 1
        fi
      }

      hyprland_spawn() {
        local cmd addr
        addr=$(hyprland_addr)
        if [ -z "$addr" ]; then
          echo "project-ws: no workspace named '$ws' to spawn into" >&2
          return 1
        fi

        # exec_cmd hands the string to a shell, so shell-quote it. %q is a
        # bash builtin and writeShellApplication scripts are bash.
        cmd=$(printf '%q ' "$@")

        # The command runs with the COMPOSITOR's environment, not this
        # script's — so a bare command name resolved from runtimeInputs would
        # not be found, and PROJECT_ROOT would not carry. Callers pass
        # absolute store paths (the orchestrator does), and the testing
        # override is forwarded explicitly. Absolute `env` for the same
        # reason: coreutils is on this script's PATH, not the compositor's.
        if [ -n "''${PROJECT_ROOT:-}" ]; then
          cmd="${pkgs.coreutils}/bin/env PROJECT_ROOT=$(printf '%q' "$PROJECT_ROOT") $cmd"
        fi

        hyprctl eval \
          "hl.exec_cmd([[$cmd]], { workspace = [[$(hyprland_rule "$addr")]] })" >/dev/null
      }

      # ----------------------------------------------------------- dispatch
      case "$op" in
        exists)  "''${compositor}_exists" ;;
        ensure)  "''${compositor}_ensure" ;;
        focus)   "''${compositor}_focus" ;;
        windows) "''${compositor}_windows" ;;
        spawn)
          [ "$#" -gt 0 ] || usage
          "''${compositor}_spawn" "$@"
          ;;
        *) usage ;;
      esac
    '';
  };

  # ----------------------------------------------------------- the three pieces
  #
  # Each takes a project name and launches one thing in it. No compositor
  # knowledge: run standalone from a terminal and the window lands on whatever
  # workspace is current, which — run from inside the project's own
  # workspace — is exactly right. To place one from elsewhere, go through
  # `project-ws spawn <name> project-agent <name>`, which is what the
  # orchestrator does.

  # No `--` before the command: foot stops parsing options at the first
  # non-option argument and treats the rest as the command, so the separator
  # is both unnecessary and not accepted consistently across foot versions
  # (same note as the Helix desktop entry in home/gui.nix).
  #
  # foot standalone rather than the server/client split: a server-mode client
  # shares one process, so a crash takes every terminal with it, and the
  # per-window --app-id below would not be per-window.
  #
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
  projectEnv = pkgs.writeShellApplication {
    name = "project-env";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      config.programs.direnv.package
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
  };
  # The app-ids the two foot windows are launched with, and the class Brave
  # gives its own windows. Bound once because these are now *matched* as well
  # as set — the orchestrator asks the compositor which of them are already on
  # the workspace — and a literal spelled in two places drifts into "always
  # missing", which shows up as a duplicate window rather than as an error.
  #
  # brave-browser is Brave's own class, shared by every Brave window whether
  # it belongs to this project or not, so the browser test is really "is there
  # a Brave window on this workspace". Making it exact would mean passing
  # --class, which costs the bar its icon lookup: nothing in
  # share/applications matches an invented class. The loose match is the
  # better trade — its failure is a browser window dragged onto the workspace
  # suppressing a relaunch, not a wrong window being opened.
  appIds = {
    term = "project-term";
    agent = "project-agent";
    browser = "brave-browser";
  };

  # Turn job control on, then start `cmd`, both from fish's `-C` init.
  #
  # `fish -C <cmd>` on its own does not give it. fish sets up job control only
  # for commands it treats as interactive, and init commands are not among
  # those, so the program is forked into fish's *own* process group and the
  # terminal is never handed over — measured: under a bare `-C` the child's
  # pgid is fish's pgid, and its own once this is on. Ctrl-Z then goes to a
  # foreground group containing the shell, stopping both, with nothing left
  # running to repaint a prompt: the window wedges, which is the exact failure
  # the shell underneath these two was put there to prevent.
  #
  # THE OTHER FORM ABORTS FISH — do not go back to it. Starting the program by
  # injecting it into the reader instead (an `--on-event fish_prompt` handler
  # doing `commandline --replace` then `commandline --function execute`) also
  # gives job control, and additionally records the command in history so that
  # restarting after an exit is one Up-arrow. It also does this, every time,
  # in a terminal that answers queries:
  #
  #   thread 'main' panicked at src/reader/reader.rs:1728:9:
  #   assertion failed: query.is_none()
  #
  # fish has a terminal query outstanding while it builds its first prompt,
  # and executing a command from inside that event leaves a second in flight.
  # Reproduced in foot with a core dump each time; the window dies before the
  # editor or the agent is ever reached.
  #
  # It does NOT reproduce under a bare pty (`script`), where nothing answers
  # the queries, fish gives up on them after ten seconds and disables the
  # feature that holds the assertion. That is exactly how it got written: the
  # harness could not see a bug the real terminal hits on every launch. Verify
  # anything in this area in a foot window, not in a pty.
  #
  # The price is the history entry, and an abort is not worth it.
  startAsJob = cmd: "status job-control full; ${cmd}";

  # Distinct app-ids so the two foot windows are tellable apart by window
  # rules and by `niri msg -j windows` / `hyprctl -j clients` when debugging.
  projectTerm = pkgs.writeShellApplication {
    name = "project-term";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      name=''${1:-}
      [ -n "$name" ] || { echo "usage: project-term <project>" >&2; exit 2; }
      dir="''${PROJECT_ROOT:-${projectRoot}}/$name"
      [ -d "$dir" ] || { echo "project-term: no such project: $dir" >&2; exit 1; }

      # An interactive fish that *starts* helix, rather than helix as the
      # terminal's only process. The difference is job control: with helix as
      # pid 1 of the pty there is no shell underneath it, so Ctrl-Z suspends
      # it into nothing and quitting it closes the window. Started as a job
      # from fish, Ctrl-Z drops to a prompt in the project directory and `fg`
      # goes back — but only when it is started the way startAsJob starts it.
      # See the comment there: `-C` alone gives a shell with no job control,
      # which is a window that wedges on Ctrl-Z rather than one that suspends.
      #
      # fish is wrapped in project-env rather than left to its own direnv
      # integration. That integration hooks the prompt event, and the program
      # is now started from the prompt event too, so leaning on it would be a
      # race over which handler runs first. project-env loads the environment
      # before fish starts instead, so helix has it from its first millisecond
      # and the shell inherits it. Verified: with an allowed .envrc exporting
      # FOO, the started command sees FOO=bar through project-env.
      #
      # That also keeps the blocked-.envrc warning on the path, which fish's
      # own integration would not give.
      exec ${pkgs.foot}/bin/foot \
        --app-id=${appIds.term} \
        --title="$name — helix" \
        --working-directory="$dir" \
        ${projectEnv}/bin/project-env "$dir" \
        ${config.programs.fish.package}/bin/fish \
        -C '${startAsJob "${config.programs.helix.package}/bin/hx"}'
    '';
  };

  # The agent. Claude Code is a TUI, so this is a terminal too — the piece
  # that dies and gets respawned on its own, which is the whole reason these
  # are separate programs.
  projectAgent = pkgs.writeShellApplication {
    name = "project-agent";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      name=''${1:-}
      [ -n "$name" ] || { echo "usage: project-agent <project>" >&2; exit 2; }
      dir="''${PROJECT_ROOT:-${projectRoot}}/$name"
      [ -d "$dir" ] || { echo "project-agent: no such project: $dir" >&2; exit 1; }

      # Same shape as project-term above, and for the same reasons — see the
      # comments there for why fish is wrapped in project-env, and startAsJob
      # for why `-C` alone is not enough to start it as a job.
      #
      # The agent gets a shell under it too. Ctrl-Z is the smaller half of
      # why: the larger one is that when claude exits — and it exits far more
      # often than an editor does, on /quit, on a crash, on a context limit —
      # the window survives with a prompt in the project directory instead of
      # vanishing. Re-running it is then one `claude` typed at that prompt,
      # rather than project-agent from somewhere else.
      exec ${pkgs.foot}/bin/foot \
        --app-id=${appIds.agent} \
        --title="$name — claude" \
        --working-directory="$dir" \
        ${projectEnv}/bin/project-env "$dir" \
        ${config.programs.fish.package}/bin/fish \
        -C '${startAsJob "${config.programs.claude-code.package}/bin/claude"}'
    '';
  };

  # One browser profile per project, so each project keeps its own cookies,
  # logins, history and open tabs. Same mechanism home/webapps.nix already
  # uses for the Conferencing profile: --profile-directory names a directory
  # under ~/.config/BraveSoftware/Brave-Browser/ and Brave creates it on first
  # use.
  #
  # Brave (not Vivaldi or Firefox) because that is what webapps.nix already
  # standardised on for profile-directory launching. If Brave is already
  # running, this signals the existing process to open a window in that
  # profile rather than starting a second browser.
  projectBrowser = pkgs.writeShellApplication {
    name = "project-browser";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      name=''${1:-}
      [ -n "$name" ] || { echo "usage: project-browser <project>" >&2; exit 2; }

      exec ${pkgs.brave}/bin/brave \
        --profile-directory="$name" \
        --no-first-run \
        --no-default-browser-check
    '';
  };

  # ---------------------------------------------------------- the orchestrator
  #
  # Idempotent on purpose: pressing the key for a project that is already open
  # focuses it. Building a second copy is never what was wanted, and the
  # cheapest way to be sure is to ask the compositor whether the workspace
  # exists rather than keeping state of our own on disk.
  #
  # That check is the entire notion of "is this project open" — it is the
  # compositor's answer, so it stays correct across a script crash, a manual
  # workspace rename, or killing every window by hand.
  #
  # Order matters slightly: the workspace is created and focused *before*
  # anything spawns, so under niri (where placement is after the fact) the
  # windows are already in the right place when they map and the move is a
  # no-op rather than a visible jump.
  #
  # Mod+A is the way a project workspace is *opened*, not the way it is
  # returned to: project-ws puts it on a numbered slot, so once it exists
  # Mod+<that number> reaches it like any other workspace, and the number is
  # what the bar shows the name against. Pressing Mod+A again and picking the
  # same project is still correct — it focuses what is already there.
  projectWorkspace = pkgs.writeShellApplication {
    name = "project-workspace";
    # project-pick and project-ws run as ordinary children of this script, so
    # runtimeInputs is enough for them. The three pieces are NOT here on
    # purpose: they are handed to `project-ws spawn`, which under Hyprland
    # passes them to the compositor to run — in the compositor's environment,
    # where this script's PATH does not exist. They are spelled out as store
    # paths below instead. (Found the hard way: bare names produced a
    # workspace with nothing in it and no error anywhere.)
    runtimeInputs = [
      pkgs.coreutils
      projectPick
      projectWs
    ];
    text = ''
      name=''${1:-}
      if [ -z "$name" ]; then
        name=$(project-pick || true)
      fi
      # Cancelled the picker. Not an error.
      [ -n "$name" ] || exit 0

      root="''${PROJECT_ROOT:-${projectRoot}}"
      if [ ! -d "$root/$name" ]; then
        echo "project-workspace: not a project directory: $root/$name" >&2
        exit 1
      fi

      # Create the workspace if it is not there, then put into it whatever is
      # missing. One path rather than two, because a freshly created
      # workspace is just the case where all three are missing and a project
      # whose agent was closed is the case where one is. That is what makes
      # Mod+A on an already-open project relaunch rather than only focus, and
      # it picks up the case that used to be useless for free: a project
      # workspace whose windows have all been closed is no longer focused
      # empty.
      project-ws exists "$name" || project-ws ensure "$name"

      # Presence is decided per *window*, not per program. A project-term
      # window where helix was quit on purpose counts as present: what is left
      # is a shell in the project directory, which is worth keeping, and
      # pushing an editor back into it is the opposite of what quitting asked
      # for. The cost is the other side of the same coin — a program that died
      # without taking its window with it is invisible here, and restarting it
      # is a matter of typing its name at the prompt that is already there.
      have=$(project-ws windows "$name")
      has() { [[ $'\n'"$have"$'\n' == *$'\n'"$1"$'\n'* ]]; }

      # Browser last: it is the slowest to map, and under niri each spawn
      # blocks until its window appears, so both terminals are already usable
      # while it is still starting.
      has ${appIds.term} || project-ws spawn "$name" ${projectTerm}/bin/project-term "$name"
      has ${appIds.agent} || project-ws spawn "$name" ${projectAgent}/bin/project-agent "$name"
      has ${appIds.browser} || project-ws spawn "$name" ${projectBrowser}/bin/project-browser "$name"

      project-ws focus "$name"
    '';
  };
in
{
  # All of them, not just the orchestrator. The pieces are meant to be typed:
  # `project-agent foo` after an agent dies, `project-list` to see the order
  # the picker will use, `project-ws focus foo` to jump.
  home.packages = [
    projectList
    projectPick
    projectWs
    projectEnv
    projectTerm
    projectAgent
    projectBrowser
    projectWorkspace
  ];

  # The bind lives here rather than in home/niri.nix and home/hyprland.nix for
  # the same reason modules/sdbackup.nix keeps its own: this is one feature,
  # and a feature split across three files goes stale. Both sessions are
  # cross-referenced from their own files so the next person looking for
  # "what is Mod+A" finds this.
  #
  # Mod+A: a letter, so it is on the Preonic's base layer (CLAUDE.md
  # "Keyboard"), and verified free in both sessions — no Mod+A or "+ A" bind
  # exists in home/niri.nix or home/hyprland.nix, and modules/sdbackup.nix
  # only claims Mod+B and Mod+Backspace.
  programs.niri.settings.binds = {
    "Mod+A".action = (config.lib.niri.actions.spawn "${projectWorkspace}/bin/project-workspace");
  };

  # `extraConfig` is a `lines` option, so this appends to the Lua in
  # home/hyprland.nix rather than colliding with it. As modules/sdbackup.nix
  # notes: a `lines` option has no mkForce, so this must never bind a combo
  # that home/hyprland.nix also binds — two hl.bind() calls on the same combo
  # would race.
  #
  # "SUPER" spelled out rather than home/hyprland.nix's `mod` local: `lines`
  # merges in module order, and this block is emitted BEFORE that file's —
  # verified in the generated hyprland.lua, where it sits above
  # `local mod = "SUPER"`. `mod` would be nil here.
  wayland.windowManager.hyprland.extraConfig = ''

    ------------------------------------------------------ project workspaces
    -- See home/project-workspace.nix. Mirrors niri's Mod+A in the same file.
    hl.bind("SUPER + A", hl.dsp.exec_cmd("${projectWorkspace}/bin/project-workspace"))
  '';
}
