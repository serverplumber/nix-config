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

  # LocalSend (home/gui.nix) listens on 53317 for both its UDP multicast
  # peer-discovery announcements and its HTTPS transfer server. The app
  # itself was confirmed listening on 0.0.0.0:53317/{tcp,udp} — this was
  # still failing to see other devices on the LAN because the default
  # firewall DROPs everything not explicitly allowed, and nothing opened
  # this port. 53317 is LocalSend's fixed default (changeable in its own
  # settings, in which case this needs to move with it) — measured
  # 2026-08-14.
  networking.firewall.allowedTCPPorts = [ 53317 ];
  networking.firewall.allowedUDPPorts = [ 53317 ];
}
