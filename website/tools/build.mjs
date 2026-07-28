#!/usr/bin/env node
/* Gera os quatro HTML estáticos a partir de content/<lang>.json.
 *
 *   node tools/build.mjs
 *
 * Suba o ASSET_VERSION ao mexer em assets/css/site.css ou assets/js/site.js:
 * o Cloudflare guarda os assets por 7 dias e o token do servidor não purga.
 */

import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');

const ASSET_VERSION = 12;
const SITE = 'https://www.loadcli.com';
const REPO = 'https://github.com/nhkameda/loadcli';
const DMG = '/download/loadcli-1.0.0.dmg';

const LANGS = [
  { code: 'en', file: 'index.html', hreflang: 'en', label: 'EN' },
  { code: 'es', file: 'es.html', hreflang: 'es', label: 'ES' },
  { code: 'zh', file: 'zh.html', hreflang: 'zh-CN', label: '中文' },
  { code: 'pt', file: 'pt.html', hreflang: 'pt-BR', label: 'PT' },
];

const esc = (s) =>
  String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

const ico = {
  github: '<svg viewBox="0 0 16 16" fill="currentColor" aria-hidden="true"><path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82a7.4 7.4 0 0 1 2-.27c.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8Z"/></svg>',
  apple: '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M16.36 12.72c-.02-2.3 1.88-3.4 1.96-3.46-1.07-1.56-2.73-1.78-3.32-1.8-1.41-.14-2.76.83-3.48.83-.72 0-1.83-.81-3-.79-1.55.02-2.97.9-3.77 2.28-1.61 2.79-.41 6.92 1.15 9.19.77 1.11 1.68 2.35 2.88 2.31 1.16-.05 1.6-.75 3-.75s1.79.75 3.01.72c1.24-.02 2.03-1.13 2.79-2.24.88-1.29 1.24-2.54 1.26-2.6-.03-.01-2.42-.93-2.44-3.69ZM14.1 5.9c.64-.77 1.07-1.85.95-2.92-.92.04-2.03.61-2.69 1.38-.59.68-1.11 1.77-.97 2.82 1.02.08 2.07-.52 2.71-1.28Z"/></svg>',
  win: '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M3 5.7 10.2 4.7v6.9H3V5.7Zm0 12.6 7.2 1v-6.8H3v5.8Zm8 1.1L21 21V12.8h-10v6.6Zm0-14.7v6.9h10V3l-10 1.7Z"/></svg>',
  dl: '<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M10 3v10m0 0 4-4m-4 4-4-4M3.5 15.5h13"/></svg>',
  arrow: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12h14m0 0-5.5-5.5M19 12l-5.5 5.5"/></svg>',
  play: '<svg viewBox="0 0 12 12" fill="currentColor" aria-hidden="true"><path d="M3 1.8v8.4l7-4.2z"/></svg>',
  folder: '<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M2.5 5.5A1.5 1.5 0 0 1 4 4h3.2l1.4 1.7H16a1.5 1.5 0 0 1 1.5 1.5v7.3A1.5 1.5 0 0 1 16 16H4a1.5 1.5 0 0 1-1.5-1.5v-9Z"/></svg>',
  globe: '<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="10" cy="10" r="7.2"/><path d="M2.8 10h14.4M10 2.8c1.9 2 2.9 4.5 2.9 7.2s-1 5.2-2.9 7.2c-1.9-2-2.9-4.5-2.9-7.2s1-5.2 2.9-7.2Z"/></svg>',
  code: '<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m7 6-4 4 4 4m6-8 4 4-4 4"/></svg>',
  pencil: '<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M13.6 3.9a1.7 1.7 0 0 1 2.4 2.4L7.4 15 4 16l1-3.4 8.6-8.7Z"/></svg>',
};

const SWATCHES = ['#7C5CFF', '#3B82F6', '#06B6D4', '#10B981', '#F59E0B',
                  '#EF4444', '#EC4899', '#8B5CF6', '#64748B', '#0EA5E9'];

/** Cabeçalho numerado de seção — a grade visível do manual técnico. */
const marker = (n, label, right = '') =>
  `<div class="marker"><b>${n}</b><span>${esc(label)}</span><span class="tnum">${esc(right)}</span></div>`;

