{
  lib,
  writeShellApplication,
  ddcutil,
  brightnessctl,
  jq,
  util-linux,
  coreutils,
  gawk,
  systemd,
  niri,
  hyprland,
}:

# Step the brightness of whichever monitor has focus: `monitor-brightness -`
# or `+`. Bound to Mod+Alt+7 / Mod+Alt+8 in home/monitor-brightness.nix.
#
# The laptop panel has a kernel backlight and goes through brightnessctl like
# the XF86 keys do. An external monitor has none — its brightness lives in the
# monitor and is set over DDC/CI, an I2C bus that runs down the video cable,
# which is what ddcutil speaks (hardware.i2c in modules/hardware-keys.nix
# gives the user the bus devices).
#
# The monitor is picked by its EDID model string, which the compositor
# reports, rather than by I2C bus number. The LG hangs off the nvidia card,
# whose connectors carry no `ddc` link in sysfs, so there is no path from
# connector name to bus; the model string is the one identifier both sides
# share.
#
# Absolute set after a read, not ddcutil's relative `setvcp 10 + N`: the read
# gives the monitor's real maximum to clamp against, which is not always 100.
#
# Below the monitor's hardware 0 the dimming carries on in software: the
# wl-gammarelay-rs daemon (home/monitor-brightness.nix) scales the output's
# gamma ramp, down to a floor of 0.1. Dimming spends the hardware range first
# and brightening gives the software range back first, so the two read as one
# continuous slider. Gamma dims the picture, not the backlight — whites go
# grey, blacks stay black — which is why it only starts where DDC runs out.
# Without the daemon the software half is simply skipped.
writeShellApplication {
  name = "monitor-brightness";

  runtimeInputs = [
    ddcutil
    brightnessctl
    jq
    util-linux
    coreutils
    gawk
    systemd
    niri
    hyprland
  ];

  text = ''
    step=1
    soft_step=0.05
    soft_floor=0.1
    case "''${1:-}" in
      +) sign=1 ;;
      -) sign=-1 ;;
      *) echo "usage: monitor-brightness +|-" >&2; exit 2 ;;
    esac

    if [ -n "''${NIRI_SOCKET:-}" ]; then
      output=$(niri msg --json focused-output)
    elif [ -n "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
      output=$(hyprctl -j monitors | jq '.[] | select(.focused)')
    else
      echo "neither niri nor Hyprland is running" >&2; exit 1
    fi
    name=$(jq -r .name <<<"$output")
    model=$(jq -r .model <<<"$output")

    if [[ $name == eDP-* ]]; then
      if [ "$sign" = 1 ]; then
        brightnessctl --class=backlight set "+$step%" > /dev/null
      else
        brightnessctl --class=backlight set "$step%-" > /dev/null
      fi
      exit 0
    fi

    # A DDC round trip takes a noticeable fraction of a second. Presses that
    # land while one is in flight are dropped rather than queued, so holding
    # the key cannot pile up work that keeps changing the brightness after it
    # is released.
    exec 9> "''${XDG_RUNTIME_DIR:-/tmp}/monitor-brightness.lock"
    flock -n 9 || exit 0

    # The daemon names each output's object after the connector, `-` → `_`.
    relay() {
      busctl --user "$1" rs.wl-gammarelay "/outputs/''${name//-/_}" \
        rs.wl.gammarelay Brightness "''${@:2}"
    }
    # `d 0.85` → 0.85; empty when the daemon is not running.
    soft=$(relay get-property 2>/dev/null | awk '{print $2}' || true)
    set_soft() {
      relay set-property d "$(awk -v s="$soft" -v d="$1" -v f="$soft_floor" \
        'BEGIN { n = s + d; if (n > 1) n = 1; if (n < f) n = f; printf "%.2f", n }')"
    }

    if [ "$sign" = 1 ] && [ -n "$soft" ] && awk -v s="$soft" 'BEGIN { exit !(s < 1) }'; then
      set_soft "$soft_step"
      exit 0
    fi

    # --brief prints `VCP 10 C <current> <max>`.
    read -r _ _ _ current max < <(ddcutil --model "$model" getvcp 10 --brief)
    if [ "$sign" = -1 ] && (( current == 0 )); then
      [ -n "$soft" ] && set_soft "-$soft_step"
      exit 0
    fi
    new=$(( current + sign * step ))
    (( new < 0 )) && new=0
    (( new > max )) && new=$max
    ddcutil --model "$model" --noverify setvcp 10 "$new"
  '';

  meta = {
    description = "Step the focused monitor's brightness via backlight, DDC/CI, then gamma";
    license = lib.licenses.mit;
    mainProgram = "monitor-brightness";
  };
}
