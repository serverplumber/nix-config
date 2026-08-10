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
  # ⚠️ Okular cannot print. Its nixpak sandbox (home/gui.nix) cuts the CUPS
  # socket. That is independent of anything in this file — if PDF printing
  # matters, the hole has to be punched on the sandbox side.
}
