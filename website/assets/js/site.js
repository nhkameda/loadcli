/* loadcli.com — comportamento da página.
 *
 * Módulo ES único, carregado com `type="module"`. Tudo é auto-hospedado: não há
 * uma única requisição para fora do domínio, o que mantém o site inteiro
 * funcional atrás do Great Firewall e compatível com a CSP `script-src 'self'`.
 *
 * Ordem das coisas:
 *   1. estado de rolagem da barra superior
 *   2. revelação por IntersectionObserver
 *   3. Lenis para a rolagem suave
 *   4. um único laço de rAF que escreve --py (parallax) e --p (palco do hero)
 *   5. o terminal que se digita sozinho
 *   6. o mesh gradient WebGL do Paper Shaders, importado de forma tolerante
 *
 * Nada aqui é obrigatório: se o WebGL falhar, se o Lenis não carregar ou se o
 * usuário pedir menos movimento, o layout continua inteiro e legível.
 */

const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));

/* ------------------------------------------------ 1. barra superior */

const nav = document.querySelector('.nav');
if (nav) {
  const onScroll = () => nav.classList.toggle('is-stuck', window.scrollY > 8);
  onScroll();
  window.addEventListener('scroll', onScroll, { passive: true });
}

/* ------------------------------------------------ 2. revelação */

const revealables = document.querySelectorAll('[data-reveal]');
const revealAll = () => revealables.forEach((el) => el.classList.add('is-in'));

if (revealables.length) {
  if (reduced || !('IntersectionObserver' in window)) {
    revealAll();
  } else {
    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          entry.target.classList.add('is-in');
          io.unobserve(entry.target);
        });
      },
      { rootMargin: '0px 0px -12% 0px', threshold: 0.08 }
    );
    revealables.forEach((el) => io.observe(el));

    // Rede de segurança: a revelação é enfeite, não pode ser o que decide se o
    // conteúdo existe. Se o observador não entregar (aba em segundo plano na
    // carga, navegador antigo, âncora direta para o meio da página), tudo
    // aparece assim mesmo alguns segundos depois.
    setTimeout(revealAll, 2600);
  }
}

/* ------------------------------------------------ 3. rolagem suave */

let lenis = null;
if (!reduced && typeof globalThis.Lenis === 'function') {
  lenis = new globalThis.Lenis({
    duration: 1.05,
    // desaceleração exponencial: rápido no começo, macio no fim
    easing: (t) => Math.min(1, 1.001 - Math.pow(2, -10 * t)),
    smoothWheel: true,
    touchMultiplier: 1.6,
  });
}

/* âncoras internas passam pelo Lenis para não brigar com ele */
document.querySelectorAll('a[href^="#"]').forEach((link) => {
  link.addEventListener('click', (event) => {
    const id = link.getAttribute('href');
    if (!id || id === '#') return;
    const target = document.querySelector(id);
    if (!target) return;
    event.preventDefault();
    if (lenis) lenis.scrollTo(target, { offset: -64 });
    else target.scrollIntoView({ behavior: reduced ? 'auto' : 'smooth' });
    history.replaceState(null, '', id);
  });
});

/* ------------------------------------------------ 4. laço único */

const parallaxItems = [...document.querySelectorAll('[data-parallax]')].map((el) => ({
  el,
  speed: parseFloat(el.dataset.parallax) || 0.1,
}));

const scene = document.querySelector('.stage__scene');
const stage = document.querySelector('.stage');
const steps = document.querySelector('.steps');
const stageTag = document.querySelector('.stage__tag span');
const tagLabels = stageTag ? JSON.parse(stageTag.dataset.labels || '[]') : [];

let stageProgress = 0;

