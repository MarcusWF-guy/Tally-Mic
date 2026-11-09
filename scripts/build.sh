#!/bin/bash
# Builds "build/Tally Mic.app" and signs it with the "Tally Local" certificate (SPEC 9, 11).
# The first build creates the certificate, which asks for your Mac password once.
set -euo pipefail
cd "$(dirname "$0")/.."

name="Tally Local"
if ! /usr/bin/security find-identity -p codesigning | grep -q "\"$name\""; then
    echo "Creating the \"$name\" certificate. macOS may ask for your Mac password."
    ./scripts/make-cert.sh
fi

swift build -c release --product TallyMic
bin_dir="$(swift build -c release --show-bin-path)"

app="build/Tally Mic.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/TallyMic" "$app/Contents/MacOS/TallyMic"
cp Resources/Info.plist "$app/Contents/Info.plist"

# The build number is the commit count, so Copy Diagnostics and the log show which build is running.
build_number="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$app/Contents/Info.plist"

/usr/bin/codesign --force --sign "$name" "$app"
/usr/bin/codesign --verify --strict "$app"
echo "Built $app (build $build_number)"
