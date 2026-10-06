#!/bin/bash
# Route ONLY the phone's traffic (10.0.0.1 / fdcc::1 from OpenTether) through a
# free Cloudflare WARP WireGuard tunnel inside WSL, to get around ISP P2P blocking.
# WSL's own traffic and Windows are untouched. Nothing persists past a WSL restart.
#
#   sudo bash torrent-vpn.sh up | down | status
#
# Needs ~/warp/wgcf-profile.conf (made with: wgcf register --accept-tos && wgcf generate).
set -u
IF=wg-ot
TABLE=51820
HOME_DIR=$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)
CONF="$HOME_DIR/warp/wgcf-profile.conf"

[ "$(id -u)" = 0 ] || { echo "Run with sudo."; exit 1; }

up() {
    [ -f "$CONF" ] || { echo "Missing $CONF"; exit 1; }
    command -v wg >/dev/null || apt-get install -y wireguard-tools || exit 1
    if ! ip link show $IF >/dev/null 2>&1; then
        ip link add $IF type wireguard || exit 1
        # wg-quick strip drops Address/DNS/MTU so we never touch WSL's own routes or DNS.
        wg setconf $IF <(wg-quick strip "$CONF") || { ip link del $IF; exit 1; }
        for a in $(sed -n 's/^Address *= *//p' "$CONF" | tr ',' ' '); do
            ip addr add "$a" dev $IF
        done
        ip link set $IF mtu 1280 up
    fi
    ip route replace default dev $IF table $TABLE
    ip -6 route replace default dev $IF table $TABLE
    ip rule show | grep -q "from 10.0.0.1 lookup $TABLE" || ip rule add from 10.0.0.1 table $TABLE priority 100
    ip -6 rule show | grep -q "from fdcc::1 lookup $TABLE" || ip -6 rule add from fdcc::1 table $TABLE priority 100
    iptables -t nat -C POSTROUTING -s 10.0.0.1 -o $IF -j MASQUERADE 2>/dev/null ||
        iptables -t nat -A POSTROUTING -s 10.0.0.1 -o $IF -j MASQUERADE
    ip6tables -t nat -C POSTROUTING -s fdcc::1 -o $IF -j MASQUERADE 2>/dev/null ||
        ip6tables -t nat -A POSTROUTING -s fdcc::1 -o $IF -j MASQUERADE
    echo "Phone traffic now goes through Cloudflare WARP."
}

down() {
    ip rule del from 10.0.0.1 table $TABLE 2>/dev/null
    ip -6 rule del from fdcc::1 table $TABLE 2>/dev/null
    iptables -t nat -D POSTROUTING -s 10.0.0.1 -o $IF -j MASQUERADE 2>/dev/null
    ip6tables -t nat -D POSTROUTING -s fdcc::1 -o $IF -j MASQUERADE 2>/dev/null
    ip link del $IF 2>/dev/null
    echo "WARP route removed; phone traffic goes direct again."
}

status() {
    wg show $IF 2>/dev/null | grep -E 'endpoint|handshake|transfer' || echo "$IF is down"
    ip rule show | grep $TABLE
    ip -6 rule show | grep $TABLE
}

case "${1:-}" in
    up) up ;;
    down) down ;;
    status) status ;;
    *) echo "usage: sudo bash $0 up|down|status"; exit 1 ;;
esac
