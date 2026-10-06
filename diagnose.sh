#!/bin/bash
# Read-only health check of the WSL + phone side. Changes nothing, needs no sudo.
# Run by Diagnose-ReverseTether.bat, or directly: wsl -d Ubuntu -- bash diagnose.sh
RELAY=OpenTether-v0.9.5-beta.1-linux-amd64
ok()   { echo "  [OK]   $*"; }
warn() { echo "  [WARN] $*"; }
fail() { echo "  [FAIL] $*"; }

echo "== Ubuntu (WSL) =="
echo "  kernel $(uname -r)"
for t in adb lsusb wget iptables ip6tables; do command -v $t >/dev/null && ok "$t installed" || fail "$t missing -> run the launcher (it installs it)"; done

echo "== OpenTether relay =="
[ -x ~/$RELAY ] && ok "relay binary ~/$RELAY" || fail "relay binary missing -> run the launcher"
pgrep -f "$RELAY" >/dev/null && ok "relay running" || fail "relay not running -> run the launcher, enter sudo password in the Relay window"
if ip link show ot0 >/dev/null 2>&1; then
    ok "tunnel interface ot0 up ($(ip -br addr show ot0 | awk '{print $3, $4}'))"
    echo "  ot0 packets: from phone=$(cat /sys/class/net/ot0/statistics/rx_packets) to phone=$(cat /sys/class/net/ot0/statistics/tx_packets)"
else
    fail "ot0 missing -> relay not started or crashed (check the Relay window)"
fi
if ss -tn | grep -q ':8765.*ESTAB\|ESTAB.*:8765'; then ok "phone connected to relay"
else warn "phone not connected to relay -> open OpenTether on the phone and tap Start VPN"; fi

echo "== Torrent mode (optional) =="
if ip link show wg-ot >/dev/null 2>&1; then
    ok "on: phone traffic goes through Cloudflare WARP (wg-ot rx=$(cat /sys/class/net/wg-ot/statistics/rx_bytes)B tx=$(cat /sys/class/net/wg-ot/statistics/tx_bytes)B)"
    ip rule show | grep -q 51820 || warn "wg-ot exists but routing rule missing -> sudo bash torrent-vpn.sh up"
else
    echo "  off"
fi

echo "== USB / ADB =="
lsusb | grep -qiv "linux foundation" && lsusb | grep -iv "linux foundation" | sed 's/^/  usb: /' || fail "no USB device in WSL -> phone not attached (see Windows section)"
devs=$(adb devices | tail -n +2 | grep -v '^$')
if [ -z "$devs" ]; then fail "adb sees no phone -> USB not attached, or USB debugging off"; exit 0; fi
echo "$devs" | sed 's/^/  adb: /'
echo "$devs" | grep -q unauthorized && fail "phone unauthorized -> unlock it and accept the USB debugging prompt"
echo "$devs" | grep -q 'device$' || exit 0
adb reverse --list | grep -q 8765 && ok "adb reverse tcp:8765 set" || warn "adb reverse missing -> the relay sets it; restart the relay"

echo "== Phone =="
p() { adb shell "$@" 2>/dev/null | tr -d '\r'; }
echo "  $(p getprop ro.product.manufacturer) $(p getprop ro.product.model), Android $(p getprop ro.build.version.release)"
v=$(p dumpsys package com.opentether | grep -m1 versionName | sed 's/.*=//')
[ -n "$v" ] && ok "OpenTether app installed ($v)" || fail "OpenTether app not installed -> run the launcher"
p dumpsys connectivity | grep -q 'VPN CONNECTED extra: VPN:com.opentether' && ok "OpenTether VPN active" || warn "OpenTether VPN not active -> tap Start VPN"
[ "$(p settings get global airplane_mode_on)" = 1 ] && warn "airplane mode on -> phone may freeze OpenTether in background"
[ "$(p settings get global mobile_data)" = 1 ] && ok "mobile data on" || warn "mobile data off -> some phones (OnePlus/OPPO) freeze OpenTether; turn it on (traffic still uses USB)"
p dumpsys deviceidle whitelist | grep -q com.opentether && ok "OpenTether battery: unrestricted" || warn "OpenTether battery optimised -> App info > Battery > Unrestricted"
fr=$(p logcat -d | grep -E 'freeze uid: [0-9]+ com.opentether' | tail -3)
[ -n "$fr" ] && { warn "phone recently FROZE OpenTether (internet stops when this happens):"; echo "$fr" | sed 's/^/         /'; }
echo "  last OpenTether app events:"
p logcat -d | grep -E 'OT/' | grep -vE 'TUN inject|relay [0-9]+B|PING|PONG|TUN [0-9]+B|→ TUN' | tail -8 | sed 's/^/         /'
