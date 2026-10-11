#!/bin/sh
# Fails when the app could reach the network from anywhere but its two doors, when a URL appears that is not on the
# allowlist, or when a third-party package is declared. Run by CI and by hand: scripts/check-egress.sh
set -eu
cd "$(dirname "$0")/.."

fail=0
bad() { printf 'egress: %s\n' "$1" >&2; fail=1; }

# 1. Network APIs may only appear in Cloud/ (HTTPS, one host) and LAN/ (UDP, your own network).
apis='URLSession|URLRequest\(|NWConnection|NWBrowser|NWListener|CFSocket|CFStream|socket\(AF_|WKWebView|NSAppleScript|Process\(\)'
hits="$(grep -rEn "$apis" Sources | grep -v '^Sources/ATOMBERG/Cloud/' | grep -v '^Sources/ATOMBERG/LAN/' || true)"
[ -z "$hits" ] || bad "network API outside Cloud/ and LAN/:
$hits"

# 2. Every URL literal must be on the allowlist: the API host, this repository, the licence text.
allowed='^https://(api\.developer\.atomberg-iot\.com|github\.com/ashwingopalsamy/atomberg-console|polyformproject\.org)(/|$)'
urls="$(grep -rEoh 'https?://[^"[:space:])>]+' Sources | sort -u | grep -Ev "$allowed" || true)"
[ -z "$urls" ] || bad "URL not on the allowlist:
$urls"

# 3. No third-party code, no transport-security exceptions.
if grep -q '\.package(' Package.swift; then bad "Package.swift declares a dependency"; fi
[ ! -e Package.resolved ] || bad "Package.resolved exists"
if grep -q 'NSAppTransportSecurity' Resources/Info.plist; then bad "Info.plist relaxes App Transport Security"; fi

[ "$fail" -eq 0 ] && printf 'egress: ok (one cloud host, UDP 5625/5600, no dependencies)\n'
exit "$fail"
