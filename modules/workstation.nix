{ config, pkgs, ... }:
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

  # Mount the SD card slot on access. udisks2 runs, but only mounts when a
  # client asks, and niri/Hyprland have none — an inserted card just sat
  # unmounted. autofs does it at the system level, the same in every session.
  # sdbackup (modules/sdbackup.nix) finds its card through this.
  #
  # Keyed by slot (/dev/mmcblk0), which assumes a card formatted whole-device
  # with no partition table. `--ghost` makes /media/sdcard visible in a
  # directory listing before it is mounted, so a glob over /media/*/ triggers
  # the mount rather than seeing nothing. The short timeout unmounts an idle
  # card quickly, so it spends as little time as possible mounted-and-pullable.
  #
  # exFAT has no Unix ownership, so it is assigned at mount time: group
  # `users` with group write, i.e. any normal user of the workstation.
  services.autofs =
    let
      mediaMap = pkgs.writeText "auto.media" ''
        sdcard -fstype=exfat,rw,uid=0,gid=${toString config.users.groups.users.gid},fmask=0117,dmask=0007 :/dev/mmcblk0
      '';
    in
    {
      enable = true;
      autoMaster = ''
        /media file:${mediaMap} --ghost --timeout=60
      '';
    };
}
