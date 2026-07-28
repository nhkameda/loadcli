#!/usr/bin/env bash
# Sign (Developer ID) + notarize + staple + build a distributable DMG.
#
# Credentials come from the ENVIRONMENT (never commit secrets). Recommended:
#   op run --env-file=.env -- make sign-notarize
# where .env contains op:// references, e.g.
#   LOADCLI_SIGN_ID="op://Cofre/AppleDevID/identity"
#   LOADCLI_NOTARY_PROFILE="loadcli-notary"   # a stored `notarytool store-credentials` profile
# Or set LOADCLI_APPLE_ID / LOADCLI_TEAM_ID / LOADCLI_APP_PASSWORD instead of a profile.
set -euo pipefail

APP="${1:?uso: sign_notarize.sh <caminho/loadcli.app>}"
ENT="Sources/loadcli/Resources/loadcli.entitlements"
DIST="dist"
mkdir -p "$DIST"

: "${LOADCLI_SIGN_ID:?Defina LOADCLI_SIGN_ID com a identidade 'Developer ID Application: Nome (TEAMID)'}"

# Verify the Developer ID certificate is installed.
if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  echo "ERRO: nenhum certificado 'Developer ID Application' no Keychain."
  echo "  Crie em Xcode → Settings → Accounts → Manage Certificates → '+' → Developer ID Application,"
  echo "  ou em https://developer.apple.com/account/resources/certificates"
  exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="$DIST/loadcli-$VERSION.dmg"
ZIP="$DIST/loadcli-$VERSION.zip"

echo "==> Assinando (hardened runtime + timestamp)…"
# Sign nested code first, then the app bundle.
find "$APP/Contents" \( -name "*.dylib" -o -name "*.framework" -o -name "*.bundle" \) -print0 2>/dev/null |
  while IFS= read -r -d '' f; do
    codesign --force --options runtime --timestamp --sign "$LOADCLI_SIGN_ID" "$f"
  done
codesign --force --options runtime --timestamp \
  --entitlements "$ENT" --sign "$LOADCLI_SIGN_ID" "$APP"
codesign --verify --strict --verbose=2 "$APP"

# Build the notarization auth argument array.
if [ -n "${LOADCLI_NOTARY_PROFILE:-}" ]; then
  AUTH=(--keychain-profile "$LOADCLI_NOTARY_PROFILE")
elif [ -n "${LOADCLI_APPLE_ID:-}" ]; then
  AUTH=(--apple-id "$LOADCLI_APPLE_ID" --team-id "${LOADCLI_TEAM_ID:?}" --password "${LOADCLI_APP_PASSWORD:?}")
else
  echo "ERRO: defina LOADCLI_NOTARY_PROFILE (recomendado) ou LOADCLI_APPLE_ID/TEAM_ID/APP_PASSWORD."
  exit 1
fi

echo "==> Notarizando o app…"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" "${AUTH[@]}" --wait
xcrun stapler staple "$APP"

echo "==> Gerando DMG…"
rm -f "$DMG"
create-dmg \
  --volname "loadcli" \
  --window-size 540 380 \
  --icon-size 110 \
  --icon "loadcli.app" 150 190 \
  --app-drop-link 390 190 \
  "$DMG" "$APP" || true   # create-dmg returns nonzero on cosmetic warnings

echo "==> Notarizando o DMG…"
xcrun notarytool submit "$DMG" "${AUTH[@]}" --wait
xcrun stapler staple "$DMG"

echo "==> Verificação Gatekeeper:"
spctl -a -vvv --type install "$DMG" || spctl -a -vvv "$APP" || true
echo "OK -> $DMG"
