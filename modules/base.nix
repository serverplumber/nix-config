{ config, pkgs, ... }:
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

  # ***

  # CA trust for software built against a non-nixpkgs OpenSSL.
  #
  # NixOS's security/ca.nix writes exactly four paths — ssl/certs/{ca-bundle,
  # ca-certificates}.crt, pki/tls/certs/ca-bundle.crt and ssl/trust-source —
  # and deliberately not /etc/ssl/cert.pem, which is the BSD/macOS convention.
  # Anything compiled elsewhere with the stock OPENSSLDIR=/etc/ssl looks for
  # exactly that file.
  #
  # uv's standalone CPython is the case that bit here. It ships its own
  # OpenSSL 3.5.7, so it checks /etc/ssl/cert.pem (absent), falls back to
  # capath=/etc/ssl/certs (present) — and finds nothing, because a capath
  # needs `openssl rehash` hash symlinks and NixOS puts only two bundle files
  # there. Every TLS call then fails with CERTIFICATE_VERIFY_FAILED:
  #
  #   ssl.create_default_context().get_ca_certs()  ->  0 certs
  #
  # Belt and braces, because the two mechanisms cover different software:
  # the symlink fixes anything that hardcodes the path, while SSL_CERT_FILE
  # is what OpenSSL, requests/certifi and most language runtimes consult
  # first. Neither weakens verification — both point at the same system CA
  # bundle the rest of the machine already trusts.
  #
  # NOT a fix for containers: a container has its own /etc/ssl, so a rootless
  # podman image with this problem needs the bundle mounted in or baked into
  # the image instead.
  environment.etc."ssl/cert.pem".source =
    config.environment.etc."ssl/certs/ca-certificates.crt".source;

  environment.sessionVariables.SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";

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
