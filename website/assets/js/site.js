/* loadcli.com — comportamento da página.
 *
 * Tudo auto-hospedado: nenhuma requisição sai do domínio, o que mantém o site
 * inteiro funcional atrás do Great Firewall e compatível com a CSP
 * `script-src 'self'`.
 *
 * A regra de ouro aqui: a animação é enfeite, nunca requisito. Se o JS não
 * rodar, o <noscript> mostra tudo; se o observador não entregar, uma rede de
 * segurança mostra tudo mesmo assim.
 *
 * Nota de projeto: a primeira versão deste site amarrava a entrada do hero à
 * rolagem, então a primeira coisa que a pessoa via era uma caixa vazia. Agora
 * o hero é uma sequência ORQUESTRADA NA CARGA (CSS, `animation-delay`), e a
 * rolagem só faz parallax e revelação das seções seguintes.
 */

const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

/* ------------------------------------------------ barra superior */

const nav = document.querySelector('.nav');
if (nav) {
  const onScroll = () => nav.classList.toggle('is-stuck', window.scrollY > 8);
  onScroll();
  window.addEventListener('scroll', onScroll, { passive: true });
}

/* ------------------------------------------------ revelação */

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
      { rootMargin: '0px 0px -10% 0px', threshold: 0.06 }
    );
    revealables.forEach((el) => io.observe(el));
    setTimeout(revealAll, 2600);
  }
}

/* ------------------------------------------------ rolagem suave */

let lenis = null;
if (!reduced && typeof globalThis.Lenis === 'function') {
  lenis = new globalThis.Lenis({
    duration: 1.05,
    easing: (t) => Math.min(1, 1.001 - Math.pow(2, -10 * t)),
    smoothWheel: true,
    touchMultiplier: 1.6,
  });
  const raf = (time) => {
    lenis.raf(time);
    requestAnimationFrame(raf);
  };
  requestAnimationFrame(raf);
}

document.querySelectorAll('a[href^="#"]').forEach((link) => {
  link.addEventListener('click', (event) => {
    const id = link.getAttribute('href');
    if (!id || id === '#') return;
    const target = document.querySelector(id);
    if (!target) return;
    event.preventDefault();
    if (lenis) lenis.scrollTo(target, { offset: -60 });
    else target.scrollIntoView({ behavior: reduced ? 'auto' : 'smooth' });
    history.replaceState(null, '', id);
  });
});

/* ------------------------------------------------ parallax + passos */

const parallaxItems = [...document.querySelectorAll('[data-parallax]')].map((el) => ({
  el,
  speed: parseFloat(el.dataset.parallax) || 0.06,
}));
const steps = document.querySelector('.steps');

if (!reduced && (parallaxItems.length || steps)) {
  const frame = () => {
    const vh = window.innerHeight;
    for (const item of parallaxItems) {
      const rect = item.el.getBoundingClientRect();
      if (rect.bottom < -200 || rect.top > vh + 200) continue;
      const delta = (rect.top + rect.height / 2 - vh / 2) / vh;
      item.el.style.setProperty('--py', `${(-delta * item.speed * 100).toFixed(2)}px`);
    }
    if (steps) {
      steps.classList.toggle('is-done', steps.getBoundingClientRect().top < vh * 0.5);
    }
    requestAnimationFrame(frame);
  };
  requestAnimationFrame(frame);
} else if (steps) {
  steps.classList.add('is-done');
}

/* ------------------------------------------------ o terminal se digita */

/* Começa na carga, junto com a entrada do hero — não depende de rolagem. */
const typed = document.querySelector('[data-typed]');
if (typed) {
  const text = typed.dataset.typed || '';
  if (reduced) {
    typed.textContent = text;
  } else {
    let i = 0;
    const tick = () => {
      typed.textContent = text.slice(0, ++i);
      if (i < text.length) setTimeout(tick, 30 + Math.random() * 38);
    };
    setTimeout(tick, 900);
  }
}

/* ------------------------------------------------ troca de idioma */

/* Mantém a seção em que a pessoa está ao trocar de idioma — as âncoras são as
   mesmas nos quatro arquivos justamente para isso. */
document.querySelectorAll('.langbar a').forEach((link) => {
  link.addEventListener('click', () => {
    if (window.location.hash) link.href = link.getAttribute('href') + window.location.hash;
  });
});
