{ pkgs, ... }:
let
  # github-mcp-server needs a GitHub token in GITHUB_PERSONAL_ACCESS_TOKEN.
  # This repo holds no secrets and is not encrypted, so the token cannot be
  # written into the MCP config — and putting it in the shell environment
  # instead would only move it somewhere every process can read.
  #
  # `gh` is already logged in to github.com and keeps its token in the
  # secret service (kwallet, via org.freedesktop.secrets), so the token
  # already exists on this machine, managed, outside the store. This wrapper
  # fetches it at spawn time and hands it to the server over its own
  # environment. Nothing is persisted and nothing lands in /nix/store.
  #
  # Consequence worth knowing: the server inherits `gh`'s scopes, not a
  # PAT's. Today that login is `repo`, `read:org`, `gist` — enough for the
  # default toolsets (context, copilot, issues, pull_requests, repos,
  # users), but toolsets like `actions`, `code_security` or `dependabot`
  # would need `gh auth refresh -s ...` first, not a change here.
  #
  # Also: this only works while the secret service is unlocked. Claude Code
  # spawns the server as a child of itself, so a terminal inside the desktop
  # session is fine; a bare TTY login with no kwallet is not, and the server
  # will fail to start with the message below rather than hang.
  github-mcp-server-gh-auth = pkgs.writeShellApplication {
    name = "github-mcp-server-gh-auth";
    runtimeInputs = [
      pkgs.gh
      pkgs.github-mcp-server
    ];
    text = ''
      if ! token=$(gh auth token 2>&1); then
        echo "github-mcp-server: could not get a token from gh: $token" >&2
        echo "Run 'gh auth login', or unlock the secret service." >&2
        exit 1
      fi
      export GITHUB_PERSONAL_ACCESS_TOKEN="$token"
      exec github-mcp-server stdio "$@"
    '';
  };

  # PostToolUse hook: reformat a .nix file right after it is written, so
  # `just verify`'s fmt-check never fails on whitespace Claude produced.
  #
  # Packaged rather than written inline in settings.json for two reasons.
  # First, PATH: hooks inherit the session's environment, and `jq` is not
  # something this config guarantees globally — runtimeInputs pins both jq
  # and the exact nixfmt this flake formats with (`nix fmt` is pkgs.nixfmt,
  # see flake.nix), so the hook can never disagree with `just fmt` about
  # what correct formatting is. Second, quoting: a shell pipeline inside a
  # JSON string inside a Nix string is three layers of escaping to get
  # wrong.
  #
  # Claude Code passes the hook a JSON object on stdin; `.tool_response
  # .filePath` is the authoritative path after the write, with
  # `.tool_input.file_path` as the fallback for tools that do not echo it
  # back. Non-.nix writes fall through and do nothing.
  #
  # A nixfmt failure (normal while a file is mid-edit and not yet valid) is
  # reported as a systemMessage and the hook still exits 0: a formatter
  # should never be what blocks a turn.
  claude-nixfmt-hook = pkgs.writeShellApplication {
    name = "claude-nixfmt-hook";
    runtimeInputs = [
      pkgs.jq
      pkgs.nixfmt
    ];
    text = ''
      file=$(jq -r '.tool_response.filePath // .tool_input.file_path // empty')
      case "$file" in
        *.nix) ;;
        *) exit 0 ;;
      esac
      [ -f "$file" ] || exit 0
      if ! err=$(nixfmt "$file" 2>&1); then
        jq -nc --arg m "nixfmt failed on $file: $err" '{systemMessage: $m}'
      fi
    '';
  };
