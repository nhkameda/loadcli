#!/usr/bin/env node
/* Gera as ilustrações do site com o Nano Banana Pro (Gemini 3 Pro Image).
 *
 * A chave NUNCA fica em disco: o .env ao lado carrega só a referência op://.
 *
 *   cd website && op run --env-file=.env -- node tools/gen-images.mjs
 *   # se o `op run` estourar a autorização:
 *   GEMINI_KEY="$(op read 'op://Personal/Hackton-Gemini-NanoBananaPro/credential')" \
 *     node tools/gen-images.mjs
 *
 * Só gera o que falta. Para refazer uma peça, passe o nome dela.
 * Depois: python3 tools/optimize-images.py
 *
 * DIREÇÃO DE ARTE — o que importa aqui é ilustrar SITUAÇÕES, não formas
 * abstratas. A primeira versão deste site pediu "retângulos convergindo" e o
 * resultado não dizia nada. Cada peça agora é uma cena com contexto: uma mesa,
 * mãos, monitores, o antes e o depois.
 */

import { writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const outDir = join(root, 'assets', 'img');

const KEY = process.env.GEMINI_KEY || process.env.GEMINI_API_KEY;
const PRO = 'gemini-3-pro-image-preview';
const FLASH = 'gemini-3.1-flash-image';

/* Ilustração editorial de revista técnica: traço fino, papel quente, tinta
   preta e UMA cor de destaque. Nada de degradê 3D — é justamente o visual
   "gerado por IA" que queremos evitar. */
const STYLE = [
  'Editorial spot illustration for a technical magazine, in the tradition of',
  'New Yorker and MIT Technology Review illustration.',
  'Strictly limited palette: warm bone paper background (#EFEBE3), deep warm',
  'black ink (#16130F), and exactly ONE accent colour, an electric violet',
  '(#6C4DF6), used sparingly for a single focal element.',
  'Confident fine line work, flat fills, no photorealism, no 3D rendering,',
  'no glossy gradients, no drop shadows, no glow effects.',
  'Subtle paper grain. Slightly imperfect hand-drawn line quality.',
  'Isometric or three-quarter view. No text, no words, no letters, no logos,',
  'no readable UI. Faces are never shown in detail.',
].join(' ');

const MANIFEST = [
  {
    name: 'scene-before',
    aspect: '4:3',
    size: '2K',
    prompt:
      'A developer seen from behind, sitting at a desk late at night, shoulders ' +
      'tense. On the single monitor in front of them, about a dozen small ' +
      'windows overlap each other in complete disorder, spilling over one ' +
      'another. Coffee cup, tangled cable, notebook. The chaos of windows is ' +
      'drawn in black ink; nothing is violet. A scene about mess.',
  },
  {
    name: 'scene-after',
    aspect: '4:3',
    size: '2K',
    prompt:
      'The exact same developer, same desk, same angle and same drawing style ' +
      'as a companion piece. Now the monitor shows just two clean panels side ' +
      'by side, separated by a single crisp vertical line: a terminal on the ' +
      'right, a browser on the left. The shoulders are relaxed. The vertical ' +
      'divider line is the only violet element in the whole image.',
  },
  {
    name: 'scene-click',
    aspect: '16:9',
    size: '2K',
    prompt:
      'Close crop of two hands resting on a low-profile mechanical keyboard, ' +
      'seen from a three-quarter angle above. One index finger is mid-tap, ' +
      'caught at the instant of a double click on a trackpad beside the ' +
      'keyboard. A desk lamp pools light from the upper left. A small violet ' +
      'ripple radiates from the point of contact, the only colour in the image.',
  },
  {
    name: 'scene-sync',
    aspect: '16:9',
    size: '2K',
    prompt:
      'Two laptops of different sizes standing open side by side on a shared ' +
      'wooden desk, drawn in three-quarter view. Both screens display the same ' +
      'neat grid of small rounded cards. Between and above them, a thin violet ' +
      'arc connects one screen to the other, suggesting the same folder living ' +
      'in two places. Everything else is black ink on bone paper.',
  },
  {
    name: 'scene-desktops',
    aspect: '16:9',
    size: '2K',
    prompt:
      'An over-the-shoulder view of a person facing a wide monitor that shows ' +
      'Mission Control: five rectangular desktop thumbnails arranged in a row ' +
      'along the top, slightly overlapping in perspective. A sixth thumbnail is ' +
      'being drawn into existence at the right end of the row, outlined in ' +
      'violet, the only colour. The person sits still, hands off the keyboard.',
  },
  ...['en', 'es', 'zh', 'pt'].map((lang) => ({
    name: `og-${lang}`,
    aspect: '16:9',
    size: '2K',
    prompt:
      'A wide editorial composition: a desk seen from directly above, with a ' +
      'laptop whose screen shows two clean panels split by a single vertical ' +
      'violet line. Around the laptop, a notebook, a pen and a coffee cup are ' +
      'arranged with generous empty space. Black ink on bone paper, one violet ' +
      'accent. Large empty margins on the left third for a title to sit.',
  })),
];

/* ------------------------------------------------------------------ */

async function generate(item, model) {
  const body = {
    contents: [{ parts: [{ text: `${STYLE}\n\n${item.prompt}` }] }],
    generationConfig: { responseModalities: ['TEXT', 'IMAGE'] },
  };
  if (model === PRO) {
    body.generationConfig.imageConfig = { aspectRatio: item.aspect, imageSize: item.size };
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
    throw new Error(`${model} → HTTP ${response.status}: ${(await response.text()).slice(0, 240)}`);
  }
  const json = await response.json();
  const image = (json?.candidates?.[0]?.content?.parts ?? []).find((p) => p.inlineData?.data);
  if (!image) throw new Error(`${model} não devolveu imagem`);
  return Buffer.from(image.inlineData.data, 'base64');
}

async function main() {
  if (!KEY) {
    console.error('Falta a chave. Veja o cabeçalho deste arquivo.');
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
    process.stdout.write(`→ ${item.name} (${item.aspect}) `);
    try {
      let bytes;
      try {
        bytes = await generate(item, PRO);
      } catch (proError) {
        process.stdout.write(`[pro falhou: ${proError.message.slice(0, 50)}] `);
        bytes = await generate(item, FLASH);
      }
      writeFileSync(out, bytes);
      console.log(`ok · ${(bytes.length / 1024).toFixed(0)} KB`);
    } catch (error) {
      console.log(`FALHOU · ${error.message}`);
    }
  }
  console.log('\nAgora rode: python3 tools/optimize-images.py');
}

main();
