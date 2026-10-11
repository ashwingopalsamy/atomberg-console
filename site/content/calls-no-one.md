# Calls no one

**Short answer:** Atomberg Console contacts one cloud host, `api.developer.atomberg-iot.com` over HTTPS, and your fans on UDP ports 5625 and 5600 on your own network. Nothing else.

![The app talks to the Atomberg API over HTTPS and to your fans over your Wi-Fi. Everything else is refused.](/atomberg-console/brand/egress.svg)

## The two doors

| Door | To | Why | Carries |
|---|---|---|---|
| Cloud client | `api.developer.atomberg-iot.com:443` | read and control devices | your API key, a short-lived token, device ids |
| LAN service | your fans, UDP 5625 and 5600 | local control | speed, power, light, timer |

## What is refused

Analytics, telemetry, update checks, crash reports, ads, any other host, any other port, any address that is not private, link-local, loopback or the broadcast address.

## How that is enforced

- `NetworkPolicy` checks every request and every datagram before it is sent.
- `scripts/check-egress.sh` fails CI if network code appears outside the two doors, if a URL is not on the allowlist, or if a package is added.
- There are no third-party packages. `Package.swift` has no dependencies.
- A test pins the policy, and another checks that the call log never holds a secret.

## Verify it yourself

```sh
lsof -nP -a -p "$(pgrep -x ATOMBERG)" -i      # every socket it has open
nettop -p "$(pgrep -x ATOMBERG)"              # live bytes per connection
tail -f "$HOME/Library/Application Support/ATOMBERG/calls.log"
```

You should see `api.developer.atomberg-iot.com:443` and UDP 5625. A firewall such as Little Snitch or LuLu shows the same. Read [the privacy page](/atomberg-console/privacy/) for what is stored and where.