function frame() {
  const vh = window.innerHeight;

  if (!reduced) {
    for (const item of parallaxItems) {
      const rect = item.el.getBoundingClientRect();
      const centre = rect.top + rect.height / 2;
      const delta = (centre - vh / 2) / vh;
      item.el.style.setProperty('--py', `${(-delta * item.speed * 100).toFixed(2)}px`);
    }
  }

  if (stage && scene) {
    const rect = stage.getBoundingClientRect();
    // 0 quando o palco entra pela base, 1 quando o topo chega a 38% da tela
    const p = clamp((vh * 0.94 - rect.top) / (vh * 0.62), 0, 1);
    if (Math.abs(p - stageProgress) > 0.001) {
      stageProgress = p;
      scene.style.setProperty('--p', p.toFixed(3));
      if (stageTag && tagLabels.length) {
        const index = p < 0.3 ? 0 : p < 0.72 ? 1 : 2;
        if (stageTag.textContent !== tagLabels[index]) stageTag.textContent = tagLabels[index];
      }
      if (p > 0.5) startTyping();
    }
  }

  if (steps) {
    const rect = steps.getBoundingClientRect();
    steps.classList.toggle('is-collapsed', rect.top < vh * 0.45);
  }

  requestAnimationFrame(frame);
}

if (lenis) {
  const raf = (time) => {
    lenis.raf(time);
    requestAnimationFrame(raf);
  };
  requestAnimationFrame(raf);
}
requestAnimationFrame(frame);

/* ------------------------------------------------ 5. terminal */

const typedEl = document.querySelector('[data-typed]');
let typingStarted = false;

function startTyping() {
  if (typingStarted || !typedEl) return;
  typingStarted = true;

  const text = typedEl.dataset.typed || '';
  if (reduced) {
    typedEl.textContent = text;
    revealTerminalOutput();
    return;
  }

  let i = 0;
  const tick = () => {
    typedEl.textContent = text.slice(0, ++i);
    if (i < text.length) setTimeout(tick, 34 + Math.random() * 42);
    else setTimeout(revealTerminalOutput, 420);
  };
  setTimeout(tick, 240);
}

function revealTerminalOutput() {
  const lines = document.querySelectorAll('[data-term-line]');
  lines.forEach((line, index) => {
    setTimeout(() => {
      line.style.opacity = '1';
    }, reduced ? 0 : index * 240);
  });
}

/* ------------------------------------------------ 6. mesh gradient */

async function mountShader() {
  const host = document.querySelector('.hero__glow');
  if (!host || reduced) return;

  // Sem WebGL não vale a pena nem importar: o gradiente CSS já está na tela.
  const probe = document.createElement('canvas');
  const gl = probe.getContext('webgl2');
  if (!gl) return;

  try {
    const [{ ShaderMount }, { meshGradientFragmentShader }, { getShaderColorFromString }] =
      await Promise.all([
        import('./vendor/paper-shaders/shader-mount.js'),
        import('./vendor/paper-shaders/shaders/mesh-gradient.js'),
        import('./vendor/paper-shaders/get-shader-color-from-string.js'),
      ]);

    // Paleta deliberadamente clara: o shader é atmosfera, não fundo. Só um
    // violeta saturado no meio de quatro quase-brancos — em GPU de verdade as
    // cores da marca puras cobrem o hero e derrubam a legibilidade do título.
    const colors = ['#ffffff', '#f4f0ff', '#ddd3ff', '#a78bfa', '#faf8ff'].map(
      getShaderColorFromString
    );

    new ShaderMount(
      host,
      meshGradientFragmentShader,
      {
        u_colors: colors,
        u_colorsCount: colors.length,
        u_distortion: 0.82,
        u_swirl: 0.58,
        u_grainMixer: 0.12,
        u_grainOverlay: 0.03,
        // sizing padrão (o vertex shader do Paper Shaders exige estes)
        u_fit: 0,
        u_scale: 1.15,
        u_rotation: 0,
        u_offsetX: 0,
        u_offsetY: 0,
        u_originX: 0.5,
        u_originY: 0.5,
        u_worldWidth: 0,
        u_worldHeight: 0,
        u_imageAspectRatio: 1,
      },
      { antialias: true, alpha: true },
      0.11 // velocidade: respiração lenta, não animação
    );

    host.classList.add('has-shader');
  } catch (error) {
    // Silencioso de propósito: o fundo CSS já cobre este caso.
    console.debug('shader indisponível', error);
  }
}

mountShader();

/* ------------------------------------------------ 7. troca de idioma */

/* Mantém a seção em que a pessoa está ao trocar de idioma — as âncoras são as
   mesmas nos quatro arquivos justamente para isso. */
document.querySelectorAll('.langbar a').forEach((link) => {
  link.addEventListener('click', () => {
    if (window.location.hash) link.href = link.getAttribute('href') + window.location.hash;
  });
});
