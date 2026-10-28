#!/bin/bash
# DNS for the Control Center's DNS tile (modules/DnsSettings.qml).
#
#   dns.sh apply HOST V4 V6   point every connected Wi-Fi/Ethernet connection
#                             at that resolver, DNS over TLS
#   dns.sh apply off          back to the network's own (DHCP) DNS
#
# Per connection (ipv4/ipv6.dns as "IP#name", connection.dns-over-tls yes,
# ignore-auto-dns), then `nmcli device reapply` -- no reconnect. Not
# NetworkManager's global DNS, which would have covered every network at
# once: over D-Bus (GlobalDnsConfiguration) it rejects the dns+tls:// and
# "IP#name" forms -- the call succeeds and the setting comes back empty --
# and even a plain IP that it did keep never reached systemd-resolved's
# links here (NM 1.58). So DnsSettings re-runs `apply` when another
# network connects, and `off` resets every saved connection still pointing
# at a Mullvad resolver, not just the connected ones.
# Only connections with ipv4.method auto: the hotspot (shared) and VPNs
# keep their own DNS.
set -u

active_conns() {
    nmcli -t -f UUID,TYPE connection show --active | while IFS=: read -r uuid type; do
        case "$type" in 802-11-wireless|802-3-ethernet) ;; *) continue ;; esac
        [ "$(nmcli -g ipv4.method connection show "$uuid")" = auto ] && echo "$uuid"
    done
}

reapply() {
    local dev
    for dev in $(nmcli -g GENERAL.DEVICES connection show "$1" | tr ',' ' '); do
        nmcli device reapply "$dev" >/dev/null
    done
}

case "${1:-}" in
apply)
    rc=0
    if [ "${2:-}" = off ]; then
        nmcli -t -f UUID connection show | while read -r uuid; do
            nmcli -g ipv4.dns connection show "$uuid" 2>/dev/null | grep -q '#[a-z.]*dns\.mullvad\.net' || continue
            nmcli connection modify "$uuid" ipv4.dns "" ipv6.dns "" ipv4.ignore-auto-dns no ipv6.ignore-auto-dns no \
                connection.dns-over-tls -1 || exit 1
            nmcli -t -f UUID connection show --active | grep -qx "$uuid" && reapply "$uuid"
        done || rc=1
        exit $rc
    fi
    host=$2 v4=$3 v6=$4
    for uuid in $(active_conns); do
        # Already set: nothing to reapply (DnsSettings calls this on every
        # connection change, a reapply included).
        [ "$(nmcli -g ipv4.dns connection show "$uuid")" = "$v4#$host" ] && continue
        nmcli connection modify "$uuid" ipv4.dns "$v4#$host" ipv6.dns "$v6#$host" \
            ipv4.ignore-auto-dns yes ipv6.ignore-auto-dns yes connection.dns-over-tls yes || { rc=1; continue; }
        reapply "$uuid" || rc=1
    done
    exit $rc
    ;;
*)
    echo "usage: dns.sh apply HOST V4 V6 | apply off" >&2
    exit 2
    ;;
esac
