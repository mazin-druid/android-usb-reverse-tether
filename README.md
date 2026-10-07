# Android USB Reverse Tether for Windows

**Share your Windows 11 PC's internet with any Android phone over a USB cable, in one click.**
No Wi-Fi hotspot, no root, no phone-specific setup.

Built on [**OpenTether**](https://github.com/pyd-07/NetcoN-OpenTether) by [pyd-07](https://github.com/pyd-07),
which does the actual tunnelling. This project is a one-click Windows launcher around it: it installs
everything, wires up the USB connection, starts OpenTether, and helps you fix things when they break.

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
3. [Download the latest release](../../releases/latest), unzip it anywhere, double-click **`ReverseTether.bat`**.
4. Click **Connect**. When it says so, open **OpenTether** on the phone and tap **Start VPN**.

Next time: plug in, double-click, **Connect**.

## The window

```
 ● USB passthrough    installed
 ● Ubuntu (WSL)       Ubuntu
 ● Linux tools        adb, lsusb, wget, iptables
 ● OpenTether relay   v0.9.5-beta.1
 ● Phone              OnePlus 13 (1-5, 22d9:2769)
 ● Phone in Linux     attached (auto re-attach on)
 ● USB debugging      authorized
 ● OpenTether app     installed
 ● Relay running      running in the background
 ● Phone tunnel       connected - the phone is using this PC's internet      ← live
 ● Torrent mode       off                                                   ← live

 [Connect] [Disconnect]                            [Torrent mode: OFF]
 [Send files to phone] [Get files from phone] [Diagnostics] [Help]
```

- Each row turns **green** when that step is fine, **yellow** when it's waiting for you (with a hint), **red** on a problem.
- **Connect** runs every step and installs whatever is missing; it's safe to click again any time.
- **Disconnect** turns torrent mode off, stops the relay and gives the phone back to Windows.
- **Your Ubuntu password** is asked in a small box when needed. It's kept in memory for that session only, never saved.
- **Closing the window** asks whether to keep the phone's internet running in the background or disconnect.
- **Diagnostics** shows a full health report (with a *Copy report* and *Report a problem* button).

Prefer a console? **`Start-ReverseTether.bat`** does the same steps in a command window, with a text control panel.

## Requirements

- Windows 11, 64-bit Intel/AMD PC with virtualisation enabled (needed for WSL2).
  Windows 10 21H2+ should work too but is untested.
- Any Android phone (Android 8+) with USB debugging. No root needed.
- Admin rights on the PC for the first run (installing WSL and usbipd-win, sharing the USB device)

## What happens on first run

**Connect** checks each piece and installs only what's missing:

| Step | Installs / does | You may be asked to |
|---|---|---|
| USB passthrough | [usbipd-win](https://github.com/dorssel/usbipd-win) via winget | approve a Windows prompt |
| Ubuntu (WSL) | WSL2 + Ubuntu | create a Linux username/password, **restart, then open the app again** |
| Linux tools | `adb`, `lsusb`, `wget`, `iptables` inside Ubuntu | enter your Ubuntu password |
| OpenTether relay | downloaded from OpenTether's official release | |
| Phone | found by maker USB ID, or you pick it from a list | plug in / enable USB debugging |
| Phone in Linux | shares and attaches the phone to Ubuntu, with automatic re-attach | approve an Administrator prompt (first time) |
| USB debugging | checks ADB | tap **Allow** on the phone |
| OpenTether app | installs it on the phone if missing | approve any install prompt on the phone |
| Relay running | starts the relay in the background | enter your Ubuntu password |
| Phone tunnel | waits for the phone | open OpenTether, tap **Start VPN** |

## File transfer

**Send files to phone** and **Get files from phone** open a transfer window:

- **Send:** add files/folders (buttons or drag-and-drop from Explorer), pick the phone folder, choose **Copy** or **Move**.
- **Get:** browse a phone folder (Download, Camera, Pictures, Movies, Music, Documents), select several files
  (Ctrl/Shift-click or *Select all*), choose where to save on the PC (default **Downloads\From Phone**), **Copy** or **Move**.
- A progress bar shows bytes done, speed and **time left**; **Cancel** stops a transfer and removes the unfinished item.
- **Move** deletes each original only after that item has transferred successfully.

Transfers go straight over the USB link with `adb` at roughly **30–40 MB/s** (measured on a OnePlus 13:
31 MB/s to the phone, 37 MB/s back), much faster than going through the network. While tethering, the
phone is attached to Linux, so it doesn't show up as a drive in Windows Explorer; use the transfer window.
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
| `ReverseTether.bat` + `gui.ps1` | The app window (double-click `ReverseTether.bat`) |
| `Start-ReverseTether.bat` | Console version of the same launcher |
| `Diagnose-ReverseTether.bat` + `diagnose.sh` | Read-only health check → `diagnostics.txt` |
| `torrent-vpn.sh` | Optional torrent mode (phone traffic through Cloudflare WARP) |
| `transfer.ps1` | File transfer window |
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
