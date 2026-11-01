(() => {
  const navToggle = document.getElementById('nav-toggle');
  const nav = document.getElementById('main-nav');
  const header = document.querySelector('.site-header');
  const langSelect = document.getElementById('lang-select');

  /* language selector: same 41 locales as the editor */
  const i18n = window.SITE_I18N;
  const languages = i18n && Array.isArray(i18n.languages) ? i18n.languages : [];
  const byLowerCode = new Map(languages.map((language) => [language.code.toLowerCase(), language]));
  const STORAGE_KEY = 'godotRetroEngine.language';
  let currentTranslations = (i18n && i18n.strings && i18n.strings.en) || {};
  let updateCarouselLabels = null;
  const navLabel = (open) => currentTranslations[open ? 'nav.close' : 'nav.open']
    || (open ? 'Close navigation' : 'Open navigation');

  const resolveLanguage = (tag) => {
    if (!tag) return null;
    const clean = String(tag).replace(/_/g, '-').toLowerCase();
    if (byLowerCode.has(clean)) return byLowerCode.get(clean);

    const [base, region] = clean.split('-');
    if (base === 'pt') return byLowerCode.get(region === 'br' ? 'pt_br' : 'pt');
    if (base === 'es') return byLowerCode.get(region === 'ar' ? 'es_ar' : 'es');
    if (base === 'zh') {
      return byLowerCode.get(/tw|hk|mo|hant/.test(clean) ? 'zh_hant' : 'zh_hans');
    }
    return byLowerCode.get(base) || null;
  };

  const readStoredLanguage = () => {
    try { return localStorage.getItem(STORAGE_KEY); } catch { return null; }
  };

  const storeLanguage = (code) => {
    try { localStorage.setItem(STORAGE_KEY, code); } catch { /* private mode */ }
  };

  const applyLanguage = (code, persist) => {
    if (!i18n || !i18n.strings) return;
    const language = byLowerCode.get(String(code).toLowerCase()) || resolveLanguage(code) || byLowerCode.get('en');
    if (!language) return;

    const translations = i18n.strings[language.code] || i18n.strings.en || {};
    const fallback = i18n.strings.en || {};
    currentTranslations = translations;
    const renderHtml = (value) => value
      .replace(/\{\{SNES\}\}/g, '<code>_snes_export</code>')
      .replace(/\{\{MD\}\}/g, '<code>_md_export</code>');

    document.querySelectorAll('[data-i18n]').forEach((element) => {
      const key = element.getAttribute('data-i18n');
      const value = translations[key] ?? fallback[key];
      if (typeof value === 'string') element.textContent = value;
    });

    document.querySelectorAll('[data-i18n-html]').forEach((element) => {
      const key = element.getAttribute('data-i18n-html');
      const value = translations[key] ?? fallback[key];
      if (typeof value === 'string') element.innerHTML = renderHtml(value);
    });

    document.documentElement.lang = language.code.replace(/_/g, '-');
    document.documentElement.dir = language.dir || 'ltr';

    if (langSelect) {
      langSelect.value = language.code;
      langSelect.setAttribute('aria-label', translations['nav.language'] || 'Language');
    }
    if (navToggle) navToggle.setAttribute('aria-label', navLabel(nav && nav.classList.contains('is-open')));
    if (updateCarouselLabels) updateCarouselLabels();
    if (persist) storeLanguage(language.code);
  };

  if (languages.length && langSelect) {
    const fragment = document.createDocumentFragment();
    languages.forEach((language) => {
      const option = document.createElement('option');
      option.value = language.code;
      option.textContent = language.label;
      fragment.appendChild(option);
    });
    langSelect.replaceChildren(fragment);
    langSelect.addEventListener('change', () => {
      applyLanguage(langSelect.value, true);
      closeNav();
    });

    const stored = resolveLanguage(readStoredLanguage());
    const requested = resolveLanguage(new URLSearchParams(window.location.search).get('lang'));
    const preferred = (navigator.languages || [navigator.language || 'en'])
      .map(resolveLanguage)
      .find(Boolean);
    applyLanguage((requested || stored || preferred || byLowerCode.get('en')).code, false);
  }

  /* hero preview carousel */
  const carousel = document.querySelector('[data-carousel]');
  if (carousel) {
    const slides = [...carousel.querySelectorAll('.screen-slide')];
    const dots = [...carousel.querySelectorAll('[data-carousel-dot]')];
    const badge = carousel.querySelector('#hero-badge');
    const prevButton = carousel.querySelector('[data-carousel-prev]');
    const nextButton = carousel.querySelector('[data-carousel-next]');
    const dotsGroup = carousel.querySelector('[data-carousel-dots]');
    const motionQuery = window.matchMedia('(prefers-reduced-motion: reduce)');
    let index = Math.max(0, slides.findIndex((slide) => slide.classList.contains('is-active')));
    let timer = null;
    let paused = false;

    const update = (nextIndex) => {
      if (!slides.length) return;
      index = (nextIndex + slides.length) % slides.length;
      slides.forEach((slide, i) => {
        const active = i === index;
        slide.classList.toggle('is-active', active);
        slide.setAttribute('aria-hidden', String(!active));
      });
      dots.forEach((dot, i) => {
        const active = i === index;
        dot.classList.toggle('is-active', active);
        if (active) dot.setAttribute('aria-current', 'true');
        else dot.removeAttribute('aria-current');
      });
      if (badge) badge.textContent = slides[index].dataset.badge || '';
    };

    const stop = () => {
      if (timer !== null) {
        window.clearInterval(timer);
        timer = null;
      }
    };

    const start = () => {
      stop();
      if (paused || motionQuery.matches || document.hidden || slides.length < 2) return;
      timer = window.setInterval(() => update(index + 1), 4800);
    };

    const pause = () => {
      paused = true;
      stop();
    };

    const resume = () => {
      paused = false;
      start();
    };

    const refreshLabels = () => {
      if (prevButton) prevButton.setAttribute('aria-label', currentTranslations['carousel.prev'] || 'Previous preview');
      if (nextButton) nextButton.setAttribute('aria-label', currentTranslations['carousel.next'] || 'Next preview');
      if (dotsGroup) dotsGroup.setAttribute('aria-label', currentTranslations['carousel.slides'] || 'Preview slides');
      const label = currentTranslations['carousel.go'] || 'Show preview {{n}}';
      dots.forEach((dot, i) => dot.setAttribute('aria-label', label.replace('{{n}}', String(i + 1))));
    };

    updateCarouselLabels = refreshLabels;
    refreshLabels();
    update(index);

    if (prevButton) prevButton.addEventListener('click', () => { update(index - 1); start(); });
    if (nextButton) nextButton.addEventListener('click', () => { update(index + 1); start(); });
    dots.forEach((dot, i) => {
      dot.addEventListener('click', () => { update(i); start(); });
    });

    carousel.addEventListener('mouseenter', pause);
    carousel.addEventListener('mouseleave', resume);
    carousel.addEventListener('focusin', pause);
    carousel.addEventListener('focusout', (event) => {
      if (!carousel.contains(event.relatedTarget)) resume();
    });
    document.addEventListener('visibilitychange', () => {
      if (document.hidden) stop();
      else if (!paused) start();
    });
    motionQuery.addEventListener?.('change', () => {
      if (motionQuery.matches) stop();
      else start();
    });

    start();
  }

  const closeNav = () => {
    if (!nav || !navToggle) return;
    nav.classList.remove('is-open');
    navToggle.setAttribute('aria-expanded', 'false');
    navToggle.setAttribute('aria-label', navLabel(false));
    document.body.classList.remove('menu-open');
  };

  if (navToggle && nav) {
    navToggle.addEventListener('click', () => {
      const open = nav.classList.toggle('is-open');
      navToggle.setAttribute('aria-expanded', String(open));
      navToggle.setAttribute('aria-label', navLabel(open));
      document.body.classList.toggle('menu-open', open);
    });

    nav.querySelectorAll('a').forEach((link) => {
      link.addEventListener('click', closeNav);
    });

    document.addEventListener('keydown', (event) => {
      if (event.key === 'Escape') closeNav();
    });
  }

  const onScroll = () => {
    if (header) header.classList.toggle('is-scrolled', window.scrollY > 8);
  };
  window.addEventListener('scroll', onScroll, { passive: true });
  onScroll();

  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const reveals = document.querySelectorAll('.reveal');
  if (!reduceMotion && 'IntersectionObserver' in window) {
    const revealObserver = new IntersectionObserver((entries, observer) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        entry.target.classList.add('in');
        observer.unobserve(entry.target);
      });
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.08 });
    reveals.forEach((element) => revealObserver.observe(element));
  } else {
    reveals.forEach((element) => element.classList.add('in'));
  }

  const sections = [...document.querySelectorAll('main section[id]')];
  const navLinks = [...document.querySelectorAll('.main-nav a[href^="#"]')];
  if ('IntersectionObserver' in window && sections.length && navLinks.length) {
    const activeObserver = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        const id = `#${entry.target.id}`;
        navLinks.forEach((link) => {
          link.classList.toggle('is-active', link.getAttribute('href') === id);
        });
      });
    }, { rootMargin: '-42% 0px -52% 0px', threshold: 0 });
    sections.forEach((section) => activeObserver.observe(section));
  }

  const year = document.getElementById('year');
  if (year) year.textContent = String(new Date().getFullYear());

  document.querySelectorAll('a[target="_blank"]').forEach((link) => {
    if (!link.rel.includes('noopener')) link.rel += ' noopener';
  });
})();
