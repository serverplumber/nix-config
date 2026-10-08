{ ... }: {
  # Firefox hardened by policy rather than by switching to a fork: LibreWolf
  # is mostly this same config on top of Firefox, and Zen lags Firefox's
  # security releases because its UI patches need rebasing every release.
  # Plain Firefox gets fixes the day Mozilla ships them.
  #
  # ***
  #
  # A NixOS module rather than home-manager because the NixOS one writes
  # /etc/firefox/policies/policies.json, which every Firefox profile obeys
  # and none can override. programs.firefox.preferences is turned into the
  # Preferences policy, which Firefox only honours for an allowlist of pref
  # prefixes (modules/policies/Policies.sys.mjs in omni.ja) — notably not
  # privacy.resistFingerprinting, which is left off anyway: it forces UTC
  # and letterboxing and breaks too many sites. about:policies shows what
  # was applied, and flags any policy name Firefox doesn't recognise.
  programs.firefox = {
    enable = true;

    policies = {
      DisableTelemetry = true;
      DisableFirefoxStudies = true;
      DontCheckDefaultBrowser = true; # Brave is the default, modules/mime.nix

      EnableTrackingProtection = {
        Value = true;
        Category = "strict";
        Locked = true;
      };
      HttpsOnlyMode = "force_enabled";

      SearchEngines = {
        Default = "DuckDuckGo";
        DefaultPrivate = "DuckDuckGo";
      };

      # Upsells, sponsored content, and anything else Mozilla puts in front
      # of you to read. The new tab keeps only search and your own shortcuts.
      FirefoxHome = {
        Search = true;
        TopSites = true;
        SponsoredTopSites = false;
        Highlights = false;
        Pocket = false;
        Stories = false; # "Popular today"
        SponsoredPocket = false;
        SponsoredStories = false;
        Weather = false;
        Snippets = false;
        Widgets.Enabled = false;
        Locked = true;
      };
      OverrideFirstRunPage = "";
      OverridePostUpdatePage = "";
      NoDefaultBookmarks = true;
      FirefoxSuggest = {
        SponsoredSuggestions = false;
        ImproveSuggest = false;
        Locked = true;
      };
      UserMessaging = {
        ExtensionRecommendations = false;
        FeatureRecommendations = false;
        MoreFromMozilla = false;
        WhatsNew = false;
        UrlbarInterventions = false;
        FirefoxLabs = false;
        SkipOnboarding = true;
        Locked = true;
      };
      GenerativeAI = {
        Enabled = false;
        Locked = true;
      };

      # Pulled from addons.mozilla.org at startup, not pinned by nix: the
      # pinned route (NUR's firefox-addons) is a package source outside
      # nixpkgs, and a blocklist engine is better kept current than pinned.
      ExtensionSettings."uBlock0@raymondhill.net" = {
        installation_mode = "force_installed";
        install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
      };

      # uBO's managed storage. Both keys replace rather than add, on every
      # start, so filters and lists belong here, not in the dashboard.
      "3rdparty".Extensions."uBlock0@raymondhill.net".toOverwrite = {
        filters = [
          # Wikipedia's donation banners, which CentralNotice injects here.
          "wikipedia.org###centralNotice"
        ];

        # uBO's default-on lists (the entries in its assets/assets.json
        # without "off": true) — they must be restated, since this replaces
        # the whole selection — plus the EasyList/uBO cookie-notice pair.
        # Cookie notices are hidden, not answered: Firefox's own
        # reject-for-you service (cookiebanners.*) is gone from current
        # releases, so there is nothing left that clicks "reject".
        filterLists = [
          "user-filters"
          "ublock-filters"
          "ublock-badware"
          "ublock-privacy"
          "ublock-unbreak"
          "ublock-quick-fixes"
          "easylist"
          "easyprivacy"
          "urlhaus-1"
          "plowe-0"

          "fanboy-cookiemonster"
          "ublock-cookies-easylist"

          # EasyList – Annoyances: donation appeals ("support the Guardian"),
          # newsletter, notification, chat and AI widgets.
          "easylist-annoyances"
          "easylist-newsletters"
          "easylist-notifications"
          "easylist-chat"
          "fanboy-ai-suggestions"
        ];
      };
    };

    preferences = {
      "privacy.globalprivacycontrol.enabled" = true;
      "privacy.fingerprintingProtection" = true;

      # Connections made to pages that were never clicked.
      "network.prefetch-next" = false;
      "network.dns.disablePrefetch" = true;
      "network.predictor.enabled" = false;
    };
  };
}
