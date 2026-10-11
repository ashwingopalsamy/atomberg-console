# Privacy

Atomberg Console talks to two things and nothing else.

| To | How | Why | Carries |
|---|---|---|---|
| `api.developer.atomberg-iot.com` | HTTPS | read and control your devices | your API key, a short-lived token, device ids |
| your fans on your Wi‑Fi | UDP 5625 (listen), 5600 (commands) | local control | speed, power, light, timer |

No analytics. No crash reporting. No update check. No third-party code: `Package.swift` has no dependencies.

## How that is enforced

- `Cloud/NetworkPolicy.swift` refuses any URL that is not `https://api.developer.atomberg-iot.com`, and any UDP
  address that is not private, link-local, loopback or the broadcast address, on a port other than 5625 or 5600.
- `scripts/check-egress.sh` fails CI if a network API shows up outside `Cloud/` and `LAN/`, if a URL literal is
  not on the allowlist, or if a package is added.
- `Tests/ATOMBERGTests/NetworkPolicyTests.swift` pins the policy.
- The About window links to this repository. That opens your browser; the app itself makes no request.

## What is stored, and where

| What | Where |
|---|---|
| API key, refresh token, access token | macOS Keychain, item `com.ashwin.ATOMBERG` |
| Device list and last readings | `~/Library/Application Support/ATOMBERG/catalogue.json` |
| Calls used today | `~/Library/Application Support/ATOMBERG/quota.json` |
| One line per cloud request (method, path, status) | `~/Library/Application Support/ATOMBERG/calls.log` |

`calls.log` never contains headers, bodies or tokens (a test checks this).

## Check it yourself

```sh
# every socket the app has open
lsof -nP -a -p "$(pgrep -x ATOMBERG)" -i

# live bytes per connection
nettop -p "$(pgrep -x ATOMBERG)"

# what it asked the cloud for
tail -f "$HOME/Library/Application Support/ATOMBERG/calls.log"
```

You should see `api.developer.atomberg-iot.com:443` and UDP port 5625, and nothing else. A firewall such as
Little Snitch or LuLu will show the same.
