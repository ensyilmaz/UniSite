(() => {
    'use strict';
    const $ = (selector, scope = document) => scope.querySelector(selector);
    const $$ = (selector, scope = document) => [...scope.querySelectorAll(selector)];
    const services = JSON.parse($('#ut-service-data').textContent);
    const home = $('#page-home');
    const views = $$('.ut-view');
    const nav = $('#mainNav');
    const mobileToggle = $('#navToggle');
    const desktop = matchMedia('(min-width: 1101px)');
    const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
    const dropdowns = $$('[data-dropdown]');
    const searchForm = $('#headerSearch');
    const searchToggle = $('#searchToggle');
    const searchResults = $('#ut-search-results');
    let lastArticleButton = null;
    let hoverTimer;

    function icon(name) {
        const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
        svg.setAttribute('class', 'ut-icon');
        svg.setAttribute('viewBox', '0 0 24 24');
        svg.setAttribute('aria-hidden', 'true');
        const use = document.createElementNS(svg.namespaceURI, 'use');
        use.setAttribute('href', `#ut-i-${name}`);
        svg.append(use);
        return svg;
    }

    function closeDropdowns(except) {
        clearTimeout(hoverTimer);
        dropdowns.forEach(button => {
            if (button === except) return;
            button.setAttribute('aria-expanded', 'false');
            document.getElementById(button.getAttribute('aria-controls')).hidden = true;
        });
    }
    function setDropdown(button, open) {
        if (open) closeDropdowns(button);
        button.setAttribute('aria-expanded', String(open));
        document.getElementById(button.getAttribute('aria-controls')).hidden = !open;
        if (open) closeSearch();
    }
    function closeMobile() {
        nav.classList.remove('is-open');
        mobileToggle.setAttribute('aria-expanded', 'false');
        mobileToggle.setAttribute('aria-label', 'Menüyü aç');
        closeDropdowns();
    }
    dropdowns.forEach(button => {
        button.addEventListener('click', () => setDropdown(button, button.getAttribute('aria-expanded') !== 'true'));
        button.addEventListener('keydown', event => {
            if (event.key === 'ArrowDown') {
                event.preventDefault();
                setDropdown(button, true);
                $(`#${button.getAttribute('aria-controls')} a`)?.focus();
            }
        });
        const item = button.closest('.ut-nav-item');
        item.addEventListener('pointerenter', event => {
            if (!desktop.matches || event.pointerType !== 'mouse') return;
            clearTimeout(hoverTimer);
            hoverTimer = setTimeout(() => setDropdown(button, true), 130);
        });
        item.addEventListener('pointerleave', () => {
            if (!desktop.matches) return;
            clearTimeout(hoverTimer);
            hoverTimer = setTimeout(() => {
                if (!item.contains(document.activeElement)) setDropdown(button, false);
            }, 220);
        });
        item.addEventListener('focusout', () => setTimeout(() => {
            if (!item.contains(document.activeElement)) setDropdown(button, false);
        }, 0));
    });
    // Hizmetler başlığının kendisi de mega menüyü açar; tüm hizmetler bağlantısı paneldedir.
    $('#mainNav .ut-nav-mega > .nav-link').addEventListener('click', event => {
        if (event.button !== 0 || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
        event.preventDefault();
        const button = $('.ut-nav-mega [data-dropdown]');
        setDropdown(button, button.getAttribute('aria-expanded') !== 'true');
    });
    mobileToggle.addEventListener('click', () => {
        const open = mobileToggle.getAttribute('aria-expanded') !== 'true';
        nav.classList.toggle('is-open', open);
        mobileToggle.setAttribute('aria-expanded', String(open));
        mobileToggle.setAttribute('aria-label', open ? 'Menüyü kapat' : 'Menüyü aç');
        if (open) closeSearch(); else closeDropdowns();
    });
    desktop.addEventListener('change', closeMobile);

    function closeSearch() {
        searchForm.hidden = true;
        searchResults.hidden = true;
        searchToggle.setAttribute('aria-expanded', 'false');
    }
    searchToggle.addEventListener('click', () => {
        const open = searchForm.hidden;
        closeMobile();
        searchForm.hidden = !open;
        searchResults.hidden = true;
        searchToggle.setAttribute('aria-expanded', String(open));
        if (open) $('input', searchForm).focus();
    });

    const infoPages = {
        '/kurumsal/hakkimizda': {
            title: 'Hakkımızda',
            paragraphs: ['Kurumsal ölçekte güvenli, ölçeklenebilir ve yönetilebilir BT altyapıları tasarlıyor, iş süreçlerinizi geleceğe taşıyoruz.', 'Güvenilir iş ortağınız olarak daha verimli, daha sürdürülebilir bir gelecek için çalışıyoruz. Analiz, tasarım, uygulama ve destek süreçlerini bir bütün olarak ele alıyoruz.']
        },
        '/kurumsal/vizyonumuz': { title: 'Vizyonumuz', pending: true },
        '/kurumsal/misyonumuz': { title: 'Misyonumuz', pending: true },
        '/referanslar/musteri-referanslari': { title: 'Müşteri Referansları', pending: true },
        '/belgelerimiz': { title: 'Belgelerimiz', paragraphs: ['Belgeler ve sertifikalar bu alanda paylaşılacaktır. Güncel belgelerimiz hakkında bilgi almak için bizimle iletişime geçebilirsiniz.'] },
        '/bilgi-guvenligi-politikasi': { title: 'Bilgi Güvenliği Politikası', pending: true },
        '/kvkk-aydinlatma-metni': { title: 'KVKK Aydınlatma Metni', pending: true },
        '/gizlilik-politikasi': { title: 'Gizlilik Politikası', pending: true }
    };

    function populateDetail(service) {
        $('#detail-title').textContent = service.title;
        $('#detail-breadcrumb-title').textContent = service.title;
        $('#detail-description').textContent = service.description;
        $('#detail-topics').replaceChildren(...service.topics.map(topic => {
            const section = document.createElement('section');
            section.className = 'ut-topic';
            section.id = `topic-${topic.slug}`;
            const heading = document.createElement('h2');
            heading.textContent = topic.title;
            const paragraph = document.createElement('p');
            paragraph.textContent = topic.text;
            section.append(heading, paragraph);
            return section;
        }));
        $('#detail-icon').replaceChildren(icon(service.icon));
    }
    function populateInfo(info) {
        $('#info-title').textContent = info.title;
        $('#info-breadcrumb-title').textContent = info.title;
        const paragraphs = info.paragraphs || ['Bu sayfanın içeriği hazırlanıyor. Ayrıntılı bilgi için bizimle iletişime geçebilirsiniz.'];
        $('#info-copy').replaceChildren(...paragraphs.map(text => {
            const paragraph = document.createElement('p');
            paragraph.textContent = text;
            return paragraph;
        }));
    }
    function readRoute() {
        let hash;
        try { hash = decodeURIComponent(location.hash.slice(1)); } catch { hash = ''; }
        if (!hash || hash === '/' || hash === 'ana-sayfa') return { path: '/' };
        if (!hash.startsWith('/')) return { path: '/', anchor: hash };
        const parts = hash.split('?');
        return { path: parts[0].replace(/\/$/, '') || '/', topic: new URLSearchParams(parts[1] || '').get('konu') };
    }
    function renderRoute(focus = true) {
        const route = readRoute();
        let path = route.path;
        if (path === '/kurumsal/neden-uniturk') { path = '/'; route.anchor = 'neden-uniturk'; }
        if (path === '/kurumsal/belgelerimiz') path = '/belgelerimiz';
        if (path === '/iletisim') { path = '/'; route.anchor = 'iletisim'; }
        if (path === '/is-ortaklarimiz') { path = '/'; route.anchor = 'ortaklar'; }
        if (path === '/referanslar/projelerimiz') { path = '/'; route.anchor = 'projeler'; }
        let target = home;
        let title = 'Ana Sayfa';
        if (path === '/blog') { target = $('#page-blog'); title = 'Blog'; }
        else if (path === '/hizmetler') { target = $('#page-services'); title = 'Hizmetlerimiz'; }
        else if (path.startsWith('/hizmetler/')) {
            const service = services.find(item => item.slug === path.split('/')[2]);
            if (service) { populateDetail(service); target = $('#page-detail'); title = service.title; }
            else { populateInfo({ title: 'Hizmet bulunamadı', paragraphs: ['Aradığınız hizmete Hizmetlerimiz menüsünden ulaşabilirsiniz.'] }); target = $('#page-info'); title = 'Hizmet bulunamadı'; }
        } else if (infoPages[path]) { populateInfo(infoPages[path]); target = $('#page-info'); title = infoPages[path].title; }
        else if (path !== '/') { populateInfo({ title: 'Sayfa bulunamadı', paragraphs: ['Aradığınız içeriğe üst menüden veya site içi aramadan ulaşabilirsiniz.'] }); target = $('#page-info'); title = 'Sayfa bulunamadı'; }
        views.forEach(view => { view.hidden = view !== target; });
        document.body.classList.toggle('ut-inner-page', target !== home);
        document.body.classList.toggle('has-overlay-header', target === home);
        $('#siteHeader').classList.toggle('is-overlay', target === home);
        document.title = `${title} - Unitürk Bilişim Teknolojileri`;
        $$('#mainNav a[aria-current]').forEach(link => link.removeAttribute('aria-current'));
        const activePath = path.startsWith('/hizmetler') ? '/hizmetler' : path.startsWith('/kurumsal') ? '/kurumsal/hakkimizda' : path;
        const activeLink = $$('#mainNav a').find(link => link.getAttribute('href') === activePath);
        activeLink?.setAttribute('aria-current', 'page');
        closeMobile();
        closeSearch();
        if ($('#blogDialog').open) $('#blogDialog').close();
        requestAnimationFrame(() => {
            const anchor = route.topic ? document.getElementById(`topic-${route.topic}`) : route.anchor ? document.getElementById(route.anchor) : null;
            if (anchor && target.contains(anchor)) {
                anchor.scrollIntoView({ behavior: 'instant', block: 'start' });
                if (focus) { anchor.setAttribute('tabindex', '-1'); anchor.focus({ preventScroll: true }); }
            } else {
                window.scrollTo({ top: 0, behavior: 'instant' });
                if (focus) { const heading = $('h1', target); heading?.setAttribute('tabindex', '-1'); heading?.focus({ preventScroll: true }); }
            }
        });
    }

    document.addEventListener('click', event => {
        const articleButton = event.target.closest('[data-blog-open]');
        if (articleButton) {
            const template = document.getElementById(`blog-content-${articleButton.dataset.blogOpen}`);
            if (!template) return;
            lastArticleButton = articleButton;
            $('#blogDialogContent').replaceChildren(template.content.cloneNode(true));
            const heading = $('h2', $('#blogDialogContent'));
            heading.id = 'blog-dialog-title';
            $('#blogDialog').showModal();
            document.body.classList.add('ut-dialog-open');
            return;
        }
        const link = event.target.closest('a[href]');
        if (!link || event.defaultPrevented || event.button !== 0 || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey || link.target === '_blank' || link.hasAttribute('download')) return;
        const href = link.getAttribute('href');
        if (href === '#mainContent') {
            event.preventDefault();
            $('#mainContent').focus();
            $('#mainContent').scrollIntoView({ block: 'start' });
            return;
        }
        if (href.startsWith('/') && !href.startsWith('//')) {
            // Sunucudaki mevcut kurumsal ve yasal sayfalar kendi adreslerinde çalışır.
            // Tek HTML önizlemesinde bu adresler için yerel görünüm sağlanır.
            const path = href.split('?')[0];
            const locallyUpdated = path === '/' || path === '/hizmetler' || path.startsWith('/hizmetler/') || path === '/blog' || path === '/iletisim' || path === '/is-ortaklarimiz' || path === '/referanslar/projelerimiz';
            if (location.protocol !== 'file:' && !locallyUpdated) return;
            event.preventDefault();
            const next = `#${href}`;
            if (location.hash === next) renderRoute(); else location.hash = next;
        } else if (href.startsWith('#')) {
            if (href === location.hash) { event.preventDefault(); renderRoute(); }
            closeMobile();
        }
    });
    window.addEventListener('hashchange', () => renderRoute());
    document.addEventListener('click', event => {
        if (!event.target.closest('.ut-nav-item')) closeDropdowns();
        if (!event.target.closest('#siteHeader')) { closeMobile(); closeSearch(); }
    });
    document.addEventListener('keydown', event => {
        if (event.key !== 'Escape' || $('#blogDialog').open) return;
        const openButton = dropdowns.find(button => button.getAttribute('aria-expanded') === 'true');
        if (openButton) { closeDropdowns(); openButton.focus(); }
        else if (!searchForm.hidden) { closeSearch(); searchToggle.focus(); }
        else if (mobileToggle.getAttribute('aria-expanded') === 'true') { closeMobile(); mobileToggle.focus(); }
    });
    $('#blogDialogClose').addEventListener('click', () => $('#blogDialog').close());
    $('#blogDialog').addEventListener('click', event => {
        if (event.target !== $('#blogDialog')) return;
        const box = event.target.getBoundingClientRect();
        if (event.clientX < box.left || event.clientX > box.right || event.clientY < box.top || event.clientY > box.bottom) event.target.close();
    });
    $('#blogDialog').addEventListener('close', () => {
        document.body.classList.remove('ut-dialog-open');
        if (lastArticleButton && !$('#page-blog').hidden) lastArticleButton.focus();
    });

    const searchIndex = [
        ...services.flatMap(service => [{ title: service.title, route: `/hizmetler/${service.slug}` }, ...service.topics.map(topic => ({ title: topic.title, route: `/hizmetler/${service.slug}?konu=${topic.slug}` }))]),
        ...Object.entries(infoPages).map(([route, info]) => ({ title: info.title, route })),
        { title: 'İletişim', route: '/iletisim' }, { title: 'Blog', route: '/blog' }, { title: 'Neden Uniturk?', route: '/kurumsal/neden-uniturk' },
        ...$$('.ut-blog-card').map(card => ({ title: $('h2', card).textContent, route: '/blog', article: $('[data-blog-open]', card).dataset.blogOpen }))
    ];
    const normalize = text => text.toLocaleLowerCase('tr-TR').normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/ı/g, 'i');
    searchForm.addEventListener('submit', event => {
        event.preventDefault();
        const query = normalize($('input', searchForm).value.trim());
        const found = query ? searchIndex.filter(item => normalize(item.title).includes(query)).slice(0, 10) : [];
        searchResults.replaceChildren();
        const label = document.createElement('p');
        label.textContent = found.length ? `${found.length} sonuç bulundu` : 'Sonuç bulunamadı. Farklı bir kelimeyle tekrar arayın.';
        searchResults.append(label);
        found.forEach(item => {
            const link = document.createElement('a');
            link.href = `#${item.route}`;
            link.textContent = item.title;
            if (item.article) link.addEventListener('click', () => setTimeout(() => $(`[data-blog-open="${item.article}"]`)?.click(), 60));
            link.addEventListener('click', closeSearch);
            searchResults.append(link);
        });
        searchResults.hidden = false;
    });

    function recoverImage(img) {
        img.hidden = true;
        const fallback = img.parentElement.querySelector('.ut-brand-fallback');
        if (fallback) fallback.hidden = false;
    }
    $$('img').forEach(img => {
        img.addEventListener('error', () => recoverImage(img));
        if (img.complete && img.naturalWidth === 0) recoverImage(img);
    });

    const slides = $$('.hero-slide');
    const captions = $$('.hero-caption');
    const slider = $('#heroSlider');
    let slideIndex = 0;
    let slideTimer;
    let sliderPaused = false;
    function showSlide(index) {
        slideIndex = (index + slides.length) % slides.length;
        slides.forEach((slide, i) => { slide.classList.toggle('is-active', i === slideIndex); slide.setAttribute('aria-hidden', String(i !== slideIndex)); });
        captions.forEach((caption, i) => { caption.classList.toggle('is-active', i === slideIndex); caption.setAttribute('aria-hidden', String(i !== slideIndex)); });
        $('#heroCurrent').textContent = String(slideIndex + 1).padStart(2, '0');
        $('#heroProgress').style.width = `${(slideIndex + 1) / slides.length * 100}%`;
    }
    function startSlider() {
        clearInterval(slideTimer);
        if (!reducedMotion.matches && !sliderPaused && !document.hidden && !home.hidden) slideTimer = setInterval(() => showSlide(slideIndex + 1), 6500);
    }
    $('#heroPrev').addEventListener('click', () => { showSlide(slideIndex - 1); startSlider(); });
    $('#heroNext').addEventListener('click', () => { showSlide(slideIndex + 1); startSlider(); });
    $('#heroPause').addEventListener('click', event => {
        sliderPaused = !sliderPaused;
        event.currentTarget.setAttribute('aria-pressed', String(sliderPaused));
        event.currentTarget.setAttribute('aria-label', sliderPaused ? 'Slaytları oynat' : 'Slaytları duraklat');
        event.currentTarget.replaceChildren(icon(sliderPaused ? 'play' : 'pause'));
        startSlider();
    });
    slider.addEventListener('pointerenter', () => clearInterval(slideTimer));
    slider.addEventListener('pointerleave', startSlider);
    slider.addEventListener('focusin', () => clearInterval(slideTimer));
    slider.addEventListener('focusout', event => { if (!slider.contains(event.relatedTarget)) startSlider(); });
    document.addEventListener('visibilitychange', startSlider);
    window.addEventListener('hashchange', startSlider);
    reducedMotion.addEventListener('change', startSlider);
    showSlide(0);

    const track = $('#projectsTrack');
    const projectCards = $$('.project-card', track);
    const dots = $('#projectsDots');
    projectCards.forEach((card, index) => {
        const dot = document.createElement('button');
        dot.type = 'button';
        dot.setAttribute('aria-label', `${index + 1}. projeyi göster`);
        dot.addEventListener('click', () => track.scrollTo({ left: card.offsetLeft - projectCards[0].offsetLeft, behavior: reducedMotion.matches ? 'instant' : 'smooth' }));
        dots.append(dot);
    });
    function updateProjectDots() {
        const width = projectCards[1].offsetLeft - projectCards[0].offsetLeft;
        const index = width ? Math.min(projectCards.length - 1, Math.round(track.scrollLeft / width)) : 0;
        $$('button', dots).forEach((dot, i) => { dot.classList.toggle('is-active', i === index); dot.setAttribute('aria-pressed', String(i === index)); });
    }
    $('#projectsNext').append(icon('arrow'));
    $('#projectsNext').addEventListener('click', () => {
        const atEnd = track.scrollLeft + track.clientWidth >= track.scrollWidth - 5;
        track.scrollTo({ left: atEnd ? 0 : track.scrollLeft + track.clientWidth * .8, behavior: reducedMotion.matches ? 'instant' : 'smooth' });
    });
    track.addEventListener('scroll', updateProjectDots, { passive: true });
    updateProjectDots();
    renderRoute(false);
    startSlider();
})();
