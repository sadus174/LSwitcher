#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/release-preflight.sh
if [[ "${1:-}" == "--preflight-only" ]]; then exit 0; fi
if [[ $# != 0 ]]; then echo 'Usage: build-dmg.sh [--preflight-only]' >&2; exit 2; fi
if [[ "${REGENERATE_ICONS:-0}" == "1" ]]; then
    swift scripts/make-icons.swift
    "${ICON_PYTHON:-python3}" scripts/optimize-icons.py
    iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
fi
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
dmg="dist/LSwitcher-${version}.dmg"
notarize() {
    local file="$1" label="$2" directory="dist/notarization/$version"
    mkdir -p "$directory"
    xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$directory/$label-submit.json"
    local submission
    submission="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$directory/$label-submit.json")"
    xcrun notarytool log "$submission" --keychain-profile "$NOTARY_PROFILE" > "$directory/$label-log.json"
    python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1])).get("status")=="Accepted" else "Notarization was not accepted; inspect the saved Apple log")' "$directory/$label-submit.json"
    echo "Notarization accepted; review $directory/$label-log.json for warnings."
}

# Set UNIVERSAL=1 on a build host with the appropriate SDK to ship both architectures.
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    swift build -c release --arch arm64 --arch x86_64
    binary_dir="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
else
    swift build -c release
    binary_dir="$(swift build -c release --show-bin-path)"
fi
mkdir -p dist
stage="$(mktemp -d "${TMPDIR:-/tmp}/lswitcher-dmg.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
app="$stage/LSwitcher.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/LSwitcher" "$app/Contents/MacOS/LSwitcher"
strip -S -x "$app/Contents/MacOS/LSwitcher"
cp "$binary_dir/LSwitcherUpdater" "$app/Contents/MacOS/LSwitcherUpdater"
strip -S -x "$app/Contents/MacOS/LSwitcherUpdater"
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$app/Contents/MacOS/LSwitcherUpdater"
else
    codesign --force --sign - "$app/Contents/MacOS/LSwitcherUpdater"
fi
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/"
resource_bundle="$binary_dir/LSwitcher_LSwitcherCore.bundle"
if [[ ! -d "$resource_bundle" ]]; then
    echo "Missing dictionary resource bundle: $resource_bundle" >&2
    exit 1
fi
ditto "$resource_bundle" "$app/Contents/Resources/LSwitcher_LSwitcherCore.bundle"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$app"
else
    codesign --force --sign - "$app"
fi
codesign --verify --deep --strict "$app"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    # ZIP cannot carry a stapled ticket; staple the app before making the final ZIP.
    ditto -c -k --sequesterRsrc --keepParent "$app" "$stage/notarize.zip"
    notarize "$stage/notarize.zip" app
    xcrun stapler staple "$app"
    xcrun stapler validate "$app"
    codesign --verify --deep --strict "$app"
    spctl --assess --type execute --verbose=2 "$app"
    rm "$stage/notarize.zip"
fi
python3 scripts/check-size.py "$app"
mkdir -p dist/LSwitcher.app
rsync -a --delete "$app/" dist/LSwitcher.app/
if [[ "${WITH_UPDATE:-0}" == "1" ]]; then
    architecture="$(uname -m)"
    archive="dist/LSwitcher-${version}-${architecture}.zip"
    ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
    # Hash and sign only the final archive, after stapling has changed the app.
    swift scripts/sign-update.swift "$version" "$architecture" "$archive"
fi
ln -s /Applications "$stage/Applications"
hdiutil create -volname LSwitcher -srcfolder "$stage" -ov -format UDZO "$dmg"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    notarize "$dmg" dmg
    xcrun stapler staple "$dmg"
    xcrun stapler validate "$dmg"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
fi
hdiutil verify "$dmg"
echo "Created $dmg"
