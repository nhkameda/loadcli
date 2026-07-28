#!/usr/bin/env bash
# Empacota um DMG a partir de um build Release já assinado ad-hoc.
#
# É o caminho SEM notarização: serve para publicar enquanto não existe um
# certificado Developer ID. O macOS vai avisar na primeira abertura, e o site
# explica como abrir mesmo assim. Quando o certificado existir, use
# `make sign-notarize` — aí o aviso some.
#
#   scripts/package_dmg.sh build/Build/Products/Release/loadcli.app
set -euo pipefail

APP="${1:?uso: package_dmg.sh <caminho/loadcli.app>}"
ENT="Sources/loadcli/Resources/loadcli.entitlements"
DIST="dist"
mkdir -p "$DIST"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="$DIST/loadcli-$VERSION.dmg"

echo "==> Assinatura ad-hoc (com entitlements, sem hardened runtime)…"
# O hardened runtime só faz sentido com um certificado de verdade; com "-" ele
# apenas endurece o app sem nenhum ganho de confiança para o Gatekeeper.
codesign --force --deep --entitlements "$ENT" --sign - "$APP"
codesign --verify --verbose=2 "$APP"

echo "==> Gerando DMG…"
rm -f "$DMG"
create-dmg \
  --volname "loadcli" \
  --window-size 540 380 \
  --icon-size 110 \
  --icon "loadcli.app" 150 190 \
  --app-drop-link 390 190 \
  "$DMG" "$APP" || true   # create-dmg sai !=0 em avisos cosméticos

test -f "$DMG"
echo
echo "OK -> $DMG  ($(du -h "$DMG" | cut -f1))"
echo "Sem notarização: na 1ª abertura o usuário precisa de botão direito › Abrir."
