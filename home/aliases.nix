{
  # eza's own aliases (ls/ll/la/lla/lt) stay with programs.eza in ./cli.nix.
  programs.fish.shellAliases = {
    tree = "eza --tree --icons"; # lt doesn't come to hand
    glow = "glow --pager"; # fish's alias wraps `command glow`, no recursion
  };
}
