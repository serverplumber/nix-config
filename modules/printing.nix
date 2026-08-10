{ ... }: {
  services.printing.enable = true;

  # Driverless printing discovery (IPP Everywhere / AirPrint). Without avahi,
  # CUPS only sees printers you add by address by hand — network printers
  # simply do not appear, which reads as "printing is broken".
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  # ***

  # The `lp` group is already in users.users.stablefly.extraGroups (added for
  # the scanner, needed here too).
  #
  # Okular's sandbox has /run/cups/cups.sock and /etc/cups bound explicitly
  # (home/gui.nix) so it can print despite being boxed. If the printer list is
  # empty there but populated elsewhere, that bind is the thing to check.
}
