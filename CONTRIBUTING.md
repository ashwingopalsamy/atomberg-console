# Contributing

Small, focused pull requests are easiest to review.

## Build and test

```sh
scripts/bundle.sh        # build and sign build/Atomberg Console.app
swift test               # unit tests
scripts/check-egress.sh  # network policy check
```

macOS 26 and Xcode 26 (or its Command Line Tools) are required. There are no dependencies to install.

### Signing

`scripts/bundle.sh` signs with an Apple Development certificate when you have one (free: Xcode › Settings ›
Accounts › Manage Certificates). Without one it makes a private self-signed identity under `~/.atomberg-signing`,
which works but makes the Keychain ask again after each rebuild. `ATOMBERG_SIGN=adhoc` forces an ad hoc signature.

## Rules that keep the app trustworthy

- Network code lives in `Sources/ATOMBERG/Cloud` and `Sources/ATOMBERG/LAN`, nowhere else.
- New hosts, ports or packages need a discussion first. `scripts/check-egress.sh` will fail without one.
- Never log credentials, tokens or request bodies.
- Every cloud call spends the user's 100-a-day budget. A change that adds one needs a reason in the PR.

## Commits

[Conventional Commits](https://www.conventionalcommits.org), short:

```
feat(ui): add speed control to fan rows
fix(lan): reopen the listener after permission changes
docs: explain the call budget
```

Subject under 50 characters, imperative, no full stop. Add a body only when the why is not obvious.

## Pull requests

Four lines: what, why, how to check, risk. Link an issue if there is one.

## Licence

By contributing you agree your work is under the [PolyForm Noncommercial License 1.0.0](LICENSE).
