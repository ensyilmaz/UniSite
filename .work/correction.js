(() => {
    'use strict';
    const select = (selector, root = document) => root.querySelector(selector);
    const all = (selector, root = document) => [...root.querySelectorAll(selector)];
    const header = document.getElementById('siteHeader');
    const main = select('main');
    const services = JSON.parse(document.getElementById('utx-services-data').textContent);
    const articles = JSON.parse(document.getElementById('utx-articles-data').textContent);
    const pages = all('.utx-page', main);
    const homeSections = [...main.children].filter(element => !element.classList.contains('utx-page'));
    const triggers = all('[data-utx-dropdown]');
    let activeTrigger;
    let openedByHover = false;
    let leaveTimer;
    let currentView = 'home';
    let blogScroll = 0;

    function positionPanel() {
        if (!activeTrigger) return;
        const panel = document.getElementById(activeTrigger.dataset.utxDropdown);
        const anchor = activeTrigger.getBoundingClientRect();
        const mobile = matchMedia('(max-width: 991.98px)').matches;
        const viewportWidth = document.documentElement.clientWidth;
        const viewportHeight = window.visualViewport?.height || innerHeight;
        const width = Math.min(panel.id === 'utx-services-menu' ? 320 : 250, viewportWidth - 32);
        const left = Math.min(Math.max(16, anchor.left - 14), viewportWidth - width - 16);
        const top = Math.min(mobile ? anchor.bottom + 5 : header.getBoundingClientRect().bottom + 7, viewportHeight - 100);
        panel.style.left = `${left}px`;
        panel.style.top = `${top}px`;
        panel.style.width = `${width}px`;
        panel.style.maxHeight = `${Math.max(80, viewportHeight - top - 16)}px`;
    }
    function closePanel(focus = false) {
        clearTimeout(leaveTimer);
        if (!activeTrigger) return;
        const previous = activeTrigger;
        document.getElementById(previous.dataset.utxDropdown).hidden = true;
        previous.setAttribute('aria-expanded', 'false');
        activeTrigger = null;
        openedByHover = false;
        if (focus) previous.focus();
    }
    function openPanel(trigger, fromHover = false) {
        clearTimeout(leaveTimer);
        const searchButton = header.querySelector('[aria-controls="headerSearch"]');
        if (searchButton?.getAttribute('aria-expanded') === 'true') searchButton.click();
        if (activeTrigger !== trigger) closePanel();
        activeTrigger = trigger;
        openedByHover = fromHover;
        const panel = document.getElementById(trigger.dataset.utxDropdown);
        panel.hidden = false;
        trigger.setAttribute('aria-expanded', 'true');
        positionPanel();
        requestAnimationFrame(positionPanel);
        setTimeout(positionPanel, 220);
    }
    function modified(event) { return event.button !== 0 || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey; }
    triggers.forEach(trigger => {
        if (trigger.dataset.utxDropdown === 'utx-services-menu') trigger.setAttribute('href', '#/hizmetler');
        trigger.addEventListener('click', event => {
            if (modified(event)) return;
            event.preventDefault();
            event.stopPropagation();
            if (trigger.dataset.utxDropdown === 'utx-services-menu' && !event.target.closest('.utx-nav-chevron')) {
                navigate('#/hizmetler');
                return;
            }
            if (activeTrigger === trigger && !openedByHover) closePanel(); else openPanel(trigger);
        });
        trigger.addEventListener('keydown', event => {
            if (event.key === 'ArrowDown') {
                event.preventDefault();
                openPanel(trigger);
                select('a', document.getElementById(trigger.dataset.utxDropdown))?.focus();
            }
        });
        trigger.addEventListener('pointerenter', event => {
            if (event.pointerType === 'mouse' && matchMedia('(min-width: 992px)').matches) openPanel(trigger, true);
        });
        trigger.addEventListener('pointerleave', () => {
            leaveTimer = setTimeout(() => {
                const panel = document.getElementById(trigger.dataset.utxDropdown);
                if (!panel.matches(':hover') && !panel.contains(document.activeElement)) closePanel();
            }, 180);
        });
        const panel = document.getElementById(trigger.dataset.utxDropdown);
        panel.addEventListener('pointerenter', () => clearTimeout(leaveTimer));
        panel.addEventListener('pointerleave', () => {
            if (matchMedia('(min-width: 992px)').matches) leaveTimer = setTimeout(() => {
                if (!panel.contains(document.activeElement)) closePanel();
            }, 180);
        });
        panel.addEventListener('click', event => { if (event.target.closest('a')) closePanel(); });
    });
    window.addEventListener('resize', positionPanel);
    window.addEventListener('scroll', () => closePanel(), { passive: true });
    document.addEventListener('click', event => {
        if (!event.target.closest('[data-utx-dropdown],.utx-panel')) closePanel();
    });
    document.addEventListener('keydown', event => {
        if (event.key === 'Escape' && activeTrigger) { event.preventDefault(); closePanel(true); }
    });

    function closeExistingMobileMenu() {
        const button = select('.nav-toggle', header);
        if (button?.getAttribute('aria-expanded') === 'true') button.click();
    }
    function uniqueSvgIds(root, prefix) {
        const ids = all('[id]', root).map(element => [element.id, `${prefix}-${element.id}`]);
        ids.forEach(([previous, next]) => {
            all('*', root).forEach(element => {
                [...element.attributes].forEach(attribute => {
                    let value = attribute.value.replaceAll(`url(#${previous})`, `url(#${next})`);
                    if (value === `#${previous}`) value = `#${next}`;
                    if (value !== attribute.value) element.setAttribute(attribute.name, value);
                });
            });
            const element = all('[id]', root).find(item => item.id === previous);
            if (element) element.id = next;
        });
    }
    function populateArticle(slug) {
        const article = articles[slug];
        const card = all('#utx-blog-view .utx-blog-card').find(item => select('[data-blog-open]', item).dataset.blogOpen === slug);
        if (!article || !card) return false;
        document.getElementById('utx-article-title').textContent = article.title;
        document.getElementById('utx-article-deck').textContent = article.deck;
        document.getElementById('utx-article-category').textContent = article.category;
        const sourceTime = select('time', card);
        const date = document.getElementById('utx-article-date');
        date.dateTime = sourceTime.dateTime;
        date.textContent = sourceTime.textContent;
        const body = document.getElementById('utx-article-body');
        body.innerHTML = article.bodyHtml;
        const words = body.textContent.trim().split(/\s+/).length;
        document.getElementById('utx-article-reading').textContent = `${Math.max(1, Math.ceil(words / 200))} dk okuma`;
        const cover = select('.utx-blog-art', card).cloneNode(true);
        uniqueSvgIds(cover, `utx-cover-${slug}`);
        document.getElementById('utx-article-cover').replaceChildren(cover);
        const related = all('#utx-blog-view .utx-blog-card').filter(item => item !== card).slice(0, 2).map((item, index) => {
            const clone = item.cloneNode(true);
            uniqueSvgIds(clone, `utx-related-${index}`);
            return clone;
        });
        document.getElementById('utx-article-related').replaceChildren(...related);
        return true;
    }
    function showPage(name, serviceSlug, topicSlug, focus = true) {
        if (name === 'article' && !populateArticle(serviceSlug)) {
            history.replaceState(null, '', '#/blog');
            showPage('blog', null, null, focus);
            return;
        }
        const page = name === 'home' ? null : document.getElementById(`utx-${name}-view`);
        if (name !== 'home' && !page) return;
        const previousView = currentView;
        if (currentView === 'blog' && name === 'article') blogScroll = window.scrollY;
        currentView = name;
        if (name === 'detail') {
            const service = services.find(item => item.slug === serviceSlug);
            if (!service) return;
            document.getElementById('utx-detail-title').textContent = service.title;
            document.getElementById('utx-detail-description').textContent = service.description;
            document.getElementById('utx-detail-topics').replaceChildren(...service.topics.map(topic => {
                const section = document.createElement('section');
                section.className = 'utx-detail-topic';
                section.id = `utx-topic-${topic.slug}`;
                const heading = document.createElement('h2');
                heading.textContent = topic.title;
                const paragraph = document.createElement('p');
                paragraph.textContent = topic.text;
                section.append(heading, paragraph);
                return section;
            }));
        }
        homeSections.forEach(section => { section.hidden = name !== 'home'; });
        pages.forEach(element => { element.hidden = element !== page; });
        // İç sayfalarda sitenin kendi is-solid düzenini, ana sayfada özgün overlay düzenini kullan.
        document.body.classList.toggle('has-overlay-header', name === 'home');
        header.classList.toggle('is-overlay', name === 'home');
        header.classList.toggle('is-solid', name !== 'home');
        closePanel();
        closeExistingMobileMenu();
        all('a.is-current[aria-current]', select('#mainNav')).forEach(link => { link.classList.remove('is-current'); link.removeAttribute('aria-current'); });
        const activeLink = name === 'blog' || name === 'article' ? select('#mainNav [href$="/blog"]') : name === 'services' || name === 'detail' ? select('[data-utx-dropdown="utx-services-menu"]') : null;
        if (activeLink) { activeLink.classList.add('is-current'); activeLink.setAttribute('aria-current', 'page'); }
        const title = name === 'home' ? 'Ana Sayfa' : name === 'blog' ? 'Blog' : name === 'services' ? 'Hizmetlerimiz' : name === 'article' ? articles[serviceSlug].title : document.getElementById('utx-detail-title').textContent;
        document.title = `${title} - Unitürk Bilişim Teknolojileri`;
        requestAnimationFrame(() => {
            const topic = topicSlug ? document.getElementById(`utx-topic-${topicSlug}`) : null;
            if (topic) {
                topic.scrollIntoView({ block: 'start', behavior: 'instant' });
                if (focus) { topic.tabIndex = -1; topic.focus({ preventScroll: true }); }
            } else {
                window.scrollTo({ top: name === 'blog' && previousView === 'article' ? blogScroll : 0, behavior: 'instant' });
                if (focus && page) { const heading = select('h1', page); heading.tabIndex = -1; heading.focus({ preventScroll: true }); }
            }
        });
    }
    function readHash(focus = true) {
        const hash = location.hash;
        if (!hash || hash === '#/') showPage('home', null, null, focus);
        else if (hash === '#/blog') showPage('blog', null, null, focus);
        else if (hash.startsWith('#/blog/')) {
            let slug;
            try { slug = decodeURIComponent(hash.slice('#/blog/'.length)); } catch { slug = ''; }
            showPage('article', slug, null, focus);
        }
        else if (hash === '#/hizmetler') showPage('services', null, null, focus);
        else if (hash.startsWith('#/hizmetler/')) {
            const [slug, query] = hash.slice('#/hizmetler/'.length).split('?');
            showPage('detail', slug, new URLSearchParams(query || '').get('konu'), focus);
        }
    }
    function navigate(hash) {
        if (location.hash === hash) readHash(); else location.hash = hash;
    }
    all('a[href="/blog"],a[href="/hizmetler"],a.brand[href="/"],[data-utx-view],[data-utx-service]').forEach(link => {
        if (link.hasAttribute('data-utx-dropdown')) return;
        const href = link.getAttribute('href');
        let hash = '#/';
        if (link.dataset.utxService) hash = `#/hizmetler/${link.dataset.utxService}${link.dataset.utxTopic ? `?konu=${link.dataset.utxTopic}` : ''}`;
        else if (link.dataset.utxView) hash = link.dataset.utxView === 'home' ? '#/' : link.dataset.utxView === 'blog' ? '#/blog' : '#/hizmetler';
        else if (href === '/blog') hash = '#/blog';
        else if (href === '/hizmetler') hash = '#/hizmetler';
        link.setAttribute('href', hash);
        link.addEventListener('click', event => {
            if (modified(event)) return;
            event.preventDefault();
            navigate(hash);
        });
    });
    // file:// ile açılan kopyada mevcut sunucu bağlantıları doğru sitede çalışsın.
    // Sayfaların içeriğini veya mevcut JavaScript davranışlarını değiştirmez.
    if (location.protocol === 'file:') {
        all('a[href^="/"],form[action^="/"]').forEach(element => {
            const attribute = element.tagName === 'FORM' ? 'action' : 'href';
            const value = element.getAttribute(attribute);
            if (value.startsWith('/') && !value.startsWith('//')) element.setAttribute(attribute, `https://dev.munitek.com${value}`);
        });
    }
    window.addEventListener('hashchange', () => readHash());

    if (location.hash) readHash(false);
})();