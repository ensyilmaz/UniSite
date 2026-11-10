(function () {
    'use strict';

    const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    // Header: kaydırma durumu ve mobil menü
    const header = document.getElementById('siteHeader');
    if (header) {
        const toggle = document.getElementById('navToggle');
        const nav = document.getElementById('mainNav');

        const onScroll = () => header.classList.toggle('is-scrolled', window.scrollY > 10);
        onScroll();
        window.addEventListener('scroll', onScroll, { passive: true });

        const setOpen = (open) => {
            header.classList.toggle('nav-open', open);
            toggle?.setAttribute('aria-expanded', String(open));
            toggle?.setAttribute('aria-label', open ? 'Menüyü kapat' : 'Menüyü aç');
        };

        toggle?.addEventListener('click', () => setOpen(!header.classList.contains('nav-open')));
        nav?.addEventListener('click', (e) => {
            if (e.target.closest('a')) setOpen(false);
        });
    }

    // Header arama kutusu
    const searchToggle = document.getElementById('searchToggle');
    const searchForm = document.getElementById('headerSearch');
    if (searchToggle && searchForm) {
        const searchInput = searchForm.querySelector('input');

        const setSearchOpen = (open) => {
            searchForm.hidden = !open;
            searchToggle.setAttribute('aria-expanded', String(open));
            if (open) searchInput?.focus();
        };

        searchToggle.addEventListener('click', () => setSearchOpen(searchForm.hidden));

        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape' && !searchForm.hidden) {
                setSearchOpen(false);
                searchToggle.focus();
            }
        });

        document.addEventListener('click', (e) => {
            if (!searchForm.hidden && !searchForm.contains(e.target) && !searchToggle.contains(e.target)) {
                setSearchOpen(false);
            }
        });
    }

    // Hero slider
    const slider = document.getElementById('heroSlider');
    if (slider) {
        const slides = Array.from(slider.querySelectorAll('.hero-slide'));
        const captions = Array.from(slider.querySelectorAll('.hero-caption'));
        const current = document.getElementById('heroCurrent');
        const total = document.getElementById('heroTotal');
        const progress = document.getElementById('heroProgress');
        const prev = document.getElementById('heroPrev');
        const next = document.getElementById('heroNext');
        const pad = (n) => String(n).padStart(2, '0');
        let index = slides.findIndex((s) => s.classList.contains('is-active'));
        let timer = null;

        if (index < 0) index = 0;
        total.textContent = pad(slides.length);

        const show = (i) => {
            slides[index].classList.remove('is-active');
            captions[index]?.classList.remove('is-active');
            index = (i + slides.length) % slides.length;
            slides[index].classList.add('is-active');
            captions[index]?.classList.add('is-active');
            current.textContent = pad(index + 1);
            progress.style.width = ((index + 1) / slides.length) * 100 + '%';
            if (prev) prev.disabled = index === 0;
        };

        const restart = () => {
            if (reduceMotion) return;
            clearInterval(timer);
            timer = setInterval(() => show(index + 1), 6000);
        };

        prev?.addEventListener('click', () => { show(index - 1); restart(); });
        next?.addEventListener('click', () => { show(index + 1); restart(); });

        show(index);
        restart();
    }

    // Öne çıkan projeler karuseli
    const track = document.getElementById('projectsTrack');
    if (track && track.children.length) {
        const dots = document.getElementById('projectsDots');
        const next = document.getElementById('projectsNext');
        let pageCount = 0;

        const metrics = () => {
            const gap = parseFloat(getComputedStyle(track).columnGap) || 0;
            const cardWidth = track.children[0].getBoundingClientRect().width;
            const perPage = Math.max(1, Math.round((track.clientWidth + gap) / (cardWidth + gap)));
            return { perPage, step: perPage * (cardWidth + gap) };
        };

        const update = () => {
            const { step } = metrics();
            const atEnd = track.scrollLeft + track.clientWidth >= track.scrollWidth - 4;
            const active = atEnd ? pageCount - 1 : Math.round(track.scrollLeft / step);
            Array.from(dots.children).forEach((d, i) => d.classList.toggle('is-active', i === active));
        };

        const build = () => {
            const { perPage, step } = metrics();
            const count = Math.ceil(track.children.length / perPage);
            if (count !== pageCount) {
                pageCount = count;
                dots.innerHTML = '';
                for (let i = 0; i < count; i++) {
                    const dot = document.createElement('button');
                    dot.type = 'button';
                    dot.setAttribute('aria-label', (i + 1) + '. proje sayfası');
                    dot.addEventListener('click', () => track.scrollTo({ left: i * metrics().step, behavior: 'smooth' }));
                    dots.appendChild(dot);
                }
            }
            dots.hidden = count < 2;
            next.hidden = count < 2;
            if (step) update();
        };

        next.addEventListener('click', () => {
            const atEnd = track.scrollLeft + track.clientWidth >= track.scrollWidth - 4;
            track.scrollTo({ left: atEnd ? 0 : track.scrollLeft + metrics().step, behavior: 'smooth' });
        });

        track.addEventListener('scroll', update, { passive: true });
        window.addEventListener('resize', build);
        build();
    }
})();
