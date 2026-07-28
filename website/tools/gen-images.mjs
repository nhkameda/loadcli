#!/usr/bin/env node
/* Gera as ilustrações de apoio do site com o Nano Banana Pro (Gemini 3 Pro
 * Image), no mesmo molde de ~/DEV/arteneural/scripts/gen-landing-v4.mjs.
 *
 * A chave NUNCA fica em disco: o .env ao lado carrega só a referência op://,
 * e o 1Password resolve na hora. Como o `op` trava quando chamado de forma não
 * interativa, rode isto num terminal de verdade, para o Touch ID poder aparecer:
 *
 *   cd website && op run --env-file=.env -- node tools/gen-images.mjs
 *   (ou, da raiz do repo, `make site-images`)
 *
 * Só gera o que está faltando. Para refazer uma peça, apague o arquivo dela em
 * assets/img/ e rode de novo — ou passe o nome:
 *
 *   op run --env-file=.env -- node tools/gen-images.mjs ritual og-pt
 */

import { writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const outDir = join(root, 'assets', 'img');

const KEY = process.env.GEMINI_KEY || process.env.GEMINI_API_KEY;
const PRO = 'gemini-3-pro-image-preview';
/* O Pro costuma congestionar e estourar o tempo; o flash é o plano B da casa
   (ver arteneural/docs/LANDING-PAGE-RECIPE.md). O flash não aceita imageConfig. */
const FLASH = 'gemini-3.1-flash-image';

/* Linguagem visual comum, tirada do ícone do app: squircle violeta com
   degradê para índigo, brilho branco no canto superior esquerdo, moldura de
   painel dividido em branco 16% e um >_ geométrico. */
const STYLE = [
  'Apple-style product illustration, extremely minimal and premium.',
  'Near-white background (#FBFBFD), abundant negative space, soft long shadows.',
  'Brand palette only: violet #8B5CF6 to deep indigo #563BD4 gradients,',
  'accent #7C5CFF, neutral slate #64748B. No other hues.',
  'Clean geometry, generous rounded corners, hairline strokes, subtle grain.',
  'No text, no words, no letters, no logos, no UI chrome, no people.',
  'Flat vector-like rendering with soft depth. Centered composition.',
].join(' ');

const MANIFEST = [
  {
    name: 'ritual',
    aspect: '16:9',
    size: '2K',
    prompt:
      'Eight small translucent rounded rectangles scattered in loose disorder, ' +
      'gradually converging and collapsing into a single bright violet rounded ' +
      'square at the centre right. A visual metaphor for many manual steps ' +
      'becoming one action.',
  },
  {
    name: 'spaces',
    aspect: '16:9',
    size: '2K',
    prompt:
      'Three floating rounded rectangular planes in gentle 3D perspective, ' +
      'stacked in depth like macOS desktops in Mission Control, the front one ' +
      'crisp and split down the middle by a thin luminous violet seam, the ones ' +
      'behind softly blurred.',
  },
  {
    name: 'card',
    aspect: '4:3',
    size: '2K',
    prompt:
      'A single sheet of paper with subtle horizontal grey lines, folding and ' +
      'morphing mid-air into a solid rounded card with a violet gradient tile in ' +
      'its corner. Left half paper, right half card, a smooth transformation.',
  },
  {
    name: 'footer',
    aspect: '21:9',
    size: '2K',
    prompt:
      'An extremely subtle abstract band: a soft violet-to-indigo mesh gradient ' +
      'fading into near-white, with a faint grid of hairlines. Barely-there ' +
      'texture meant to sit behind a page footer.',
  },
  ...['en', 'es', 'zh', 'pt'].map((lang) => ({
    name: `og-${lang}`,
    aspect: '16:9',
    size: '2K',
    prompt:
      'A violet-to-indigo rounded squircle app icon floating centre-left with a ' +
      'soft white glow in its upper-left, casting a long soft shadow onto a ' +
      'near-white surface. To its right, two abstract rounded panels side by ' +
      'side separated by a thin luminous seam. Social-share hero composition ' +
      'with wide empty margins.',
  })),
];

/* ------------------------------------------------------------------ */

async function generate(item, model) {
  const body = {
    contents: [{ parts: [{ text: `${STYLE}\n\n${item.prompt}` }] }],
    generationConfig: { responseModalities: ['TEXT', 'IMAGE'] },
  };
  if (model === PRO) {
    body.generationConfig.imageConfig = {
      aspectRatio: item.aspect,
      imageSize: item.size,
    };
  }

  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
    {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-goog-api-key': KEY },
      body: JSON.stringify(body),
    }
  );

  if (!response.ok) {
    throw new Error(`${model} → HTTP ${response.status}: ${(await response.text()).slice(0, 300)}`);
  }

  const json = await response.json();
  const parts = json?.candidates?.[0]?.content?.parts ?? [];
  const image = parts.find((p) => p.inlineData?.data);
  if (!image) throw new Error(`${model} não devolveu imagem`);
  return Buffer.from(image.inlineData.data, 'base64');
}

async function main() {
  if (!KEY) {
    console.error(
      'Falta a chave. Rode com o 1Password resolvendo o .env:\n' +
        '  op run --env-file=.env -- node tools/gen-images.mjs'
    );
    process.exit(1);
  }

  mkdirSync(outDir, { recursive: true });
  const only = process.argv.slice(2);
  const wanted = only.length ? MANIFEST.filter((i) => only.includes(i.name)) : MANIFEST;

  for (const item of wanted) {
    const out = join(outDir, `${item.name}.png`);
    if (!only.length && existsSync(out)) {
      console.log(`· ${item.name} já existe, pulando`);
      continue;
    }
    process.stdout.write(`→ ${item.name} (${item.aspect}, ${item.size}) `);
    try {
      let bytes;
      try {
        bytes = await generate(item, PRO);
      } catch (proError) {
        process.stdout.write(`[pro falhou: ${proError.message.slice(0, 60)}] `);
        bytes = await generate(item, FLASH);
      }
      writeFileSync(out, bytes);
      console.log(`ok · ${(bytes.length / 1024).toFixed(0)} KB`);
    } catch (error) {
      console.log(`FALHOU · ${error.message}`);
    }
  }

  console.log(
    '\nDepois: otimize para a web (sips -Z 1600 e conversão para WebP) e\n' +
      'lembre de subir o ASSET_VERSION em tools/build.mjs se trocar algo já publicado.'
  );
}

main();
