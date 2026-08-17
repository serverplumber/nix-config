{
  config,
  lib,
  pkgs,
  ...
}:

# Offsite backup to an SD card you carry.
#
# The card is the point: cheap, pocketable, physically separate from the
# laptop, through an airport without comment, destroyable in a second. A cold
# init fits a lunch break and an incremental fits a coffee break, so the whole
# design is "start it, walk away, come back to a card that is safe to pull".
#
# ***
#
# WHY THIS IS ONE FILE, INCLUDING THE KEYBINDS.
#
# Binds are normally home-manager's business and would live in home/niri.nix
# and home/hyprland.nix. They are here instead, reaching into
# home-manager.users, on purpose: this is one feature, and a feature spread
# across four files is a feature nobody can lift out again. The stated plan is
# that this may become a single binary daemon later — when that happens the
# whole of it should be one file to read and one file to delete, not an
# archaeology exercise across the tree.
#
# The cost of that choice is the mkForce on Mod+Backspace below. It is
# signposted from home/niri.nix so the next person to wonder why their bind
# doesn't take effect finds this file.
#
# ***
#
# This supersedes the note at bluefin-to-nixos-migration.md:1399, which said
# the tool should live in a separate repo and that a Nix-native version must
# not be built as a substitute. Superseded deliberately, not forgotten.

let
  cfg = config.services.sdbackup;

  sdbackup = pkgs.callPackage ../pkgs/sdbackup.nix {
    # backup-excludes.txt is the single source of truth for exclusions
    # (CLAUDE.md). modules/backup.nix reads the same file. Never a second copy.
    excludeFile = ../backup-excludes.txt;
    inherit (cfg) budgetMinutes dueAfterDays;
  };

  noctalia = "${config.home-manager.users.${cfg.user}.programs.noctalia.package}/bin/noctalia";

  # Both actions are real scripts in the store rather than inline command
  # strings. niri's spawn-sh and Hyprland's exec_cmd have different quoting
  # rules, and Hyprland's config here is Lua — embedding a multi-line shell
  # snippet meant passing it through Lua string escaping *and* shell quoting at
  # once. A store path has no quoting problem in either, and both compositors
  # then run byte-identical logic, which is the actual goal.
  #
  # Lock FIRST, unconditionally, before anything else runs: backup logic must
  # never be able to stop the screen from locking. If sdbackup is broken the
  # worst outcome allowed is "no backup", never "laptop left unlocked" — hence
  # the lock on its own line, ahead of everything, and `|| true` after.
  lockThen =
    name: extra:
    pkgs.writeShellScript "sdbackup-${name}" ''
      ${noctalia} msg session lock
      ${extra}
    '';

  # Mod+Backspace: plain lock, then the nag. `on-lock` exits non-zero for "no
  # card" and friends — that is information, not failure, so it is swallowed.
  lockAndRemind = lockThen "lock-remind" ''
    ${lib.getExe sdbackup} on-lock || true
  '';

  # Mod+B: the deliberate "I'm going for a break" action. Caffeine stops the
  # compositor idling out under the run; sdbackup additionally takes a
  # systemd-inhibit lock, because swayidle calls `systemctl suspend` directly
  # at 600s and only logind can refuse that.
  lockAndBackup = lockThen "lock-backup" ''
    ${noctalia} msg caffeine-enable
    ${lib.getExe sdbackup} on-lock --backup || true
  '';

  # Plasma needs its own pair. noctalia does not run under Plasma — it is
  # started by niri/Hyprland, not by a user unit — so neither `session lock`
  # nor `caffeine-enable` exists there. loginctl is the session-agnostic lock,
  # and caffeine has no Plasma equivalent worth wiring: sdbackup already takes
  # a systemd-inhibit lock around the run, which is the part that actually
  # stops a suspend.
  plasmaLockThen =
    name: extra:
    pkgs.writeShellScript "sdbackup-plasma-${name}" ''
      ${pkgs.systemd}/bin/loginctl lock-session
      ${extra}
    '';

  plasmaLockAndRemind = plasmaLockThen "lock-remind" ''
    ${lib.getExe sdbackup} on-lock || true
  '';

  plasmaLockAndBackup = plasmaLockThen "lock-backup" ''
    ${lib.getExe sdbackup} on-lock --backup || true
  '';
