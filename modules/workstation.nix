{ pkgs, ... }:
{
  # The baseline for a workstation: packages every user of a machine of this
  # type would want in a working session, whatever they use it for. A role,
  # not a host — a host imports this to say "I am a workstation", and a
  # different kind of machine would import a sibling instead.
  #
  # Where a package goes:
  #   ./base.nix — needed to repair a system that won't reach a desktop.
  #   here       — shared by every user of a workstation.
  #   home/      — one user's tools and taste.

  environment.systemPackages = with pkgs; [
    # MCP servers. Both are stdio servers a client spawns on demand, not
    # daemons, so all they need is a binary on PATH for any client (Claude
    # Code, the JetBrains IDEs in home/dev.nix) to point its server config
    # at. Claude Code's own wiring is in home/claude-code.nix.
    #
    # github-mcp-server needs GITHUB_PERSONAL_ACCESS_TOKEN in the client's
    # env; nothing here supplies one, deliberately — no secrets in this repo.
    github-mcp-server
    mcp-nixos # package / NixOS / home-manager option lookup

    # The common Linux toolbox that agents, and anyone else coming from a
    # mainstream distro, reach for without checking. Each miss costs a failed
    # call and a retry, every session.
    python3 # bare interpreter for one-off scripts; projects use devShells
    tree
    file

    # Structural search and rewrite: match by syntax tree, not by regex.
    ast-grep

    # Nix language server. Chosen over nil because it evaluates — option and
    # package completion come from real nixpkgs — where nil only analyses
    # syntax and names. Helix picks it up from PATH unconfigured; Claude Code
    # is pointed at it in home/claude-code.nix.
    nixd
  ];
}
