{
  writeShellApplication,
  networkmanager,
  coreutils,
  gnugrep,
  gawk,
}:

# mimic — MAC Imitation for Making It past Captive portals.
#
# A captive portal unlocks the MAC that clicked through it. The phone does the
# clicking (iOS pops the portal sheet on its own), then leaves the network;
# this puts the phone's private address on the laptop's profile for that
# network, so the laptop inherits the session.
#
#   mimic AA:BB:CC:DD:EE:FF [connection]   take over the phone's address
#   mimic --reset [connection]             drop the override
#   mimic --help
#
# connection defaults to the Wi-Fi profile currently up. The override is set
# per profile, so it never follows the laptop onto another network, and
# --reset falls back to the global `wifi.cloned-mac-address=preserve` in the
# NetworkManager config.
#
# Only one device may hold the address at a time — two associations with the
# same MAC knock each other off. Hence the closing reminder about Auto-Join:
# the phone rejoining on its own is the one collision this cannot see.
#
# No sudo: membership in the networkmanager group is what lets polkit allow
# modifying a system connection.
writeShellApplication {
  name = "mimic";

  runtimeInputs = [
    networkmanager
    coreutils
    gnugrep
    gawk
  ];

  text = ''
    usage() {
      echo "usage: mimic AA:BB:CC:DD:EE:FF [connection]" >&2
      echo "       mimic --reset [connection]" >&2
      echo "       mimic --help" >&2
      exit 2
    }

    help() {
      cat <<'EOF'
    mimic — MAC Imitation for Making It past Captive portals

    Take over a captive-portal session the phone already clicked through, by
    giving the laptop's Wi-Fi profile the phone's private MAC address.

    usage:
      mimic AA:BB:CC:DD:EE:FF [connection]   use this MAC on the profile and reconnect
      mimic --reset [connection]             drop the override and reconnect
      mimic --help                           show this

    connection defaults to the Wi-Fi profile that is currently connected.
    The MAC may use ':' or '-', in either case. On the iPhone it is under
    Settings → Wi-Fi → (i) → Private Wi-Fi Address.

    Only one device may use the address at a time: take the phone off the
    network, and turn off Auto-Join for it, before running this.
    EOF
    }

    # --escape no: a profile name may contain ':', which terse output would
    # otherwise backslash.
    active_wifi() {
      local dev
      dev=$(nmcli -t -f DEVICE,TYPE,STATE dev |
        awk -F: '$2 == "wifi" && $3 == "connected" { print $1; exit }')
      [ -n "$dev" ] || return 1
      nmcli -t --escape no -g GENERAL.CONNECTION dev show "$dev"
    }

    [ $# -ge 1 ] && [ $# -le 2 ] || usage

    if [ "$1" = --help ] || [ "$1" = -h ]; then
      help
      exit 0
    elif [ "$1" = --reset ]; then
      mac=""
    else
      mac=$(tr 'a-f-' 'A-F:' <<<"$1")
      grep -qE '^([0-9A-F]{2}:){5}[0-9A-F]{2}$' <<<"$mac" ||
        { echo "mimic: not a MAC address: $1" >&2; exit 2; }
      # Private (randomised) addresses set the locally-administered bit, so the
      # second hex digit is 2, 6, A or E. Anything else is a burned-in address.
      case ''${mac:1:1} in
        2 | 6 | A | E) ;;
        *) echo "mimic: $mac is not a private address — copied the phone's hardware MAC?" >&2 ;;
      esac
    fi

    conn=''${2:-}
    if [ -z "$conn" ]; then
      conn=$(active_wifi) ||
        { echo "mimic: no Wi-Fi connection is up; name one" >&2; exit 1; }
    fi

    nmcli con modify "$conn" wifi.cloned-mac-address "$mac"
    # The profile change does not touch the live link; bringing it up again
    # is what applies it.
    nmcli con up "$conn" >/dev/null

    dev=$(nmcli -t --escape no -g GENERAL.DEVICES con show "$conn")
    now=$(tr 'a-f' 'A-F' <"/sys/class/net/$dev/address")

    if [ -z "$mac" ]; then
      echo "$conn: override dropped, $dev is $now"
      exit 0
    fi

    if [ "$now" != "$mac" ]; then
      echo "mimic: $dev came up as $now, not $mac" >&2
      exit 1
    fi

    echo "$conn: $dev is now $mac"
    echo "Turn off Auto-Join for this network on the phone."
  '';
}
