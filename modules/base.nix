{ pkgs, ... }:
{
  # System-level tooling: things which must work as root, before a user
  # session exists, or while the desktop is bork. Anything that is merely
  # convenient in a user shell belongs in home/cli.nix instead. This
  # file is deliberately small, because every entry here is in the closure
  # of every generation whether or not it is used.
  #
  # The rule of thumb: if you would need it to repair a system that will
  # not boot into a graphical session, it goes here.

  environment.systemPackages = with pkgs; [
    # nix won't function without git
    git

    # an editor
    helix

    # filesystem repair and inspection
    btrfs-progs
    gptfdisk

    # Diagnostics for the class of problem that leaves no graphical session
    # which unit failed, what is holding a mount, what hardware reports
    pciutils # lspci
    usbutils # lsusb
    lsof
    psmisc # fuser, killall, pstree

    # Network debugging from a VT when the desktop is down
    curl
    dnsutils
    iproute2

    # Nix-level introspection. Useful precisely when evaluation is failing
    # and the flake's devShell is therefore not reachable.
    nix-tree
  ];

  # Nerd Fonts, system-wide so every terminal/bar/prompt has icon glyphs
  # available regardless of which user or session is active. JetBrainsMono
  # is the default monospace face; the rest are here so there's a choice
  # without reaching for `nix-tree`/nixpkgs to find the attr name.
  fonts.packages = with pkgs.nerd-fonts; [
    jetbrains-mono
    fira-code
    caskaydia-cove
    meslo-lg
    iosevka
    monaspace
  ];

  fonts.fontconfig.defaultFonts.monospace = [ "JetBrainsMono Nerd Font" ];
}