/** Figura editorial. Sempre <img> com dimensões, para o layout não pular. */
const plate = (name, w, h, cap, tag, extra = '') =>
  `<figure class="figure"${extra}>
          <img class="plate" src="/assets/img/${name}.webp?v=${ASSET_VERSION}" width="${w}" height="${h}" alt="" loading="lazy" decoding="async">
          <figcaption class="figure__cap"><b>${esc(tag)}</b><span>${esc(cap)}</span></figcaption>
        </figure>`;

function render(c) {
  const self = LANGS.find((l) => l.code === c.lang);
  const canonical = `${SITE}/${self.file === 'index.html' ? '' : self.file}`;
  const alternates = LANGS.map(
    (l) => `  <link rel="alternate" hreflang="${l.hreflang}" href="${SITE}/${l.file === 'index.html' ? '' : l.file}">`
  ).join('\n');
  const langbar = LANGS.map(
    (l) => `<a href="/${l.file === 'index.html' ? '' : l.file}" hreflang="${l.hreflang}"${
      l.code === c.lang ? ' aria-current="true"' : ''}>${l.label}</a>`
  ).join('');
  const navLinks = c.nav.links.map((l) => `<a href="${l.href}">${esc(l.label)}</a>`).join('');
  const f = c.figures;

  return `<!doctype html>
<html lang="${self.hreflang}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <title>${esc(c.meta.title)}</title>
  <meta name="description" content="${esc(c.meta.description)}">
  <link rel="canonical" href="${canonical}">
${alternates}
  <link rel="alternate" hreflang="x-default" href="${SITE}/">
  <meta name="theme-color" content="#efebe3">
  <meta name="color-scheme" content="light">
  <link rel="icon" href="/assets/img/icon-128.png?v=${ASSET_VERSION}" sizes="128x128" type="image/png">
  <link rel="apple-touch-icon" href="/assets/img/icon-256.png?v=${ASSET_VERSION}">
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="loadcli">
  <meta property="og:locale" content="${c.meta.ogLocale}">
  <meta property="og:url" content="${canonical}">
  <meta property="og:title" content="${esc(c.meta.title)}">
  <meta property="og:description" content="${esc(c.meta.description)}">
  <meta property="og:image" content="${SITE}/assets/img/og-${c.lang}.jpg?v=${ASSET_VERSION}">
  <meta name="twitter:card" content="summary_large_image">
  <link rel="preload" as="font" type="font/woff2" href="/assets/fonts/instrument-serif-normal-400-latin.woff2" crossorigin>
  <link rel="preload" as="font" type="font/woff2" href="/assets/fonts/jetbrains-mono-normal-400-latin.woff2" crossorigin>
  <link rel="stylesheet" href="/assets/css/site.css?v=${ASSET_VERSION}">
  <noscript><style>[data-reveal],.enter>*,.term__line{opacity:1!important;transform:none!important}.track__cell::before{transform:scaleX(1)!important}</style></noscript>
</head>
<body data-lang="${c.lang}">
  <a class="skip-link" href="#one-click">${esc(c.nav.skip)}</a>

  <header class="nav">
    <div class="wrap nav__in">
      <a class="brand" href="/${self.file === 'index.html' ? '' : self.file}">
        <img src="/assets/img/icon-128.png?v=${ASSET_VERSION}" alt="" width="22" height="22">loadcli
      </a>
      <nav class="nav__links" aria-label="${esc(c.nav.aria)}">${navLinks}</nav>
      <div class="nav__right">
        <nav class="langbar" aria-label="${esc(c.nav.langAria)}">${langbar}</nav>
        <a class="iconlink" href="${REPO}" rel="noopener" aria-label="GitHub">${ico.github}</a>
      </div>
    </div>
  </header>

  <main>
    <!-- ================================================== hero -->
    <section class="bay hero">
      <div class="wrap">
        <div class="hero__grid enter">
          <div style="--i:0">
            <h1 class="display">${c.hero.title}</h1>
            <p class="lede hero__lede">${esc(c.hero.lead)}</p>
            <div class="hero__cta">
              <a class="btn" href="#download">${ico.dl}${esc(c.hero.ctaPrimary)}</a>
              <a class="btn btn--ghost" href="${REPO}" rel="noopener">${ico.github}${esc(c.hero.ctaSecondary)}</a>
            </div>
            <p class="hero__meta">${c.hero.meta.map((m) => `<span>${esc(m)}</span>`).join('')}</p>
          </div>
          <aside class="hero__aside note" style="--i:1">
            ${c.hero.aside.map((p) => `<p>${esc(p)}</p>`).join('\n            ')}
          </aside>
        </div>

        <div class="enter" style="margin-top:clamp(38px,6vh,74px)">
          <div class="window" style="--i:2" data-parallax="0.05">
            <div class="window__bar">
              <span class="tl"></span><span class="tl"></span><span class="tl"></span>
              <span>${esc(c.stage.deskLabel)}</span>
            </div>
            <div class="window__body">
              <div class="pane pane--web">
                <div class="wire wire--t"></div>
                <div class="wire wire--a"></div>
                <div class="wire wire--b"></div>
                <div class="wire__grid">
                  <div class="wire__box"></div><div class="wire__box"></div>
                  <div class="wire__box"></div><div class="wire__box"></div>
                </div>
              </div>
              <div class="pane pane--term term">
                <div class="dim">~/DEV/acme</div>
                <div><span class="sig">$</span> <span data-typed="${esc(c.stage.command)}"></span><span class="caret"></span></div>
                ${c.stage.output.map((l, i) =>
                  `<div class="term__line" style="animation-delay:${2400 + i * 280}ms"><span class="ok">✓</span> <span class="dim">${esc(l.text)}</span></div>`
                ).join('\n                ')}
              </div>
            </div>
          </div>
          <div class="window__cap" style="--i:3">
            <b>${esc(c.stage.capTag)}</b><span>${esc(c.stage.capText)}</span>
          </div>
        </div>
      </div>
    </section>

    <!-- ================================================== 01 ritual -->
    <section class="bay bay--paper2">
      <div class="wrap">
        ${marker('01', c.ritual.eyebrow, c.ritual.count)}
        <div class="split">
          <div>
            <h2 class="display">${c.ritual.title}</h2>
            <p class="lede" style="margin-top:22px" data-reveal>${esc(c.ritual.lead)}</p>
            <p class="punch" data-reveal style="--delay:90ms">${c.ritual.punch}</p>
          </div>
          <ul class="steps" data-reveal>
            ${c.ritual.steps.map((s, i) =>
              `<li><i>${String(i + 1).padStart(2, '0')}</i><s>${esc(s)}</s></li>`
            ).join('\n            ')}
            <li class="keep"><i>${String(c.ritual.steps.length + 1).padStart(2, '0')}</i><span>${esc(c.ritual.kept)}</span></li>
          </ul>
        </div>

        <div class="pair" style="margin-top:clamp(30px,5vh,58px)">
          ${plate('scene-before', 1400, 1050, f.before, f.beforeTag, ' data-reveal data-parallax="0.05"')}
          ${plate('scene-after', 1400, 1050, f.after, f.afterTag, ' data-reveal data-parallax="0.09" style="--delay:120ms"')}
        </div>
      </div>
    </section>

    <!-- ================================================== 02 um clique -->
    <section class="bay" id="one-click">
      <div class="wrap">
        ${marker('02', c.flow.eyebrow, '4')}
        <div class="split">
          <h2 class="display">${c.flow.title}</h2>
          <p class="lede" data-reveal>${esc(c.flow.lead)}</p>
        </div>
        <div class="track">
          <div class="track__row">
            ${c.flow.cards.map((card, i) =>
              `<div class="track__cell" data-reveal style="--delay:${i * 110}ms">
              <i>${String(i + 1).padStart(2, '0')}</i>
              <h3>${esc(card.title)}</h3>
              <p>${esc(card.text)}</p>
            </div>`
            ).join('\n            ')}
          </div>
        </div>
        ${plate('scene-click', 1600, 900, f.click, f.clickTag, ' data-reveal data-parallax="0.07"')}
      </div>
    </section>

    <!-- ================================================== 03 o card -->
    <section class="bay bay--paper2" id="card">
      <div class="wrap">
        ${marker('03', c.card.eyebrow, 'LOADCLI.md')}
        <div class="split">
          <h2 class="display">${c.card.title}</h2>
          <p class="lede" data-reveal>${esc(c.card.lead)}</p>
        </div>

        <div class="doc">
          <div class="file" data-reveal data-parallax="0.04">
            <div class="file__name">${esc(c.card.fileLabel)}</div>
            <pre><code><span class="c">---</span>
<span class="k">loadcli</span>: 1
<span class="k">nome</span>: <span class="s">Acme Site</span>
<span class="k">grupo</span>: ${esc(c.card.groupValue)}
<span class="k">icone</span>: cart.fill
<span class="k">cor</span>: "#6C4DF6"
<span class="k">repositorio</span>: github.com/acme/site
<span class="k">url</span>: app.acme.com
<span class="k">cli</span>: claude
<span class="k">modelo</span>: opus
<span class="k">esforco</span>: xhigh
<span class="c">---</span>

<span class="d">${esc(c.card.bodyText)}</span></code></pre>
          </div>
          <div class="card" data-reveal data-parallax="0.1" style="--delay:120ms">
            <div class="card__top">
              <span class="card__tile">${ico.globe}</span>
              <span class="card__tag">claude · opus</span>
            </div>
            <h4>Acme Site</h4>
            <p class="card__row">${ico.folder} acme</p>
            <p class="card__desc">${esc(c.card.bodyText)}</p>
            <p class="card__row">${ico.code} acme/site</p>
            <div class="card__acts">
              <span class="card__go">${ico.play}${esc(c.card.start)}</span>
              <span class="sp"></span>
              <span class="card__ico">${ico.folder}</span>
              <span class="card__ico">${ico.globe}</span>
              <span class="card__ico">${ico.code}</span>
              <span class="card__ico">${ico.pencil}</span>
            </div>
          </div>
        </div>

        <ul class="claims">
          ${c.card.points.map((p, i) =>
            `<li data-reveal style="--delay:${i * 80}ms"><b>${esc(p.title)}</b><p>${esc(p.text)}</p></li>`
          ).join('\n          ')}
        </ul>

        ${plate('scene-sync', 1600, 900, f.sync, f.syncTag, ' data-reveal data-parallax="0.06"')}
      </div>
    </section>

    <!-- ================================================== 04 IA -->
    <section class="bay bay--dark" id="ai">
      <div class="wrap">
        ${marker('04', c.ai.eyebrow, '3')}
        <div class="split">
          <h2 class="display">${c.ai.title}</h2>
          <p class="lede" data-reveal>${esc(c.ai.lead)}</p>
        </div>
        <ul class="cli">
          ${c.ai.cards.map((card, i) =>
            `<li data-reveal style="--delay:${i * 100}ms">
            <h3>${esc(card.title)}</h3>
            <p>${esc(card.text)}</p>
            <div class="chips">${card.chips.map((ch, j) =>
              `<span class="chip${j === 0 ? ' chip--sig' : ''}">${esc(ch)}</span>`).join('')}</div>
          </li>`
          ).join('\n          ')}
        </ul>
        <p class="lede" data-reveal style="margin-top:40px">${esc(c.ai.swatchLead)}</p>
        <div class="swatches" data-reveal>
          ${SWATCHES.map((h) => `<span class="swatch" style="background:${h}"></span>`).join('')}
        </div>
      </div>
    </section>

    <!-- ================================================== 05 mesas -->
    <section class="bay" id="spaces">
      <div class="wrap">
        ${marker('05', c.spaces.eyebrow, 'SIP ✓')}
        <div class="split">
          <h2 class="display">${c.spaces.title}</h2>
          <div>
            <p class="lede" data-reveal>${esc(c.spaces.p1)}</p>
            <p class="lede" data-reveal style="--delay:80ms;margin-top:16px">${esc(c.spaces.p2)}</p>
          </div>
        </div>
        <blockquote class="quote" data-reveal>${c.spaces.pull}</blockquote>
        <p style="margin-top:26px" data-reveal>
          <a class="btn btn--ghost" href="${REPO}/blob/main/docs/ARCHITECTURE.md" rel="noopener">${esc(c.spaces.link)}${ico.arrow}</a>
        </p>
        ${plate('scene-desktops', 1600, 900, f.desktops, f.desktopsTag, ' data-reveal data-parallax="0.06"')}
      </div>
    </section>

    <!-- ================================================== 06 detalhes -->
    <section class="bay bay--paper2">
      <div class="wrap">
        ${marker('06', c.features.eyebrow, String(c.features.items.length))}
        <h2 class="display" style="max-width:16ch">${c.features.title}</h2>
        <ul class="specs">
          ${c.features.items.map((it, i) =>
            `<li data-reveal style="--delay:${(i % 4) * 60}ms"><i>${String(i + 1).padStart(2, '0')}</i><b>${esc(it.title)}</b><p>${esc(it.text)}</p></li>`
          ).join('\n          ')}
        </ul>
      </div>
    </section>

    <!-- ================================================== 07 baixar -->
    <section class="bay" id="download">
      <div class="wrap">
        ${marker('07', c.download.eyebrow, 'v1.0.0')}
        <h2 class="display" style="max-width:12ch">${c.download.title}</h2>
        <div class="get">
          <article data-reveal>
            <p class="get__os">${ico.apple}macOS</p>
            <h3>${esc(c.download.mac.name)}</h3>
            <p class="get__meta">${esc(c.download.mac.meta)}</p>
            <a class="btn" href="${DMG}" download>${ico.dl}${esc(c.download.mac.button)}</a>
            <p class="get__warn"><b>${esc(c.download.mac.noteTitle)}</b> ${esc(c.download.mac.noteText)}</p>
          </article>
          <article class="get--soon" data-reveal style="--delay:100ms">
            <p class="get__os">${ico.win}Windows · ${esc(c.download.soon)}</p>
            <h3>${esc(c.download.win.name)}</h3>
            <p class="get__meta">${esc(c.download.win.meta)}</p>
            <a class="btn btn--ghost" href="${REPO}/blob/main/windows/ROADMAP.md" rel="noopener">${esc(c.download.win.button)}${ico.arrow}</a>
          </article>
        </div>
        <p class="oss" data-reveal>
          <span><b>${esc(c.download.oss.title)}</b> ${esc(c.download.oss.text)}</span>
          <a class="btn btn--ghost" href="${REPO}" rel="noopener">${ico.github}${esc(c.download.oss.button)}</a>
        </p>
      </div>
    </section>
  </main>

  <footer class="foot">
    <div class="wrap foot__in">
      <p class="foot__credit">${c.footer.credit}</p>
      <div class="foot__right">
        <span>${esc(c.footer.license)}</span>
        <nav class="langbar" aria-label="${esc(c.nav.langAria)}">${langbar}</nav>
      </div>
    </div>
  </footer>

  <script src="/assets/js/vendor/lenis.min.js?v=${ASSET_VERSION}"></script>
  <script type="module" src="/assets/js/site.js?v=${ASSET_VERSION}"></script>
</body>
</html>
`;
}

