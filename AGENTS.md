# AGENTS.md

Guidance for coding agents working in this repository.

## What this is
A macOS 26 menu bar app (Swift 6, SwiftUI, no dependencies) that controls Atomberg fans, purifiers and locks.
Source-available under PolyForm Noncommercial 1.0.0. Unofficial; not affiliated with Atomberg.

## Commands
```sh
scripts/bundle.sh          # build and sign build/Atomberg Console.app
swift test                 # unit tests (24)
scripts/check-egress.sh    # network policy check, must pass
```
Set `DEVELOPER_DIR=/Library/Developer/CommandLineTools` if the Xcode toolchain fails to load Foundation.

## Rules that must hold
- Network code lives only in `Sources/ATOMBERG/Cloud` and `Sources/ATOMBERG/LAN`.
- One cloud host (`api.developer.atomberg-iot.com`), UDP 5625 and 5600 to private addresses. Enforced by
  `NetworkPolicy`; do not add destinations, packages, analytics or an updater.
- Never log credentials, tokens or request bodies. `calls.log` holds method, path, purpose, status only.
- Every cloud call spends the user's 100-a-day budget. Do not add reads without a reason.
- `docs/faq.json` is the source for the FAQ; a test keeps `FaqDetail.swift` in sync with it.
- Do not commit Atomberg's logo (`Resources/Brand/` is ignored).

## Conventions
Conventional Commits, subject under 50 characters. Small pull requests: what, why, how to check, risk.
Comments explain why, not what.

## Layout
`Sources/ATOMBERG/{App,Auth,Cloud,Domain,LAN,Persist,Store,UI}`, `Tests/ATOMBERGTests`, `docs/`, `site/` (the
project website), `scripts/`.
