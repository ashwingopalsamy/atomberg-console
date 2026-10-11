#!/bin/sh
# Prints the Homebrew cask for a release. Usage: scripts/cask.sh <version> <sha256>
# The tap keeps the file as Casks/atomberg-console.rb in github.com/ashwingopalsamy/homebrew-tap.
set -eu
[ $# -eq 2 ] || { printf 'usage: scripts/cask.sh <version> <sha256>\n' >&2; exit 1; }
cat <<EOF
cask "atomberg-console" do
  version "$1"
  sha256 "$2"

  url "https://github.com/ashwingopalsamy/atomberg-console/releases/download/v#{version}/Atomberg-Console-#{version}.dmg"
  name "Atomberg Console"
  desc "Menu bar console for Atomberg fans, purifiers and locks (unofficial)"
  homepage "https://github.com/ashwingopalsamy/atomberg-console"

  depends_on macos: ">= :tahoe"

  app "Atomberg Console.app"

  zap trash: [
    "~/Library/Application Support/ATOMBERG",
    "~/Library/Preferences/com.ashwin.ATOMBERG.plist",
  ]
end
EOF
