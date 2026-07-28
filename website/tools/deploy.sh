#!/usr/bin/env bash
# Publica www.loadcli.com no Hetzner.
#
# O acesso é PELA TAILNET: a porta 22 pública está fechada desde 2026-06-04, o
# alias `ssh hetzner` (IP público) não conecta.
set -euo pipefail
cd "$(dirname "$0")/.."

HOST="${LOADCLI_HOST:-root@100.82.35.78}"      # server-hetzner-germany-01
KEY="${LOADCLI_SSH_KEY:-$HOME/.ssh/hetzner}"
ROOT="/var/www/loadcli.com"
SSH=(ssh -i "$KEY" -o StrictHostKeyChecking=accept-new "$HOST")

echo "→ regerando as páginas a partir de content/"
node tools/build.mjs

echo "→ site (4 idiomas) + assets"
rsync -az --delete --info=stats1 \
  -e "ssh -i $KEY -o StrictHostKeyChecking=accept-new" \
  --exclude '.DS_Store' --exclude 'content/' --exclude 'tools/' \
  --exclude 'deploy/' --exclude '.env' --exclude 'CLAUDE.md' --exclude 'download/' \
  ./ "$HOST:$ROOT/"

if compgen -G "download/*.dmg" > /dev/null; then
  echo "→ instalador"
  rsync -az --info=stats1 \
    -e "ssh -i $KEY -o StrictHostKeyChecking=accept-new" \
    download/ "$HOST:$ROOT/download/"
else
  echo "· sem download/*.dmg local, pulando o instalador"
fi

echo "→ permissões"
"${SSH[@]}" "chown -R www-data:www-data $ROOT"

echo "→ validando"
for path in / /es.html /zh.html /pt.html /robots.txt /sitemap.xml; do
  printf '  %-14s ' "$path"
  curl -s -o /dev/null -w "%{http_code}\n" "https://www.loadcli.com$path?cb=$RANDOM"
done
printf '  %-14s ' "apex→www"
curl -s -o /dev/null -w "%{http_code}\n" "https://loadcli.com/?cb=$RANDOM"

echo
echo "Lembrete: se mexeu em assets/css/site.css ou assets/js/site.js, suba o"
echo "ASSET_VERSION em tools/build.mjs — o Cloudflare guarda os assets por 7 dias"
echo "e o token do servidor não tem permissão de purge."
