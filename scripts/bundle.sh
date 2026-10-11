#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

# The Xcode 27 SDK on this machine does not match the swift on PATH (swiftly), which fails to load
# Foundation. The Command Line Tools toolchain builds cleanly, so default to it unless overridden.
: "${DEVELOPER_DIR:=/Library/Developer/CommandLineTools}"
export DEVELOPER_DIR

swift build -c release

APP="build/Atomberg Console.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/ATOMBERG" "$APP/Contents/MacOS/ATOMBERG"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"

# The icon is drawn by the binary itself (`--render-icon`), so the repository holds no binary asset. It must exist
# before signing, because the signature seals the resources. A failure only costs the icon.
ICON_DIR="$(mktemp -d)"
ICONSET="$ICON_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"
if "$APP/Contents/MacOS/ATOMBERG" --render-icon "$ICON_DIR/base.png" 1024 && [ -f "$ICON_DIR/base.png" ]; then
  for size in 16 32 128 256 512; do
    double=$((size * 2))
    sips -z "$size" "$size" "$ICON_DIR/base.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z "$double" "$double" "$ICON_DIR/base.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" || printf 'warning: iconutil failed; no app icon.\n' >&2
else
  printf 'warning: could not render the app icon.\n' >&2
fi
rm -rf "$ICON_DIR"

# The brand SVGs are local and gitignored. They must be copied before signing, because the signature seals the resources.
if [ -d "Resources/Brand" ]; then
  mkdir -p "$APP/Contents/Resources/Brand"
  for svg in Resources/Brand/*.svg; do
    if [ -f "$svg" ]; then cp "$svg" "$APP/Contents/Resources/Brand/"; fi
  done
fi

# A stable identity keeps the Keychain items' access requirement and the Local Network permission across rebuilds.
# Ad hoc signing changes the code identity on every build, so every build would prompt again.
# An Apple Development certificate is preferred when one exists (free with any Apple ID: Xcode > Settings > Accounts >
# Manage Certificates > +). It carries a Team ID, which the Keychain's partition list keys on, so a rebuilt app stays
# trusted. The private self-signed identity below has no Team ID: the Keychain then trusts one exact code hash, and
# every rebuild prompts once more.
if [ -z "${SIGN_IDENTITY:-}" ]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -n 1)"
fi
IDENTITY="${SIGN_IDENTITY:-ATOMBERG Local Signing}"
# When the identity is not in the login keychain, one is made once, in a private keychain of its own. That touches
# neither the login keychain nor any trust setting: codesign signs with a self-signed identity without trust, and the
# designated requirement it produces (bundle id + this certificate) is what stays stable.
SIGN_KEYCHAIN="${SIGN_KEYCHAIN:-$HOME/.atomberg-signing/signing.keychain-db}"
# Protects only a throwaway identity in a keychain that is not in the search list.
SIGN_KEYCHAIN_PASSWORD="atomberg"

make_identity() {
  [ -f "$SIGN_KEYCHAIN" ] && return 0
  dir="$(dirname "$SIGN_KEYCHAIN")"
  mkdir -p "$dir" && chmod 700 "$dir" || return 1
  tmp="$(mktemp -d)" || return 1
  printf '[req]\ndistinguished_name = dn\nx509_extensions = ext\nprompt = no\n[dn]\nCN = %s\n[ext]\nbasicConstraints = critical,CA:false\nkeyUsage = critical,digitalSignature\nextendedKeyUsage = critical,codeSigning\n' "$IDENTITY" > "$tmp/cs.cnf"
  if /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -keyout "$tmp/key.pem" -out "$tmp/cert.pem" -days 3650 -config "$tmp/cs.cnf" >/dev/null 2>&1 \
    && /usr/bin/openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -out "$tmp/id.p12" -passout pass:atomberg >/dev/null 2>&1 \
    && security create-keychain -p "$SIGN_KEYCHAIN_PASSWORD" "$SIGN_KEYCHAIN" \
    && security set-keychain-settings "$SIGN_KEYCHAIN" \
    && security unlock-keychain -p "$SIGN_KEYCHAIN_PASSWORD" "$SIGN_KEYCHAIN" \
    && security import "$tmp/id.p12" -k "$SIGN_KEYCHAIN" -P atomberg -T /usr/bin/codesign >/dev/null \
    && security set-key-partition-list -S apple-tool:,apple: -s -k "$SIGN_KEYCHAIN_PASSWORD" "$SIGN_KEYCHAIN" >/dev/null 2>&1; then
    rm -rf "$tmp"
    return 0
  fi
  rm -rf "$tmp" "$SIGN_KEYCHAIN"
  return 1
}

# -v lists only identities trusted for signing, so the first branch is for a certificate the user trusted themselves.
if [ "${ATOMBERG_SIGN:-}" = "adhoc" ]; then
  # Release builds in CI: no certificate there, and an honest ad hoc signature is better than a made-up identity.
  codesign --force --deep --options runtime --sign - "$APP"
elif security find-identity -v -p codesigning | grep -F -q "\"$IDENTITY\"" && codesign --force --deep --options runtime --sign "$IDENTITY" "$APP"; then
  :
elif make_identity \
  && security unlock-keychain -p "$SIGN_KEYCHAIN_PASSWORD" "$SIGN_KEYCHAIN" \
  && codesign --force --deep --options runtime --sign "$IDENTITY" --keychain "$SIGN_KEYCHAIN" "$APP"; then
  :
else
  printf 'warning: could not sign with "%s"; signing ad hoc. Keychain access will prompt after each rebuild.\n' "$IDENTITY" >&2
  codesign --force --deep --options runtime --sign - "$APP"
fi

printf '%s\n' "$PWD/$APP"
