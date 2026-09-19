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
    # than `mcp__github__<tool>`. That is the prefix to use in any
    # permissions allowlist.
    #
    # Requires Claude Code >= 2.1.157 for persistent personal plugins;
    # below that the module falls back to wrapping the binary with
    # --plugin-dir. nixpkgs is on 2.1.266.
    mcpServers.github = {
      type = "stdio";
      command = "${github-mcp-server-gh-auth}/bin/github-mcp-server-gh-auth";
    };

    # `settings` is deliberately left unset. The module only writes
    # ~/.claude/settings.json when settings/marketplaces/disabled servers are
    # non-empty, and that file is currently hand-managed (and edited by the
    # CLI's own /config). Setting anything here would replace it with a
    # read-only store symlink and silently drop what is in it.
  };
}
