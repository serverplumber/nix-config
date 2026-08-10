{ ... }: {
  # Tailscale is a daemon, not a package — installing `pkgs.tailscale` into a
  # home profile gives you the CLI and nothing to talk to. This module is the
  # actual install; it pulls the package in itself.
  services.tailscale.enable = true;

  # ***

  # ⚠️ ProtonVPN (home/gui.nix) and Tailscale both rewrite routes and DNS.
  # Running both at once is the thing most likely to produce "the network is
  # broken" on this machine — usually DNS resolution going somewhere
  # unexpected rather than a hard failure. Bring one up at a time until the
  # interaction is understood; Tailscale's exit-node feature and ProtonVPN's
  # tunnel are solving overlapping problems anyway.
  #
  # If ProtonVPN's WireGuard tunnel connects but carries no traffic, this is
  # the usual cause — strict reverse-path filtering drops the replies:
  #
  #   networking.firewall.checkReversePath = "loose";
  #
  # Not set pre-emptively; it weakens a real protection and may not be needed.
}
