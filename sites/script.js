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
