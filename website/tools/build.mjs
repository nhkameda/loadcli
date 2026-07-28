#!/usr/bin/env node
/* Gera os quatro HTML estáticos a partir de content/<lang>.json.
 *
 * O que vai para o servidor continua sendo HTML puro (o padrão dos outros
 * sites da casa), mas o texto mora num único lugar por idioma — o que impede
 * que hreflang, âncoras e estrutura saiam de sincronia entre as páginas.
 *
 *   node tools/build.mjs
 *
 * Lembre de subir o ?v=N quando mexer no CSS ou no JS: o Cloudflare guarda os
 * assets por 7 dias e o token do servidor não tem permissão de purge.
 */

import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');

/** Suba isto sempre que editar assets/css/site.css ou assets/js/site.js. */
const ASSET_VERSION = 4;

const SITE = 'https://www.loadcli.com';
const REPO = 'https://github.com/nhkameda/loadcli';
const DMG = '/download/loadcli-1.0.0.dmg';

/** Ordem da barra de idiomas, e o arquivo de cada um. */
const LANGS = [
  { code: 'en', file: 'index.html', hreflang: 'en', label: 'EN' },
  { code: 'es', file: 'es.html', hreflang: 'es', label: 'ES' },
  { code: 'zh', file: 'zh.html', hreflang: 'zh-CN', label: '中文' },
  { code: 'pt', file: 'pt.html', hreflang: 'pt-BR', label: 'PT' },
];

const esc = (s) =>
  String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

/* ------------------------------------------------------------ ícones */

const icon = {
  github: '<svg viewBox="0 0 16 16" fill="currentColor" aria-hidden="true"><path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82a7.4 7.4 0 0 1 2-.27c.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8Z"/></svg>',
  apple: '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M16.36 12.72c-.02-2.3 1.88-3.4 1.96-3.46-1.07-1.56-2.73-1.78-3.32-1.8-1.41-.14-2.76.83-3.48.83-.72 0-1.83-.81-3-.79-1.55.02-2.97.9-3.77 2.28-1.61 2.79-.41 6.92 1.15 9.19.77 1.11 1.68 2.35 2.88 2.31 1.16-.05 1.6-.75 3-.75s1.79.75 3.01.72c1.24-.02 2.03-1.13 2.79-2.24.88-1.29 1.24-2.54 1.26-2.6-.03-.01-2.42-.93-2.44-3.69ZM14.1 5.9c.64-.77 1.07-1.85.95-2.92-.92.04-2.03.61-2.69 1.38-.59.68-1.11 1.77-.97 2.82 1.02.08 2.07-.52 2.71-1.28Z"/></svg>',
  windows: '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M3 5.7 10.2 4.7v6.9H3V5.7Zm0 12.6 7.2 1v-6.8H3v5.8Zm8 1.1L21 21V12.8h-10v6.6Zm0-14.7v6.9h10V3l-10 1.7Z"/></svg>',
  download: '<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M10 3v10m0 0 4-4m-4 4-4-4M3.5 15.5h13"/></svg>',
  arrow: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12h14m0 0-5.5-5.5M19 12l-5.5 5.5"/></svg>',
  terminal: '<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m4 6 3.5 3.5L4 13m6 .5h6"/></svg>',
  play: '<svg viewBox="0 0 12 12" fill="currentColor" aria-hidden="true"><path d="M3 1.8v8.4l7-4.2z"/></svg>',
  folder: '<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M2.5 5.5A1.5 1.5 0 0 1 4 4h3.2l1.4 1.7H16a1.5 1.5 0 0 1 1.5 1.5v7.3A1.5 1.5 0 0 1 16 16H4a1.5 1.5 0 0 1-1.5-1.5v-9Z"/></svg>',
  globe: '<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="10" cy="10" r="7.2"/><path d="M2.8 10h14.4M10 2.8c1.9 2 2.9 4.5 2.9 7.2s-1 5.2-2.9 7.2c-1.9-2-2.9-4.5-2.9-7.2s1-5.2 2.9-7.2Z"/></svg>',
  code: '<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m7 6-4 4 4 4m6-8 4 4-4 4"/></svg>',
  pencil: '<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M13.6 3.9a1.7 1.7 0 0 1 2.4 2.4L7.4 15 4 16l1-3.4 8.6-8.7Z"/></svg>',
  search: '<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><circle cx="9" cy="9" r="5.4"/><path d="m13.2 13.2 3.3 3.3"/></svg>',
  clock: '<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="10" cy="10" r="7.2"/><path d="M10 5.8V10l3 1.8"/></svg>',
  display: '<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="2.4" y="3.6" width="15.2" height="10" rx="1.6"/><path d="M7 16.6h6"/></svg>',
  type: '<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 5.2h12M10 5.2V15m-3 0h6"/></svg>',
  menubar: '<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="2.4" y="3.4" width="15.2" height="13.2" rx="2"/><path d="M2.4 7.4h15.2"/></svg>',
  stethoscope: '<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5.5 3v4.2a3.3 3.3 0 0 0 6.6 0V3"/><path d="M8.8 10.5v2.2a3.6 3.6 0 0 0 7.2 0v-1"/><circle cx="16" cy="10.6" r="1.5"/></svg>',
  swift: '<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3.5 4.2c3.8 4.6 7.6 7.7 12.6 9.4-1 1.6-2.6 2.6-4.9 2.6-3.6 0-6.7-2.6-7.9-6"/><path d="M12.4 3.6c1.6 3.1 3 5.6 4.1 7.4"/></svg>',
};

