{ ... }: {
  # Brave itself is a user package (home/gui.nix). This module only strips
  # the upsell features, via enterprise policy, because policy is the one
  # setting Brave cannot override at runtime: a managed policy removes the
  # toolbar button and greys out the toggle in brave://settings, where a pref
  # in the profile would just be flipped back on by the next onboarding
  # prompt.
  #
  # ***
  #
  # The path is Brave's own, not Chromium's: Brave compiles in
  # /etc/brave/policies, so programs.chromium.extraOpts (which writes
  # /etc/chromium/policies) never reaches it. brave://policy shows what was
  # picked up.
  #
  # Tor windows, Speedreader and the Wayback Machine prompt are left alone —
  # they are privacy/reading tools rather than products being sold.
  environment.etc."brave/policies/managed/debloat.json".text = builtins.toJSON {
    BraveRewardsDisabled = true;
    BraveWalletDisabled = true;
    BraveVPNDisabled = true;
    BraveAIChatEnabled = false;
    BraveNewsDisabled = true;
    BraveTalkDisabled = true;
    BravePlaylistEnabled = false;

    # Telemetry: P3A analytics, the daily usage ping, and Web Discovery
    # (opt-in page-visit reporting for Brave Search).
    BraveP3AEnabled = false;
    BraveStatsPingEnabled = false;
    BraveWebDiscoveryEnabled = false;
  };
}