in
{
  # Claude Code itself was a plain entry in ./cli.nix until this file existed.
  # It moved here because `programs.claude-code` installs the package *and*
  # owns its config, and having the package come from one file and its MCP
  # servers from another is the kind of split that goes stale.
  programs.claude-code = {
    enable = true;

    # MCP servers written declaratively. The module does NOT write
    # ~/.claude.json — that file is Claude Code's own mutable state (project
    # history, onboarding flags) and home-manager owning it would fight the
    # CLI on every write. Instead it synthesises a plugin at
    # ~/.claude/skills/claude-code-home-manager carrying a .mcp.json, which
    # is read-only config the CLI only consumes. `claude mcp add` therefore
    # still works normally for one-off servers; the two do not collide.
    #
    # The flip side of the plugin route: tools land under the plugin's
    # namespace, so they are named `mcp__plugin_hm_github__<tool>` rather
    # than `mcp__github__<tool>`. That is the prefix used in `permissions`
    # below, and the one to use in any future allowlist entry.
    #
    # Requires Claude Code >= 2.1.157 for persistent personal plugins;
    # below that the module falls back to wrapping the binary with
    # --plugin-dir. nixpkgs is on 2.1.266.
    mcpServers.github = {
      type = "stdio";
      command = "${github-mcp-server-gh-auth}/bin/github-mcp-server-gh-auth";
    };

    # ~/.claude/CLAUDE.md — standing instructions for every session on this
    # machine, regardless of repo. Kept as a real markdown file rather than
    # a Nix string so it reads and diffs like prose.
    context = ./claude-code.md;

    # Setting this at all makes home-manager own ~/.claude/settings.json as
    # a read-only store symlink, which means `/config` in the TUI can no
    # longer persist a change — settings move here and get applied with a
    # rebuild instead. That is the deliberate trade for having them survive
    # a reinstall. `model` and `agentPushNotifEnabled` below are the two
    # keys carried over from the hand-written file this replaced.
    #
    # NOT set here on purpose: anything Claude Code writes to ~/.claude.json
    # instead (onboarding state, per-project history) — that file stays
    # entirely the CLI's.
    settings = {
      model = "opus";
      agentPushNotifEnabled = true;

      # Pre-approved tool calls. Everything listed is read-only, or cheap
      # and trivially reversible; the rule is that nothing here can change
      # the running system, publish anything, or lose work.
      #
      # `Bash(cmd:*)` is a prefix match — `Bash(git log:*)` covers
      # `git log --oneline -5` but not `git push`. Verified against this
      # Claude Code build that the prefix form matches and that an empty
      # allow list blocks, so these entries are doing real work.
      #
      # Deliberately absent, so they keep prompting: `just switch`,
      # `just boot`, `just update`, `nixos-rebuild`, `git commit`,
      # `git push`, `git reset`, `git checkout`, and every MCP write tool.
      permissions.allow = [
        # This repo's pre-flight and build recipes. `switch`/`boot`/`update`
        # are the state-changing verbs and are not here.
        "Bash(just verify)"
        "Bash(just check)"
        "Bash(just fmt)"
        "Bash(just build)"
        "Bash(just home)"
        "Bash(just diff)"
        "Bash(just needs-reboot)"
        "Bash(just show)"
        "Bash(just have:*)"
        "Bash(just --list)"

        # Read-only git. `git add` is included because staging is
        # reversible and never loses work; committing is not.
        "Bash(git status:*)"
        "Bash(git diff:*)"
        "Bash(git log:*)"
        "Bash(git show:*)"
        "Bash(git blame:*)"
        "Bash(git branch:*)"
        "Bash(git remote:*)"
        "Bash(git stash list:*)"
        "Bash(git add:*)"

        # Nix introspection. `nix build` is absent: it is not dangerous but
        # it is slow and worth an explicit yes.
        "Bash(nix eval:*)"
        "Bash(nix search:*)"
        "Bash(nix flake show:*)"
        "Bash(nix flake metadata:*)"
        "Bash(nix path-info:*)"
        "Bash(nix why-depends:*)"
        "Bash(nix store diff-closures:*)"
        "Bash(nvd diff:*)"

        # Reading and searching the filesystem.
        "Bash(rg:*)"
        "Bash(fd:*)"
        "Bash(grep:*)"
        "Bash(find:*)"
        "Bash(ls:*)"
        "Bash(eza:*)"
        "Bash(cat:*)"
        "Bash(bat:*)"
        "Bash(head:*)"
        "Bash(tail:*)"
        "Bash(wc:*)"
        "Bash(stat:*)"
        "Bash(file:*)"
        "Bash(readlink:*)"
        "Bash(sed -n:*)" # -n only: no in-place editing

        # System state, read-only.
        "Bash(systemctl status:*)"
        "Bash(systemctl --user status:*)"
        "Bash(systemctl list-units:*)"
        "Bash(systemctl --user list-units:*)"
        "Bash(journalctl:*)"

        # /nix/store is immutable and world-readable, and gets read
        # constantly when working on this config. Reads elsewhere outside
        # the working directory still prompt.
        "Read(//nix/store/**)"

        # github-mcp-server, read side only. Names carry the plugin
        # namespace described above. Every write tool (issue_write,
        # pull_request_review_write, push_files, create_*, delete_file,
        # merge_pull_request, update_*) is deliberately omitted.
        "mcp__plugin_hm_github__get_me"
        "mcp__plugin_hm_github__get_commit"
        "mcp__plugin_hm_github__get_file_contents"
        "mcp__plugin_hm_github__get_label"
        "mcp__plugin_hm_github__get_latest_release"
        "mcp__plugin_hm_github__get_release_by_tag"
        "mcp__plugin_hm_github__get_tag"
        "mcp__plugin_hm_github__get_team_members"
        "mcp__plugin_hm_github__get_teams"
        "mcp__plugin_hm_github__issue_read"
        "mcp__plugin_hm_github__pull_request_read"
        "mcp__plugin_hm_github__list_branches"
        "mcp__plugin_hm_github__list_commits"
        "mcp__plugin_hm_github__list_issues"
        "mcp__plugin_hm_github__list_issue_fields"
        "mcp__plugin_hm_github__list_issue_types"
        "mcp__plugin_hm_github__list_pull_requests"
        "mcp__plugin_hm_github__list_releases"
        "mcp__plugin_hm_github__list_repository_collaborators"
        "mcp__plugin_hm_github__list_tags"
        "mcp__plugin_hm_github__search_code"
        "mcp__plugin_hm_github__search_commits"
        "mcp__plugin_hm_github__search_issues"
        "mcp__plugin_hm_github__search_pull_requests"
        "mcp__plugin_hm_github__search_repositories"
        "mcp__plugin_hm_github__search_users"
      ];

      hooks.PostToolUse = [
        {
          matcher = "Write|Edit";
          hooks = [
            {
              type = "command";
              command = "${claude-nixfmt-hook}/bin/claude-nixfmt-hook";
              statusMessage = "nixfmt";
              timeout = 30;
            }
          ];
        }
      ];
    };
  };
}