const featureIcons = [
  icon.search, icon.clock, icon.folder, icon.display,
  icon.type, icon.menubar, icon.stethoscope, icon.swift,
];

/* Cores do IconCatalog do app — a fileira "seus projetos, suas cores". */
const SWATCHES = [
  '#7C5CFF', '#3B82F6', '#06B6D4', '#10B981', '#F59E0B',
  '#EF4444', '#EC4899', '#8B5CF6', '#64748B', '#0EA5E9',
];

/* ------------------------------------------------------------ página */

function render(c) {
  const self = LANGS.find((l) => l.code === c.lang);
  const canonical = `${SITE}/${self.file === 'index.html' ? '' : self.file}`;

  const alternates = LANGS.map(
    (l) =>
      `  <link rel="alternate" hreflang="${l.hreflang}" href="${SITE}/${l.file === 'index.html' ? '' : l.file}">`
  ).join('\n');

  const langbar = LANGS.map(
    (l) =>
      `<a href="/${l.file === 'index.html' ? '' : l.file}" hreflang="${l.hreflang}"${
        l.code === c.lang ? ' aria-current="true"' : ''
      }>${l.label}</a>`
  ).join('');

  const navLinks = c.nav.links
    .map((l) => `<a href="${l.href}">${esc(l.label)}</a>`)
    .join('\n            ');

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
  <meta name="theme-color" content="#fbfbfd">
  <meta name="color-scheme" content="light">
  <link rel="icon" href="/assets/img/icon-128.png" sizes="128x128" type="image/png">
  <link rel="apple-touch-icon" href="/assets/img/icon-256.png">
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="loadcli">
  <meta property="og:locale" content="${c.meta.ogLocale}">
  <meta property="og:url" content="${canonical}">
  <meta property="og:title" content="${esc(c.meta.title)}">
  <meta property="og:description" content="${esc(c.meta.description)}">
  <meta property="og:image" content="${SITE}/assets/img/og-${c.lang}.png">
  <meta name="twitter:card" content="summary_large_image">
  <link rel="stylesheet" href="/assets/css/site.css?v=${ASSET_VERSION}">
  <noscript><style>[data-reveal]{opacity:1!important;transform:none!important}.pane--browser,.pane--terminal{opacity:1!important;transform:none!important}.desk__seam{opacity:1!important}</style></noscript>
</head>
<body data-lang="${c.lang}">
  <a class="skip-link" href="#one-click">${esc(c.nav.skip)}</a>

  <header class="nav">
    <div class="wrap nav__inner">
      <a class="brand" href="/${self.file === 'index.html' ? '' : self.file}">
        <img src="/assets/img/icon-128.png" alt="" width="24" height="24">
        <span>loadcli</span>
      </a>
      <nav class="nav__links" aria-label="${esc(c.nav.aria)}">
            ${navLinks}
      </nav>
      <div class="nav__right">
        <nav class="langbar" aria-label="${esc(c.nav.langAria)}">${langbar}</nav>
        <a class="icon-link" href="${REPO}" rel="noopener" aria-label="GitHub">${icon.github}</a>
        <a class="btn btn--primary btn--sm" href="#download">${esc(c.nav.download)}</a>
      </div>
    </div>
  </header>

  <main>
    <!-- ------------------------------------------------------- hero -->
    <section class="hero">
      <div class="hero__glow" aria-hidden="true"></div>
      <div class="wrap hero__inner">
        <h1 data-reveal>${c.hero.title}</h1>
        <p class="lead" data-reveal style="--delay:90ms">${esc(c.hero.lead)}</p>
        <div class="hero__cta" data-reveal style="--delay:170ms">
          <a class="btn btn--primary" href="#download">${icon.download}${esc(c.hero.ctaPrimary)}</a>
          <a class="btn btn--ghost" href="${REPO}" rel="noopener">${icon.github}${esc(c.hero.ctaSecondary)}</a>
        </div>
        <p class="hero__meta" data-reveal style="--delay:230ms">${c.hero.meta
          .map((m) => `<span>${esc(m)}</span>`)
          .join('<span aria-hidden="true">·</span>')}</p>

        <div class="stage" data-reveal style="--delay:300ms">
          <div class="stage__scene">
            <div class="desk desk--back-1" aria-hidden="true"></div>
            <div class="desk desk--back-2" aria-hidden="true"></div>
            <div class="desk desk--front">
              <div class="desk__bar">
                <span class="dot dot--r"></span><span class="dot dot--y"></span><span class="dot dot--g"></span>
                <span class="desk__label">${esc(c.stage.deskLabel)}</span>
              </div>
              <div class="desk__panes">
                <div class="pane pane--browser">
                  <div class="browser__chrome">
                    <span class="dot dot--r"></span><span class="dot dot--y"></span><span class="dot dot--g"></span>
                    <span class="browser__url">${esc(c.stage.browserUrl)}</span>
                  </div>
                  <div class="browser__body">
                    <div class="skeleton skeleton--title"></div>
                    <div class="skeleton skeleton--w80"></div>
                    <div class="skeleton skeleton--w60"></div>
                    <div class="browser__cards">
                      <div class="browser__card"></div><div class="browser__card"></div>
                      <div class="browser__card"></div><div class="browser__card"></div>
                    </div>
                  </div>
                </div>
                <div class="pane pane--terminal">
                  <div class="term">
                    <div><span class="dim">~/DEV/acme</span></div>
                    <div><span class="p">$</span> <span data-typed="${esc(c.stage.command)}"></span><span class="caret"></span></div>
                    ${c.stage.output
                      .map(
                        (line) =>
                          `<div data-term-line style="opacity:0;transition:opacity .4s ease"><span class="ok">${esc(
                            line.mark
                          )}</span> <span class="dim">${esc(line.text)}</span></div>`
                      )
                      .join('\n                    ')}
                  </div>
                </div>
              </div>
              <span class="desk__seam" aria-hidden="true"></span>
            </div>
          </div>
          <div class="stage__tag" aria-hidden="true">
            <span class="dotlive"></span>
            <span data-labels='${JSON.stringify(c.stage.labels)}'>${esc(c.stage.labels[0])}</span>
          </div>
        </div>
      </div>
    </section>

    <!-- ----------------------------------------------------- ritual -->
    <section class="section section--alt">
      <div class="wrap ritual">
        <div>
          <p class="eyebrow" data-reveal>${esc(c.ritual.eyebrow)}</p>
          <h2 data-reveal>${c.ritual.title}</h2>
          <p class="lead" data-reveal style="--delay:80ms;margin-top:20px">${esc(c.ritual.lead)}</p>
          <p class="ritual__punch grad-text" data-reveal style="--delay:140ms">${esc(c.ritual.punch)}</p>
        </div>
        <ul class="steps" data-reveal>
          ${c.ritual.steps.map((s) => `<li class="step">${esc(s)}</li>`).join('\n          ')}
          <li class="step step--kept">${esc(c.ritual.kept)}</li>
        </ul>
      </div>
    </section>

    <!-- ---------------------------------------------------- um clique -->
    <section class="section" id="one-click">
      <div class="wrap">
        <p class="eyebrow" data-reveal>${esc(c.flow.eyebrow)}</p>
        <h2 class="narrow" data-reveal>${c.flow.title}</h2>
        <p class="lead narrow" data-reveal style="--delay:80ms;margin-top:20px">${esc(c.flow.lead)}</p>
        <div class="flow">
          ${c.flow.cards
            .map(
              (card, i) => `<article class="flowcard" data-reveal style="--delay:${i * 80}ms" data-parallax="${
                (i % 2 ? 0.06 : 0.11).toFixed(2)
              }">
            <span class="flowcard__n">0${i + 1}</span>
            <h3>${esc(card.title)}</h3>
            <p>${esc(card.text)}</p>
          </article>`
            )
            .join('\n          ')}
        </div>
      </div>
    </section>

    <!-- ---------------------------------------------------- o card -->
    <section class="section section--alt" id="card">
      <div class="wrap">
        <p class="eyebrow" data-reveal>${esc(c.card.eyebrow)}</p>
        <h2 class="narrow" data-reveal>${c.card.title}</h2>
        <p class="lead narrow" data-reveal style="--delay:80ms;margin-top:20px">${esc(c.card.lead)}</p>

        <div class="morph">
          <div class="codeblock" data-reveal data-parallax="0.09">
            <div class="codeblock__head">${icon.folder}&nbsp;${esc(c.card.fileLabel)}</div>
            <pre><code><span class="c">---</span>
<span class="k">loadcli</span>: <span class="v">1</span>
<span class="k">nome</span>: <span class="v">Acme Site</span>
<span class="k">grupo</span>: <span class="v">${esc(c.card.groupValue)}</span>
<span class="k">icone</span>: <span class="v">cart.fill</span>
<span class="k">cor</span>: <span class="v">"#3B82F6"</span>
<span class="k">repositorio</span>: <span class="v">github.com/acme/site</span>
<span class="k">url</span>: <span class="v">app.acme.com</span>
<span class="k">cli</span>: <span class="v">claude</span>
<span class="k">modelo</span>: <span class="v">opus</span>
<span class="k">esforco</span>: <span class="v">xhigh</span>
<span class="c">---</span>

<span class="d">${esc(c.card.bodyText)}</span></code></pre>
          </div>

          <div class="morph__arrow" aria-hidden="true">${icon.arrow}</div>

          <div class="appcard" data-reveal style="--delay:120ms" data-parallax="0.14">
            <div class="appcard__top">
              <span class="appcard__icon">${icon.globe}</span>
              <span class="appcard__tag">claude</span>
            </div>
            <h4>Acme Site</h4>
            <p class="appcard__path">${icon.folder} acme</p>
            <p class="appcard__desc">${esc(c.card.bodyText)}</p>
            <p class="appcard__repo">${icon.code} acme/site</p>
            <div class="appcard__actions">
              <span class="appcard__play">${icon.play} ${esc(c.card.start)}</span>
              <span class="appcard__spacer"></span>
              <span class="appcard__ico">${icon.folder}</span>
              <span class="appcard__ico">${icon.globe}</span>
              <span class="appcard__ico">${icon.code}</span>
              <span class="appcard__ico">${icon.pencil}</span>
            </div>
          </div>
        </div>

        <ul class="sync">
          ${c.card.points
            .map(
              (p, i) =>
                `<li data-reveal style="--delay:${i * 70}ms"><b>${esc(p.title)}</b>${esc(p.text)}</li>`
            )
            .join('\n          ')}
        </ul>
      </div>
    </section>

    <!-- ------------------------------------------------------- IA -->
    <section class="section section--dark" id="ai">
      <div class="wrap">
        <p class="eyebrow" data-reveal>${esc(c.ai.eyebrow)}</p>
        <h2 class="narrow" data-reveal>${c.ai.title}</h2>
        <p class="lead narrow" data-reveal style="--delay:80ms;margin-top:20px">${esc(c.ai.lead)}</p>
        <div class="cli-grid">
          ${c.ai.cards
            .map(
              (card, i) => `<article class="clicard" data-reveal style="--delay:${i * 90}ms">
            <h3>${esc(card.title)}</h3>
            <p>${esc(card.text)}</p>
            <div class="chips">${card.chips.map((ch) => `<span class="chip">${esc(ch)}</span>`).join('')}</div>
          </article>`
            )
            .join('\n          ')}
        </div>
        <p class="lead" data-reveal style="margin-top:44px">${esc(c.ai.swatchLead)}</p>
        <div class="swatches" data-reveal>
          ${SWATCHES.map((hex) => `<span class="swatch" style="background:${hex}"></span>`).join('')}
        </div>
      </div>
    </section>

    <!-- ---------------------------------------------------- spaces -->
    <section class="section" id="spaces">
      <div class="wrap narrow">
        <p class="eyebrow" data-reveal>${esc(c.spaces.eyebrow)}</p>
        <h2 data-reveal>${c.spaces.title}</h2>
        <p class="lead" data-reveal style="--delay:80ms;margin-top:22px">${esc(c.spaces.p1)}</p>
        <p class="lead" data-reveal style="--delay:120ms;margin-top:16px">${esc(c.spaces.p2)}</p>
        <p class="ritual__punch grad-text" data-reveal style="--delay:170ms">${esc(c.spaces.pull)}</p>
        <p data-reveal style="--delay:210ms;margin-top:22px">
          <a class="btn btn--ghost btn--sm" href="${REPO}/blob/main/docs/ARCHITECTURE.md" rel="noopener">${esc(
    c.spaces.link
  )}${icon.arrow}</a>
        </p>
      </div>
    </section>

    <!-- -------------------------------------------------- recursos -->
    <section class="section section--alt">
      <div class="wrap">
        <p class="eyebrow" data-reveal>${esc(c.features.eyebrow)}</p>
        <h2 class="narrow" data-reveal>${c.features.title}</h2>
        <div class="features">
          ${c.features.items
            .map(
              (f, i) => `<article class="feature" data-reveal style="--delay:${(i % 4) * 60}ms">
            <span class="feature__ico">${featureIcons[i] || icon.terminal}</span>
            <h3>${esc(f.title)}</h3>
            <p>${esc(f.text)}</p>
          </article>`
            )
            .join('\n          ')}
        </div>
      </div>
    </section>

    <!-- -------------------------------------------------- download -->
    <section class="section" id="download">
      <div class="wrap">
        <p class="eyebrow" data-reveal>${esc(c.download.eyebrow)}</p>
        <h2 class="narrow" data-reveal>${c.download.title}</h2>
        <div class="dl">
          <article class="dlcard" data-reveal>
            <p class="dlcard__os">${icon.apple} macOS</p>
            <h3>${esc(c.download.mac.name)}</h3>
            <p class="dlcard__meta">${esc(c.download.mac.meta)}</p>
            <a class="btn btn--primary" href="${DMG}" download>${icon.download}${esc(
    c.download.mac.button
  )}</a>
            <p class="dlcard__note"><b>${esc(c.download.mac.noteTitle)}</b> ${esc(
    c.download.mac.noteText
  )}</p>
          </article>
          <article class="dlcard dlcard--soon" data-reveal style="--delay:100ms">
            <span class="badge-soon">${esc(c.download.soon)}</span>
            <p class="dlcard__os">${icon.windows} Windows</p>
            <h3>${esc(c.download.win.name)}</h3>
            <p class="dlcard__meta">${esc(c.download.win.meta)}</p>
            <a class="btn btn--ghost" href="${REPO}/blob/main/windows/ROADMAP.md" rel="noopener">${esc(
    c.download.win.button
  )}${icon.arrow}</a>
          </article>
        </div>
        <div class="oss" data-reveal style="--delay:140ms">
          <span><b>${esc(c.download.oss.title)}</b> ${esc(c.download.oss.text)}</span>
          <a class="btn btn--ghost btn--sm" href="${REPO}" rel="noopener">${icon.github}${esc(
    c.download.oss.button
  )}</a>
        </div>
      </div>
    </section>
  </main>

  <footer class="footer">
    <div class="wrap footer__grid">
      <p class="footer__credit">${c.footer.credit}</p>
      <div class="footer__right">
        <span class="tiny">${esc(c.footer.license)}</span>
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

/* en.html existe só para quem chega por um link antigo: manda para a raiz. */
writeFileSync(
  join(root, 'en.html'),
  `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>loadcli</title>
  <link rel="canonical" href="${SITE}/">
  <meta name="robots" content="noindex">
  <meta http-equiv="refresh" content="0; url=/">
</head>
<body><p><a href="/">loadcli</a></p></body>
</html>
`,
  'utf8'
);
console.log('  en.html      → /');

/* sitemap com as alternativas recíprocas */
const urls = LANGS.map((l) => {
  const loc = `${SITE}/${l.file === 'index.html' ? '' : l.file}`;
  const alts = LANGS.map(
    (a) =>
      `    <xhtml:link rel="alternate" hreflang="${a.hreflang}" href="${SITE}/${
        a.file === 'index.html' ? '' : a.file
      }"/>`
  ).join('\n');
  return `  <url>
    <loc>${loc}</loc>
${alts}
    <xhtml:link rel="alternate" hreflang="x-default" href="${SITE}/"/>
    <changefreq>monthly</changefreq>
    <priority>${l.code === 'en' ? '1.0' : '0.8'}</priority>
  </url>`;
}).join('\n');

writeFileSync(
  join(root, 'sitemap.xml'),
  `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"
        xmlns:xhtml="http://www.w3.org/1999/xhtml">
${urls}
</urlset>
`,
  'utf8'
);
console.log('  sitemap.xml');

writeFileSync(
  join(root, 'robots.txt'),
  `User-agent: *
Allow: /

Sitemap: ${SITE}/sitemap.xml
`,
  'utf8'
);
console.log('  robots.txt');
console.log(`\nassets em ?v=${ASSET_VERSION} — suba ASSET_VERSION ao mexer em css/js.`);