/* ------------------------------------------------------------ saída */

for (const lang of LANGS) {
  const content = JSON.parse(readFileSync(join(root, 'content', `${lang.code}.json`), 'utf8'));
  writeFileSync(join(root, lang.file), render(content), 'utf8');
  console.log(`  ${lang.file.padEnd(12)} ${lang.hreflang}`);
}

writeFileSync(join(root, 'en.html'),
  `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>loadcli</title>
<link rel="canonical" href="${SITE}/"><meta name="robots" content="noindex">
<meta http-equiv="refresh" content="0; url=/"></head>
<body><p><a href="/">loadcli</a></p></body></html>
`, 'utf8');
console.log('  en.html      → /');

const urls = LANGS.map((l) => {
  const loc = `${SITE}/${l.file === 'index.html' ? '' : l.file}`;
  const alts = LANGS.map((a) =>
    `    <xhtml:link rel="alternate" hreflang="${a.hreflang}" href="${SITE}/${a.file === 'index.html' ? '' : a.file}"/>`
  ).join('\n');
  return `  <url>\n    <loc>${loc}</loc>\n${alts}\n    <xhtml:link rel="alternate" hreflang="x-default" href="${SITE}/"/>\n    <changefreq>monthly</changefreq>\n    <priority>${l.code === 'en' ? '1.0' : '0.8'}</priority>\n  </url>`;
}).join('\n');

writeFileSync(join(root, 'sitemap.xml'),
  `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"\n        xmlns:xhtml="http://www.w3.org/1999/xhtml">\n${urls}\n</urlset>\n`, 'utf8');
writeFileSync(join(root, 'robots.txt'), `User-agent: *\nAllow: /\n\nSitemap: ${SITE}/sitemap.xml\n`, 'utf8');
console.log('  sitemap.xml\n  robots.txt');
console.log(`\nassets em ?v=${ASSET_VERSION}`);
