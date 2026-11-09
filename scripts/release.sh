#!/bin/bash
# Publishes a release teammates can download (SPEC 11): builds Tally Mic from main, zips it, and
# creates a GitHub release named after the version in Resources/Info.plist, with the zip attached.
# Bump CFBundleShortVersionString in a PR first; after it's merged, run this from main.
set -euo pipefail
cd "$(dirname "$0")/.."

version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)"
tag="v$version"

fail() { echo "$1" >&2; exit 1; }
[[ "$(git branch --show-current)" == "main" ]] || fail "Releases come from main. Run: git checkout main"
git diff --quiet && git diff --cached --quiet || fail "There are uncommitted changes. Commit or discard them first."
git fetch -q origin main
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail "main isn't the same as GitHub's. Run: git pull"
gh auth status >/dev/null 2>&1 || fail "The GitHub CLI isn't signed in. Run: gh auth login"
if gh release view "$tag" >/dev/null 2>&1; then
    fail "$tag is already released. Bump CFBundleShortVersionString in Resources/Info.plist in a PR first."
fi

./scripts/build.sh

# Always the same name, so the README's download link (releases/latest/download/Tally-Mic.zip)
# always gets the newest release.
zip="build/Tally-Mic.zip"
rm -f "$zip"
# ditto keeps the app's signature and attributes intact, unlike plain zip.
/usr/bin/ditto -c -k --keepParent "build/Tally Mic.app" "$zip"

# Check what teammates will get: unzip a copy and verify its signature.
check="$(mktemp -d)"
trap 'rm -rf "$check"' EXIT
/usr/bin/ditto -x -k "$zip" "$check"
/usr/bin/codesign --verify --strict "$check/Tally Mic.app"

build_number="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "build/Tally Mic.app/Contents/Info.plist")"
notes="$(cat <<NOTES
Tally Mic $version (build $build_number), for Macs with Apple silicon on macOS 27 or later.

**To install:** download Tally-Mic.zip below, open it, and drag Tally Mic into your Applications folder. The first time you open it, macOS says it can't check it for malware, because Tally Mic isn't signed through Apple. Click Done, then go to System Settings > Privacy & Security, scroll down, and click Open Anyway next to "Tally Mic was blocked". You only do this once.

**To update:** quit Tally Mic (right-click its menu bar icon > Quit Tally Mic), then replace it in Applications with the new one. Your settings stay.

More in the [README](https://github.com/$(gh repo view --json nameWithOwner --jq .nameWithOwner)#readme). Found a problem or have an idea? [Open an issue](https://github.com/$(gh repo view --json nameWithOwner --jq .nameWithOwner)/issues/new/choose).
NOTES
)"
gh release create "$tag" "$zip" --title "Tally Mic $version" --notes "$notes"
echo "Released $tag: $(gh release view "$tag" --json url --jq .url)"
