{
  inputs,
  pkgs,
  ...
}:
let
  mkNixPak = inputs.nixpak.lib.nixpak {
    inherit (pkgs) lib;
    inherit pkgs;
  };

  # Shared wrapper. Every app here gets: a Wayland socket, GPU, notifications,
  # its own config dir — and NOTHING else from $HOME. No ~/.ssh, no ~/code, no
  # ~/.aws. That is the entire point; nix does not give you this for free.
  #
  # `rw` and `ro` are FUNCTIONS of sloth, not lists. sloth only exists inside
  # the config function, so paths have to be built in there.
  #
  # ***
  #
  # ⚠️ The attribute names below are the least-verified thing in this repo.
  # `bubblewrap.sockets.*` and `gpu.enable` are believed correct but were not
  # confirmed against a real evaluation. If the first build complains about an
  # unknown option, this file is why — check https://github.com/nixpak/nixpak
  # for the current schema.
  sandbox =
    {
      package,
      appId,
      network ? true,
      rw ? (_: [ ]),
      ro ? (_: [ ]),
    }:
    (mkNixPak {
      config =
        { sloth, ... }:
        {
          app.package = package;
          flatpak.appId = appId;

          dbus.policies = {
            "org.freedesktop.portal.*" = "talk";
            "org.freedesktop.Notifications" = "talk";
          };

          gpu.enable = true;

          bubblewrap = {
            inherit network;
            sockets = {
              wayland = true;
              pipewire = true;
            };
            bind.rw = rw sloth;
            bind.ro = ro sloth;
          };
        };
    }).config.env;

  ### Obsidian — one vault directory, nothing else. Electron, and it indexes
  ### everything it can reach, so the narrower this is the better.
  ###
  ### The vault is not on this machine yet — most writing happens elsewhere.
  ### ~/Documents/obsidian_vault is created empty (see home.file below) so the
  ### bind target exists on first launch; drop the real vault in there later
  ### and nothing needs changing.
  obsidian = sandbox {
    package = pkgs.obsidian;
    appId = "md.obsidian.Obsidian";
    rw = sloth: [
      (sloth.concat' sloth.homeDir "/Documents/obsidian_vault")
      (sloth.concat' sloth.homeDir "/.config/obsidian")
    ];
  };

  ### Signal — own data dir plus somewhere to save attachments.
  signal = sandbox {
    package = pkgs.signal-desktop;
    appId = "org.signal.Signal";
    rw = sloth: [
      (sloth.concat' sloth.homeDir "/.config/Signal")
      (sloth.concat' sloth.homeDir "/Downloads")
    ];
  };

  ### Telegram — same shape.
  telegram = sandbox {
    package = pkgs.telegram-desktop;
    appId = "org.telegram.desktop";
    rw = sloth: [
      (sloth.concat' sloth.homeDir "/.local/share/TelegramDesktop")
      (sloth.concat' sloth.homeDir "/Downloads")
    ];
  };

  ### Okular — NO NETWORK, and it matters more here than anywhere else in this
  ### file. Untrusted PDFs (libgen and similar) go into poppler, which is a
  ### large C++ parser with a long CVE history. Cutting the network means a
  ### successful parser exploit has nothing to phone home to and nothing to
  ### exfiltrate to — and PDFs can embed JS and remote-content fetches of their
  ### own accord, which this also kills.
  ###
  okular = sandbox {
    package = pkgs.kdePackages.okular;
    appId = "org.kde.okular";
    network = false;
    rw = sloth: [
      (sloth.concat' sloth.homeDir "/Documents")
      (sloth.concat' sloth.homeDir "/Downloads")
      # Annotations, bookmarks and last-read position live in docdata — bind
      # rw or none of it survives a restart.
      (sloth.concat' sloth.homeDir "/.local/share/okular")
      (sloth.concat' sloth.homeDir "/.config/okularrc")
      (sloth.concat' sloth.homeDir "/.config/okularpartrc")

      # Printing. CUPS is reached over this unix socket, which the sandbox
      # otherwise cuts — the symptom is an empty printer list rather than an
      # error. Qt/KDE talks to CUPS directly, so the portal dbus policy above
      # does not cover it.
      "/run/cups/cups.sock"
    ];
    ro = sloth: [
      # PDFs living beside source. READ-ONLY on purpose: Okular never needs to
      # write here, and ro means a poppler exploit cannot modify the source
      # tree — which is most of the point of boxing this one up.
      (sloth.concat' sloth.homeDir "/code")

      # CUPS client config, so it knows which server to talk to.
      "/etc/cups"
    ];
  };

  ### Stremio — sandboxed on request, and it earns it: a streaming client that
  ### pulls from third-party addons and runs a local HTTP server on :11470.
  ### Network is obviously required, so the containment that matters here is
  ### filesystem — it sees its own dirs and nothing else.
  ###
  ### `stremio` proper was removed from nixpkgs in Feb 2026 (vulnerable qt5
  ### webengine); stremio-linux-shell is the replacement.
  stremio = sandbox {
    package = pkgs.stremio-linux-shell;
    appId = "com.stremio.Stremio";
    rw = sloth: [
      (sloth.concat' sloth.homeDir "/.stremio-server")
      (sloth.concat' sloth.homeDir "/.config/stremio")
      (sloth.concat' sloth.homeDir "/Downloads")
    ];
  };

  ### LibreOffice — NO NETWORK. It opens untrusted documents and ships a macro
  ### engine; there is no reason for it to reach the internet.
  libreoffice = sandbox {
    package = pkgs.libreoffice-fresh;
    appId = "org.libreoffice.LibreOffice";
    network = false;
    rw = sloth: [
      (sloth.concat' sloth.homeDir "/Documents")
      (sloth.concat' sloth.homeDir "/Downloads")
    ];
  };
in
{
  home.packages = [
    ### sandboxed via nixpak — see package-migration.md §1c
    obsidian
    signal
    telegram
    okular
    libreoffice
    stremio
  ]
  ++ (with pkgs; [
    ### plain nixpkgs, NOT sandboxed — deliberate, see the note below
    brave
    vivaldi
    firefox

    ### Tier 3 — sandboxing these would fight what they are for
    kdePackages.dolphin # needs to see all of $HOME; that IS the job
    obs-studio # screen capture, camera, virtual device
    proton-vpn # renamed from protonvpn-gui; rewrites routes and DNS — see modules/network.nix

    ### Deliberately NOT sandboxed, and not a future candidate either. It is
    ### used as a dev artifact — the front end to the accounting in `dirt` —
    ### so it has to reach dev data and test fixtures freely. Real financial
    ### data lives elsewhere. Jailing it would only make the work harder.
    gnucash

    ### Tier 3 — both want hardware a sandbox would take away
    prusa-slicer # USB to the printer, plus GPU for the 3D preview
    kdePackages.skanpage # needs SANE — see modules/scanning.nix

    ### Password manager. NOT sandboxed: its browser extension reaches the
    ### desktop app over native messaging, which a sandbox cuts — and the
    ### browsers are unsandboxed anyway, so a cage here would only break the
    ### pairing without protecting much.
    bitwarden-desktop

    ### Plays files from anywhere by definition — same argument as Dolphin.
    ### A sandbox would mean binding every directory you ever keep media in.
    vlc
  ]);

  # Creates ~/Documents/obsidian_vault so the sandbox bind target exists before
  # the vault itself does. Without it, nixpak binds a non-existent path and
  # Obsidian opens to an empty picker.
  home.file."Documents/obsidian_vault/.keep".text = "";

  # Browsers are installed the ordinary way on purpose. They keep full access
  # to $HOME, same as on any other distro — sandboxing them is Tier 2 and is
  # parked until there is a working system to iterate on.
  #
  # Worth being precise about what is and isn't lost: all three still have
  # their own internal sandbox (site isolation), which is what protects the
  # browser from the web. What's absent is the outer cage that would protect
  # ~/.ssh and ~/code from the browser.
  #
  # ***
  #
  # Two things that should already work, because of config elsewhere:
  #   - Wayland natively — NIXOS_OZONE_WL=1 is set in modules/hyprland.nix and
  #     applies session-wide, not just under Hyprland.
  #   - Screenshare and camera for the throwaway Brave conferencing profile,
  #     via xdg-desktop-portal + pipewire (modules/desktop.nix, audio.nix).
  #     This is the case that would have been hardest to get through a
  #     sandbox, and unsandboxed it is simply the normal path.
  #
  # If Vivaldi won't play H.264/proprietary media, it wants
  # `vivaldi-ffmpeg-codecs` alongside it. Not added pre-emptively.
}
