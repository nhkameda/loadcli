# website/ — www.loadcli.com

Site institucional do loadcli. **Estático puro** (HTML/CSS/JS), quatro idiomas,
servido pelo Nginx do host no Hetzner. Sem Docker, sem porta, sem build no
servidor.

## Como funciona

Os quatro HTML são **gerados**, não editados à mão:

```
content/{en,es,zh,pt}.json   ← o texto mora aqui, um arquivo por idioma
tools/build.mjs              ← a estrutura HTML e os ícones SVG moram aqui
      ↓ node tools/build.mjs
index.html es.html zh.html pt.html en.html sitemap.xml robots.txt
```

Isso mantém `hreflang`, âncoras e estrutura idênticos entre as páginas — que é
exatamente o que sai de sincronia quando se edita quatro arquivos na mão. **Os
HTML gerados são versionados**, então o deploy continua sendo um `rsync` simples.

Para mudar texto: edite o JSON e rode `node tools/build.mjs`.
Para mudar estrutura ou ícone: edite `tools/build.mjs` e rode de novo.

## Regras que não podem ser quebradas

1. **`?v=N` obrigatório.** O Cloudflare guarda `assets/` por 7 dias e o token do
   servidor **não tem permissão de purge**. Mexeu em `assets/css/site.css` ou
   `assets/js/site.js` → suba `ASSET_VERSION` em `tools/build.mjs` e regere.
2. **Nada de CDN externo.** Fontes, JS e imagens são todos do próprio domínio —
   o site precisa funcionar atrás do Great Firewall e a CSP é `default-src 'self'`.
   A tipografia usa a pilha do sistema de propósito: no Mac isso renderiza a SF
   Pro de verdade, com zero bytes baixados.
3. **Âncoras em inglês nos quatro idiomas** (`#one-click`, `#card`, `#ai`,
   `#spaces`, `#download`). É o que permite trocar de idioma sem perder o lugar.
4. **Ordem da barra de idiomas: EN · ES · 中文 · PT.**
5. **Sem travessão na prosa** (cacoete de IA). Convenção da casa.
6. **A revelação na rolagem é enfeite, nunca requisito.** `site.js` tem uma rede
   de segurança que mostra tudo depois de 2,6 s, e há um `<noscript>` que
   desliga a animação. Conteúdo invisível por causa de JS é bug.

## Efeitos

- **Hero**: as três mesas se montando em `transform3d`, dirigidas pela variável
  CSS `--p` (0→1) que o `site.js` escreve a cada quadro conforme o palco rola.
- **Fundo**: mesh gradient WebGL do [Paper Shaders](https://github.com/paper-design/shaders)
  (Apache 2.0), vendorizado em `assets/js/vendor/paper-shaders/` — só os arquivos
  do fecho de dependências do mesh gradient. `LICENSE` e `NOTICE` vão junto,
  como a licença exige.
- **Rolagem**: [Lenis](https://github.com/darkroomengineering/lenis) (MIT),
  `assets/js/vendor/lenis.min.js`, exposto como `globalThis.Lenis`.
- `prefers-reduced-motion: reduce` desliga shader, parallax e a montagem do
  hero. Sem WebGL, o gradiente CSS por baixo assume.

## Ilustrações

`tools/gen-images.mjs` gera a arte de apoio com o Nano Banana Pro. A chave nunca
toca o disco: `.env` guarda só a referência `op://` e o 1Password resolve na
hora. O `op` trava quando chamado sem terminal, então **rode num terminal de
verdade**:

```bash
cd website && op run --env-file=.env -- node tools/gen-images.mjs
# ou, da raiz: make site-images
python3 tools/optimize-images.py     # obrigatório: 2K PNG de ~1,8 MB → WebP de ~15 KB
```

Só gera o que falta. Para refazer uma peça, passe o nome dela.

**Se o `op run` estourar o tempo de autorização** (acontece quando a chamada não
vem de um terminal), injete a chave direto no processo — ela continua sem tocar
o disco:

```bash
GEMINI_KEY="$(op read 'op://Personal/Hackton-Gemini-NanoBananaPro/credential')" \
  node tools/gen-images.mjs
```

Detalhe que engana: `op whoami` responde *"account is not signed in"* mesmo com
tudo funcionando, porque aquele subcomando exige uma conta adicionada pelo CLI.
O que vale como teste é o `op read`.

**Como as peças entram no layout.** Sempre por `background-image` em elemento
decorativo, nunca `<img>`: assim um arquivo que falte simplesmente não aparece.
Todas usam `mix-blend-mode: multiply` — elas vêm com fundo quase-branco, que em
`multiply` desaparece contra a página em vez de deixar uma moldura retangular. A
figura da seção "mesas" ainda leva uma máscara radial nas bordas, porque o
quase-branco dela é um pouco mais escuro que o da página.

Os PNG de 2K originais ficam fora do git (ver `.gitignore`); o site serve os
`.webp`, e as imagens de Open Graph viram `.jpg` (nem todo raspador lê WebP, e
em PNG cada card sairia com 700 KB).

## Deploy

```bash
./tools/deploy.sh          # ou, da raiz: make site-deploy
```

- Acesso **pela tailnet**: `root@100.82.35.78` (`server-hetzner-germany-01`).
  A porta 22 pública está fechada desde 2026-06-04 — o alias `ssh hetzner` não conecta.
- Raiz web: `/var/www/loadcli.com`, dono `www-data`.
- Vhost versionado em `deploy/nginx-loadcli.com.conf`. Dentro de `location`, use
  `expires` e **nunca** `add_header Cache-Control` — um `add_header` aninhado
  cancela a herança de todos os headers de segurança do bloco `server`.
- TLS: Let's Encrypt DNS-01 via Cloudflare. Zona nova exige
  `--dns-cloudflare-propagation-seconds 60`.
- DNS: `A loadcli.com` e `A www.loadcli.com` → `178.104.120.126`, **proxied**.
- `download/` fica fora do git (o binário vem do `make dmg`) mas é enviado pelo
  `deploy.sh` quando existe localmente.

Registro do deploy: `~/DEV/server-het/deploys/2026-07-29-loadcli-com.md`.
