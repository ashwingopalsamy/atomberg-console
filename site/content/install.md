# Install

**Short answer:** `brew install --cask ashwingopalsamy/tap/atomberg-console`, open it, paste your API key and refresh token once.

## Homebrew

```sh
brew install --cask ashwingopalsamy/tap/atomberg-console
```

## DMG

Download `Atomberg-Console-<version>.dmg` from the [latest release](https://github.com/ashwingopalsamy/atomberg-console/releases/latest), drag the app to Applications, and verify it first:

```sh
shasum -a 256 -c Atomberg-Console-*.dmg.sha256
gh attestation verify Atomberg-Console-*.dmg -R ashwingopalsamy/atomberg-console
```

The app is not notarised, because that needs a paid Apple Developer membership. macOS asks once: right-click the app and choose Open, or run `xattr -dr com.apple.quarantine "/Applications/Atomberg Console.app"`.

## From source

```sh
git clone https://github.com/ashwingopalsamy/atomberg-console && cd atomberg-console
scripts/bundle.sh && open "build/Atomberg Console.app"
```

Needs macOS 26 and Xcode 26 or its Command Line Tools. There are no dependencies to fetch.

## First run

1. In the Atomberg Home app, turn on Developer Mode and copy the API key and refresh token.
2. Open Atomberg Console and paste both. They are stored in your Keychain and sent only to Atomberg's API.
3. Allow Local Network access when macOS asks. That is what makes fans free to control.

## Uninstall

Quit with the power button, delete the app, then remove `~/Library/Application Support/ATOMBERG` and the Keychain item `com.ashwin.ATOMBERG`. With Homebrew: `brew uninstall --zap --cask atomberg-console`.
