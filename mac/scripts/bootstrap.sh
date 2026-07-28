#!/usr/bin/env bash
# Installs the toolchain needed to build & package loadcli.
set -euo pipefail

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew não encontrado. Instale em https://brew.sh e rode de novo."
  exit 1
fi

echo "Instalando ferramentas de build…"
brew install xcodegen create-dmg xcbeautify

echo "OK. Toolchain pronto:"
for t in xcodegen create-dmg xcbeautify; do
  printf "  %-12s %s\n" "$t" "$(command -v $t || echo 'faltando')"
done
echo
echo "Xcode necessário (xcodebuild, notarytool, stapler):"
xcodebuild -version | head -1 || echo "  Xcode não encontrado — instale pela App Store."
