# OpenTether Windows Launcher

**Share your Windows PC's wired internet with your Android phone over a USB cable, in one click.**

Built on [**OpenTether**](https://github.com/pyd-07/NetcoN-OpenTether) by [pyd-07](https://github.com/pyd-07),
which does the actual tunnelling. This project is a Windows launcher around it: it installs everything,
wires up the USB connection, starts OpenTether, and helps you fix things when they break.

## Why this exists

Plenty of people work somewhere their phone has no signal and no Wi-Fi (basements, shielded
buildings, sites where guest Wi-Fi isn't offered) yet they're still expected to be reachable on
their phone. Their PC, though, has a perfectly good wired connection.

Windows' own hotspot needs a Wi-Fi card, and most USB reverse-tethering guides are long manual
procedures. This launcher turns it into: **plug in → double-click → tap Start VPN.**

> **Use responsibly.** Sharing a workplace connection with a personal device may be restricted by your
> organisation's IT policy. Check before you use it on a network you don't own.

## Quick start

1. On the phone: enable **Developer options → USB debugging**.
2. Plug the phone into the PC with a **data** USB cable.
3. [Download the latest release](../../releases/latest), unzip it anywhere, double-click **`Start-ReverseTether.bat`**.
4. Follow the prompts. When asked, open **OpenTether** on the phone and tap **Start VPN**.

Next time it's the same steps 2–4, and they take a few seconds.

## Requirements

- Windows 10 (21H2 or newer) or Windows 11, 64-bit Intel/AMD PC with virtualisation enabled (needed for WSL2)
- Any Android phone with USB debugging
- Admin rights on the PC for the first run (installing WSL and usbipd-win, sharing the USB device)

## What happens on first run

The launcher checks each piece and installs only what's missing:

| Step | Installs / does | You may be asked to |
|---|---|---|
| 1 | [usbipd-win](https://github.com/dorssel/usbipd-win) (via winget): passes the phone's USB to Linux | approve a Windows prompt |
| 2 | WSL2 + Ubuntu | create a Linux username/password, **restart, then run the launcher again** |
| 3 | `adb`, `lsusb`, `wget` inside Ubuntu | enter your Ubuntu password |
| 4 | OpenTether relay (downloaded from its official release) | |
| 5 | Finds your phone (by maker USB ID, or you type its BUSID) | plug in / enable USB debugging |
| 6 | Shares and attaches the phone to Ubuntu, starts **USB Auto-Attach** | approve an Administrator prompt (first time) |
| 7 | Checks ADB | tap **Allow USB debugging** on the phone |
| 8 | Installs the OpenTether app on the phone if missing | |
| | Starts the **OpenTether Relay** window | enter your Ubuntu password there |
| | Offers optional **torrent mode** | answer y/N |
| 9 | Checks the tunnel | open OpenTether, tap **Start VPN** |

Keep the two minimized windows, **OpenTether Relay** and **USB Auto-Attach**, open while you use it.

## Phone settings that matter

Many phones (OnePlus/OPPO/realme especially, also Xiaomi and Samsung) freeze apps in the background.
When OpenTether is frozen **the phone's internet stops**, even though everything looks connected.

1. **OpenTether → App info → Battery → Unrestricted** (or "Allow background activity").
   Do the same for apps that download in the background, such as a torrent client.
2. **Keep Mobile data ON.** With no Wi-Fi and no mobile data, OnePlus phones treat the phone as offline and
   freeze apps even when they're unrestricted. Your apps' traffic still goes over USB, not your data plan.
3. **Recommended:** Settings → VPN → OpenTether ⚙️ → **Always-on VPN** and **Block connections without VPN**.
   Android then guarantees no app uses mobile data directly; if the tunnel drops they get no internet instead.

## Torrent mode (optional)

Some ISPs and corporate networks block BitTorrent: downloads sit on "Downloading metadata" or 0 peers.
Torrent mode routes **only the phone's traffic** through free [Cloudflare WARP](https://one.one.one.one/)
(WireGuard, profile generated with [wgcf](https://github.com/ViRb3/wgcf)) inside Ubuntu. Windows and the PC's
own traffic are untouched.

```bat
wsl -d Ubuntu -- sudo bash torrent-vpn.sh up       :: on (the launcher can do this for you)
wsl -d Ubuntu -- sudo bash torrent-vpn.sh down     :: off (also off after a restart)
wsl -d Ubuntu -- sudo bash torrent-vpn.sh status
```

While on, all the phone's traffic exits through Cloudflare (bonus: working IPv6). WARP is free but not made
for torrenting, so speed varies; a paid VPN's WireGuard config can replace `~/warp/wgcf-profile.conf`.
Respect copyright law, your network's policy and Cloudflare's terms.

## When something goes wrong

Double-click **`Diagnose-ReverseTether.bat`**. It checks every link in the chain (read-only), marks each one
`[OK]`, `[WARN]` or `[FAIL]` with a hint, and saves `diagnostics.txt`.

See **[TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)** for every known problem and its fix.

## How it works

```
 Internet ← Windows (Ethernet) ← WSL2 Ubuntu ─ NAT ─ ot0 (TUN) ← OpenTether relay
                                                                      ↑ TCP 127.0.0.1:8765
                                                         adb reverse over USB (usbipd-win)
                                                                      ↑
                                       Android: OpenTether VpnService ← all app traffic
```

- OpenTether's Android app is a VPN that captures every IP packet from apps and sends it to the PC
  through one TCP stream that `adb reverse` carries over USB.
- The OpenTether relay in Ubuntu writes those packets into a TUN interface (`ot0`, phone = `10.0.0.1`), and
  Linux NATs them out to the internet through Windows. TCP, UDP and ICMP, IPv4 and IPv6, all work.
- Windows can't hand a USB device to WSL by itself; **usbipd-win** does that. `--auto-attach` re-attaches the
  phone automatically when it reconnects.

## Files

| File | Purpose |
|---|---|
| `Start-ReverseTether.bat` | The launcher |
| `Diagnose-ReverseTether.bat` + `diagnose.sh` | Read-only health check → `diagnostics.txt` |
| `torrent-vpn.sh` | Optional torrent mode (phone traffic through Cloudflare WARP) |
| `docs/TROUBLESHOOTING.md` | Problems and fixes |

## What it does NOT touch

No Windows routes, network adapters, Internet Connection Sharing, proxy or firewall settings. Inside Ubuntu,
the relay adds NAT rules that it removes when it stops; torrent mode adds rules that disappear on restart.

## Credits and acknowledgements

This launcher would be nothing without these projects. Please star them and report tunnel bugs to them:

- **[OpenTether](https://github.com/pyd-07/NetcoN-OpenTether)** by **pyd-07** (Apache-2.0): the relay and the
  Android app that do all of the tunnelling. The launcher downloads both, unmodified, from OpenTether's
  official releases.
- **[usbipd-win](https://github.com/dorssel/usbipd-win)** by Frans van Dorsselaer (GPL-3.0): USB passthrough to WSL.
- **[wgcf](https://github.com/ViRb3/wgcf)** by ViRb3 (MIT) and **Cloudflare WARP**: torrent mode.
- **Android platform-tools (adb)** and **WSL** by Google and Microsoft.

Launcher problems → open an issue here (attach `diagnostics.txt`).
Tunnel/app problems that also happen without this launcher → [OpenTether issues](https://github.com/pyd-07/NetcoN-OpenTether/issues).

## License

[MIT](LICENSE) for this launcher's own scripts. Bundled-by-download tools keep their own licenses (above).
