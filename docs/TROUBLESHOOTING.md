# Why isn't my fan found locally?

Short answer: the fan and your Mac are not on the same Wi‑Fi network, or macOS is blocking Local Network access
for the app. The app hears a fan's beacon once a second on UDP port 5625; if it hears none, it uses the cloud.

## Check, in order

1. **Same network.** Put the Mac and the fan on the same SSID and band. A guest network, an IoT network or a
   second router usually isolates them, and no beacon crosses.
2. **Local Network access.** System Settings → Privacy & Security → Local Network → Atomberg Console on.
   The app re-checks every 15 seconds and when you tap the wifi button.
3. **Router isolation.** Turn off AP isolation, client isolation or broadcast filtering for the network.
4. **Firewall.** The app must be allowed to receive incoming connections (UDP 5625).
5. **Tap the wifi button.** It opens a fresh socket and listens for a few seconds. The glyph says what it found.

## What you see

| Glyph | Meaning |
|---|---|
| `wifi` (teal) | a fan was heard; commands go over your Wi‑Fi and cost nothing |
| `wifi.exclamationmark` | listening, but no fan heard |
| `wifi.slash` | local control is off |

## Still nothing?

Open an issue and paste the last lines of `~/Library/Application Support/ATOMBERG/calls.log`.
It contains no secrets.
