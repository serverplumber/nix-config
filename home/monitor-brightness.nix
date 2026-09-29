{ config, pkgs, ... }:
let
  # The compositors' own packages rather than nixpkgs': `hyprctl` must speak
  # the IPC of the Hyprland actually running, which comes from its flake.
  monitor-brightness = pkgs.callPackage ../pkgs/monitor-brightness.nix {
    niri = config.programs.niri.package;
    hyprland = config.wayland.windowManager.hyprland.package;
  };
  exe = pkgs.lib.getExe monitor-brightness;
in
{
  # Holds the gamma ramps the script dims through below the monitor's hardware
  # 0. Both compositors implement wlr-gamma-control, which it needs (niri's
  # checked in its v26.04 source). Only one client can hold an output's gamma,
  # so this rules out running noctalia's night light (wlsunset) alongside it —
  # switching that on would fight this for the same ramps.
  #
  # Starts at brightness 1 on every login: nothing saves the dimming, and a
  # session that comes up in a dark room at 0.1 is the worse surprise.
  systemd.user.services.wl-gammarelay-rs = {
    Unit = {
      Description = "Per-output gamma brightness over D-Bus";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "dbus";
      BusName = "rs.wl-gammarelay";
      ExecStart = pkgs.lib.getExe pkgs.wl-gammarelay-rs;
      Restart = "on-failure";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # Mod+Alt+digit rather than bare Alt+digit: browsers take Alt+1…9 for their
  # tabs, and a compositor bind would swallow those. Mod+Alt+digit is free in
  # both sessions — niri spends Mod+Ctrl+digit and Hyprland Mod+Shift+digit on
  # moving windows. 7/8 here, 9/0 for window transparency in
  # home/hyprland.nix: the lower key of each pair is the darker way.
  programs.niri.settings.binds =
    let
      inherit (config.lib.niri.actions) spawn;
    in
    {
      "Mod+Alt+7".action = spawn exe "-";
      "Mod+Alt+8".action = spawn exe "+";
    };

  # `extraConfig` is a `lines` option shared with home/hyprland.nix and
  # others, so these must not collide: nothing else binds SUPER + ALT + digit.
  wayland.windowManager.hyprland.extraConfig = ''

    ---------------------------------------------------- monitor brightness
    -- Focused monitor dimmer / brighter — see home/monitor-brightness.nix.
    hl.bind("SUPER + ALT + 7", hl.dsp.exec_cmd(${builtins.toJSON "${exe} -"}))
    hl.bind("SUPER + ALT + 8", hl.dsp.exec_cmd(${builtins.toJSON "${exe} +"}))
  '';
}
