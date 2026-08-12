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
      binPath ? null,
      # "env" gives a full package (bin + share/applications, so it shows up in
      # the launcher). "script" gives the wrapped binary alone.
      #
      # env is right for almost everything. It fails on packages that ship
      # many binaries symlinked into their own lib/ — nixpak's override layer
      # then produces dangling symlinks and buildEnv refuses the collision.
      # LibreOffice is the one such package here; see its entry below.
      mode ? "env",
    }:
    let
      pak = (
        mkNixPak {
          config =
            { sloth, ... }:
            {
              # binPath is a plain string option with no null allowed, so only
              # define it when we actually have one.
              app = {
                inherit package;
              }
              // pkgs.lib.optionalAttrs (binPath != null) { inherit binPath; };

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
        }
      );
    in
    if mode == "script" then pak.config.script else pak.config.env;

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
    # doInstallCheck disabled: upstream's versionCheckPhase runs
    # `stremio --version`, which tries to create its data directory and dies
    # with PermissionDenied inside nix's build sandbox (no writable HOME).
    # The package simply cannot build as packaged on this nixpkgs pin —
    # measured 2026-08-10, it is the only thing in the whole closure that
    # failed. Skipping the check is safe; it tests nothing about the binary
    # beyond it being able to print a version string.
    package = pkgs.stremio-linux-shell.overrideAttrs (_: {
      doInstallCheck = false;
    });
    appId = "com.stremio.Stremio";
    rw = sloth: [
      (sloth.concat' sloth.homeDir "/.stremio-server")
      (sloth.concat' sloth.homeDir "/.config/stremio")
      (sloth.concat' sloth.homeDir "/Downloads")
    ];
  };

  ### LibreOffice — NO NETWORK. It opens untrusted documents and ships a macro
  ### engine; there is no reason for it to reach the internet.
  ### LibreOffice must use script mode. With mode = "env" the build dies:
  ###
  ###   pkgs.buildEnv error: two given paths contain a conflicting subpath:
  ###     dangling symlink .../nixpak-overrides-libreoffice/bin/soffice
  ###
  ### LibreOffice ships soffice/swriter/scalc/smath as symlinks into its own
  ### lib/libreoffice/program/. nixpak's override layer re-links each one, the
  ### links dangle, and buildEnv refuses the collision. Setting binPath does
  ### not help — measured; it fails identically on whichever binary comes
  ### first alphabetically.
  ###
  ### script mode yields bin/soffice alone and no share/applications, hence
  ### the hand-written desktop entry below.
  libreoffice = sandbox {
    package = pkgs.libreoffice-fresh;
    appId = "org.libreoffice.LibreOffice";
    mode = "script";
    binPath = "bin/soffice";
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

    # Chromium's Wayland backend double-counts scale on Hyprland: it
    # multiplies the legacy wl_output integer scale by the
    # wp_fractional_scale_v1 value instead of treating them as the same
    # measurement, so the whole UI renders ~2x too large (confirmed live —
    # GTK/Qt apps read the compositor scale correctly, only Chromium-family
    # browsers are affected). --disable-features=WaylandFractionalScaleV1
    # makes it fall back to the legacy protocol, which is correct here since
    # every monitor uses an integer scale (2) anyway. Upstream tracking:
    # https://github.com/hyprwm/Hyprland/discussions/11627
    (vivaldi.override {
      commandLineArgs = "--disable-features=WaylandFractionalScaleV1";
    })

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

    # ***

    ### Occasional-use tools. Unsandboxed for the same reason as VLC and
    ### Dolphin: they exist to open arbitrary files, so a cage would mean
    ### binding every directory you might ever point them at.

    krita # 6.0.2.1

    # Keyboard-driven video. VLC is a mouse-first GUI; mpv is a window you
    # shove in a tiling slot and drive from the keyboard. With yt-dlp on PATH
    # (home/cli.nix) `mpv <url>` plays YouTube/Twitch directly — no browser
    # tab, and it tiles like any other window. This is the "TV while coding"
    # combination; VLC stays for the times a GUI is actually wanted.
    mpv

    # PipeWire mixer. Without this there is NO way to set per-app volume or
    # switch output device outside the Plasma session — the media keys only
    # move the master. pwvucontrol is the PipeWire-native one (pavucontrol is
    # the older PulseAudio-era GUI).
    pwvucontrol

    # Screenshots. Nothing in a DE-less Wayland session provides this.
    # grim captures, slurp selects a region, swappy annotates.
    # niri has screenshots built in and uses its own; Hyprland calls these.
    grim
    slurp
    swappy

    # Fast, Wayland-native, keyboard-driven — suits a tiling session far
    # better than a thumbnail browser. `imv <file>`, hjkl to navigate.
    imv

    # Basic / Advanced (scientific) / FINANCIAL / Programming modes. The
    # financial mode is the reason for this one specifically — most
    # calculators do not have it. Self-contained GTK4, so unlike the GNOME
    # Calendar/Contacts family it needs no evolution-data-server or
    # gnome-keyring to work outside GNOME.
    gnome-calculator

    # Ships alongside as the power option: units, currency conversion,
    # symbolic algebra. Better than gnome-calculator at everything except
    # having a labelled financial mode.
    qalculate-gtk
  ])
  ++ [
    # Apple Music, from the project's own flake rather than nixpkgs (it is not
    # in nixpkgs at all). Free, unlike Cider — see package-migration.md §5c.
    #
    # Exposes bi-directional MPRIS over D-Bus as
    # org.mpris.MediaPlayer2.sidra, so the XF86AudioPlay/Next/Prev binds
    # already wired to playerctl in both compositors control it with no
    # extra configuration.
    inputs.sidra.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  # script mode drops share/applications, so LibreOffice would otherwise be
  # invisible to the launcher. `soffice` handles every document type and takes
  # --writer/--calc/--impress if you want a specific module.
  xdg.desktopEntries.libreoffice = {
    name = "LibreOffice";
    genericName = "Office Suite";
    exec = "soffice %U";
    icon = "libreoffice-startcenter";
    terminal = false;
    categories = [
      "Office"
      "X-Sandboxed"
    ];
  };

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
