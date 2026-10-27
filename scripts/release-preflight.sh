#!/bin/bash
set -euo pipefail
fail() { echo "Release preflight: $*" >&2; exit 1; }

if [[ "${REQUIRE_NOTARIZATION:-0}" == "1" ]]; then
    [[ -n "${SIGN_IDENTITY:-}" ]] || fail 'SIGN_IDENTITY is required for a trusted release.'
    [[ -n "${NOTARY_PROFILE:-}" ]] || fail 'NOTARY_PROFILE is required for a trusted release.'
fi
if [[ -n "${NOTARY_PROFILE:-}" && -z "${SIGN_IDENTITY:-}" ]]; then
    fail 'NOTARY_PROFILE requires a Developer ID Application SIGN_IDENTITY.'
fi
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    # Metadata only; do not export a private key or print keychain contents.
    identities="$(security find-identity -v -p codesigning)"
    if ! printf '%s' "$identities" | python3 -c '
import re,sys
requested=sys.argv[1]
entries=re.findall(r"([0-9A-Fa-f]{40})\s+\"([^\"]+)\"",sys.stdin.read())
sys.exit(0 if any((requested==key or requested==name) and name.startswith("Developer ID Application:") for key,name in entries) else 1)
' "$SIGN_IDENTITY"; then
        fail 'No matching valid Developer ID Application identity was found.'
    fi
fi
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun --find notarytool >/dev/null || fail 'notarytool is unavailable.'
    xcrun --find stapler >/dev/null || fail 'stapler is unavailable.'
    xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" --output-format json >/dev/null \
        || fail 'Notary profile is unavailable or Apple cannot be reached.'
fi
if [[ "${WITH_UPDATE:-0}" == "1" ]]; then
    [[ "${UNIVERSAL:-0}" != "1" ]] || fail 'Update manifests currently require a single architecture; build separate arm64/x86_64 packages.'
    [[ -f "${UPDATE_SIGNING_KEY:-keys/update-signing.key}" ]] || fail 'An update signing key is required; set UPDATE_SIGNING_KEY.'
fi
echo 'Release preflight passed.'