in
{
  options.services.sdbackup = {
    enable = lib.mkEnableOption "offsite backup to a carried SD card";

    user = lib.mkOption {
      type = lib.types.str;
      default = "stablefly";
      description = "User whose home is backed up and whose session gets the keybinds.";
    };

    budgetMinutes = lib.mkOption {
      type = lib.types.int;
      default = 20;
      description = ''
        Refuse to start a run whose estimated duration exceeds this, unless
        --force. The estimate comes from this card's own measured throughput,
        not from a spec sheet, so the budget is checked rather than assumed.
      '';
    };

    dueAfterDays = lib.mkOption {
      type = lib.types.int;
      default = 7;
      description = "How stale a card must be before locking the screen nags about it.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      sdbackup
      pkgs.rustic # also useful by hand: `rustic -r <card>/restic snapshots`
      pkgs.exfatprogs # mkfs.exfat / fsck.exfat for preparing and checking cards
    ];

    # exFAT, not ext4, and the reason is not convenience: if this laptop dies
    # the card has to mount on whatever machine is to hand, including macOS.
    # An offsite backup only readable by the machine that failed is not an
    # offsite backup. The cost is that exFAT has no journal, which is why
    # sdbackup syncs before it says SAFE TO REMOVE and why `verify` refuses to
    # auto-repair.
    boot.supportedFilesystems = [ "exfat" ];

    home-manager.users.${cfg.user} = {
      # niri. "Mod+B" is new (verified free against the existing binds).
      # "Mod+Backspace" already exists in home/niri.nix as a plain lock, so it
      # must be mkForce'd to add the reminder — see the header comment.
      # "Mod+Alt+Backspace" is deliberately NOT touched: it means lock +
      # caffeine and keeps meaning exactly that.
      programs.niri.settings.binds =
        let
          inherit (config.home-manager.users.${cfg.user}.lib.niri.actions) spawn;
        in
        {
          # Lowercase `b` on purpose. niri treats Mod+B and Mod+b as the same
          # bind (defining both is a "duplicate keybind" error), while
          # Mod+Shift+b is a genuinely different one — so the capital in the
          # usual notation implies a Shift that is not actually pressed.
          # Written the way the key is really hit. The uppercase binds
          # elsewhere in home/niri.nix are left alone: those mirror niri's own
          # shipped default-config.kdl bind-for-bind, which is their whole
          # point.
          "Mod+b".action = spawn "${lockAndBackup}";
          "Mod+Backspace".action = lib.mkForce (spawn "${lockAndRemind}");
        };

      # Hyprland. `extraConfig` is a `lines` option, so this appends to the Lua
      # in home/hyprland.nix rather than colliding with it. Hyprland had no
      # lock bind at all before this, so both binds here are new.
      wayland.windowManager.hyprland.extraConfig = ''

        ---------------------------------------------------------------- sdbackup
        -- Offsite SD-card backup — see modules/sdbackup.nix.
        -- SUPER+Backspace locks and reminds; SUPER+b locks, caffeinates and backs up.
        -- Lowercase b, as in the niri bind: no Shift is involved and the
        -- notation should not imply one.
        hl.bind("SUPER + Backspace", hl.dsp.exec_cmd(${builtins.toJSON "${lockAndRemind}"}))
        hl.bind("SUPER + b",         hl.dsp.exec_cmd(${builtins.toJSON "${lockAndBackup}"}))
      '';

      # Plasma. plasma-manager's `overrideConfig` defaults to false, so this
      # declares two hotkeys and leaves every other Plasma setting alone —
      # the same "don't fight the in-app settings UI" reasoning that keeps
      # home/noctalia.nix's `settings` empty.
      programs.plasma = {
        enable = true;
        hotkeys.commands = {
          "sdbackup-lock-remind" = {
            name = "Lock and check offsite backup";
            key = "Meta+Backspace";
            command = "${plasmaLockAndRemind}";
          };
          "sdbackup-lock-backup" = {
            name = "Lock and back up to SD card";
            key = "Meta+B";
            command = "${plasmaLockAndBackup}";
          };
        };
      };
    };
  };
}
