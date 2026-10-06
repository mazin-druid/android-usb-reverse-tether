# Troubleshooting

**Start here:** double-click `Diagnose-ReverseTether.bat`. The first `[FAIL]` (or `[WARN]`) in its output
is almost always the cause. Find it below.

Every problem on this page actually happened while this launcher was being built.

---

## Phone has internet for a while, then it stops

**Most common cause: the phone froze the OpenTether app.** Everything still looks connected, but no data moves.

- Confirm: the diagnostics show `phone recently FROZE OpenTether`, or `ot0 packets` stop increasing between two runs.
- Fix:
  1. OpenTether → App info → Battery → **Unrestricted** / **Allow background activity**.
  2. **Turn Mobile data ON.** On OnePlus/OPPO/realme, having no Wi-Fi and no mobile data puts the phone in an
     "offline" power mode that freezes apps even when they're unrestricted. Traffic still uses USB.
  3. After changing settings: OpenTether → App info → **Force stop**, then open it and tap **Start VPN**.
     A phone doesn't unfreeze an already-frozen app just because you changed its settings.
- Stop-gap: keeping OpenTether open on screen also prevents the freeze.

## Internet stops and the phone disappeared from USB

- Confirm: diagnostics show the phone missing from `usbipd list`, or `adb sees no phone`.
- Cause: the phone's USB connection dropped, typically under heavy traffic, with a poor cable, or through a hub
  or front-panel port.
- Fix:
  - Keep the **USB Auto-Attach** window open; it re-attaches the phone by itself when it comes back
    (allow ~30–60 s for the tunnel to reconnect).
  - If it doesn't come back: unplug/replug, and check the phone's USB notification is set to **File transfer**.
  - If it keeps happening: use a shorter/better **data** cable and a USB port directly on the PC.
    Limiting download speed in heavy apps (e.g. torrent client speed limit) also helps.

## "No known phone maker found" / phone not detected

- The phone isn't in `usbipd list` at all:
  - Charge-only cable → use a data cable.
  - Phone USB mode → pull down notifications, tap the USB notification, choose **File transfer**.
  - USB debugging off → Settings → Developer options → **USB debugging**.
- The phone is listed but not recognised (uncommon maker): type its **BUSID** (e.g. `1-5`) when asked.

## "ADB is not authorized" / `unauthorized`

Unlock the phone; a **Allow USB debugging?** prompt appears. Tick **Always allow from this computer**, tap Allow.
No prompt? Developer options → **Revoke USB debugging authorizations**, then replug.

## "USB attach failed" / stuck at "Waiting for phone inside WSL"

- Approve the **Administrator** prompt (needed once per phone to "share" it).
- If the phone shows `Shared` but never `Attached`, run in an Administrator terminal:
  `usbipd bind --busid <BUSID> --force`, then rerun the launcher.
- Another program may hold the phone (Android Studio, phone-maker PC suites). Close it and replug.

## Relay window shows a password prompt / "Relay exited"

- The relay needs root to create the `ot0` interface. Type your **Ubuntu** password (not your Windows one).
  Characters don't show while typing; that's normal.
- Forgot it? In PowerShell: `wsl -d Ubuntu -u root passwd <your-linux-username>`.
- "Relay exited": close the window and run the launcher again.
- `startup failed: ... exec: "iptables": executable file not found`: fresh WSL Ubuntu images don't include
  iptables. The launcher installs it (v1.0.2+); on older versions run
  `wsl -d Ubuntu -- sudo apt-get install -y iptables`, then the launcher again.

## OpenTether shows connected, but no websites load

1. Run diagnostics. Look for `phone connected to relay` and `ot0 packets` going up.
2. If `phone not connected to relay`: in OpenTether tap **Stop**, then **Start VPN**.
3. If connected but nothing loads: does the PC itself have internet? If the PC uses a VPN or proxy, WSL may not get through.
4. Restart everything: close both windows, run `wsl --shutdown` in PowerShell, run the launcher again.

## Some apps say "Offline" even though browsing works

Some apps check Android's network type rather than real connectivity. With OpenTether the network is a
**VPN**, which Android reports as **metered**.

- Check the app for "Unmetered/Wi-Fi only" options and turn them off (e.g. LibreTorrent → Settings → Behaviour →
  *Unmetered connections only*).
- Frozen apps also show offline; see the first section.

## Torrents: "Downloading metadata" forever / 0 peers

Your ISP or network probably blocks BitTorrent. (Normal browsing works because it's ordinary HTTPS.)

- Turn on **torrent mode**: rerun the launcher and answer `y`, or `wsl -d Ubuntu -- sudo bash torrent-vpn.sh up`.
- Check: `wsl -d Ubuntu -- sudo bash torrent-vpn.sh status` shows a recent *latest handshake*.
- Protocol encryption in the torrent client (*Require*) alone is usually not enough against a blocking ISP.
- No incoming connections are possible through this setup (several layers of NAT), so very rare torrents with
  few seeders may still be slow.

## Is my phone using mobile data?

With OpenTether's VPN active, all app traffic goes over USB; mobile data being *on* just keeps the phone from
freezing apps. To make it guaranteed: Settings → VPN → OpenTether ⚙️ → **Always-on VPN** + **Block connections
without VPN**. A low **data usage limit** for the SIM is a good extra safety net. (Calls/SMS over LTE still use
the carrier network as normal.)

## WSL problems

- `Ubuntu could not be started` after installing: restart Windows, run the launcher again.
- "Virtualisation not enabled": enable **Intel VT-x / AMD-V (SVM)** in the PC's BIOS/UEFI.
- "There is no distribution with the supplied name": the launcher auto-detects `Ubuntu`, `Ubuntu-24.04`,
  `Ubuntu-22.04` and `Ubuntu-20.04`. If yours has another name (`wsl -l -v` lists them), set `DISTRO=<name>`
  at the top of `Start-ReverseTether.bat` and `Diagnose-ReverseTether.bat`. The `wsl -d Ubuntu ...` commands in
  these docs then need that name too.

## Reset everything (nothing is permanent, so this is safe)

```powershell
wsl -d Ubuntu -- sudo bash torrent-vpn.sh down   # if torrent mode was on
wsl --shutdown                                    # stops relay and all NAT rules
```
Close the USB Auto-Attach window, then run the launcher again.

## Still stuck?

[Open an issue](../../../issues) with:
- `diagnostics.txt` (it includes your phone model and ADB serial; remove them if you prefer)
- what you did and what you expected
- the last lines from the **OpenTether Relay** window

If the problem also happens with OpenTether alone (without this launcher), please report it to
[OpenTether](https://github.com/pyd-07/NetcoN-OpenTether/issues) instead.
