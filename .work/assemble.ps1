$ErrorActionPreference = 'Stop'
$rootPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$pagePath = Join-Path $rootPath 'deneme.html'
$backupPath = Join-Path $PSScriptRoot 'deneme.original.html'
if (-not (Test-Path -LiteralPath $backupPath)) { Copy-Item -LiteralPath $pagePath -Destination $backupPath }
$text = [IO.File]::ReadAllText($backupPath, [Text.Encoding]::UTF8)
$servicesJson = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'services.json'), [Text.Encoding]::UTF8)
$services = $servicesJson | ConvertFrom-Json
function Icon([string]$name, [string]$extraClass = '') { return '<svg class="ut-icon ' + $extraClass + '" viewBox="0 0 24 24" aria-hidden="true"><use href="#ut-i-' + $name + '"></use></svg>' }
function Replace-Between([string]$source, [string]$start, [string]$end, [string]$value) {
    $startIndex = $source.IndexOf($start, [StringComparison]::Ordinal)
    if ($startIndex -lt 0) { throw "Start marker missing: $start" }
    $endIndex = $source.IndexOf($end, $startIndex, [StringComparison]::Ordinal)
    if ($endIndex -lt 0) { throw "End marker missing: $end" }
    return $source.Substring(0,$startIndex) + $value + $source.Substring($endIndex)
}
function Service-Cards {
    return (@($services | ForEach-Object {
        $item = $_
        $topics = (@($item.topics | ForEach-Object { '<li><a href="/hizmetler/' + $item.slug + '?konu=' + $_.slug + '">' + (Icon 'chevron-right') + '<span>' + $_.title + '</span></a></li>' }) -join "`n")
        '<article class="ut-service-card"><h3><a class="ut-service-title" href="/hizmetler/' + $item.slug + '"><span class="ut-service-icon">' + (Icon $item.icon) + '</span><span>' + $item.title + '</span>' + (Icon 'chevron-right' 'ut-service-chevron') + '</a></h3><p>' + $item.description + '</p><ul class="ut-service-topics" aria-label="' + $item.title + ' alt başlıkları">' + $topics + '</ul></article>'
    }) -join "`n")
}
$cards = Service-Cards
$megaGroups = (@($services | ForEach-Object {
    $item = $_
    $topics = (@($item.topics | ForEach-Object { '<li><a href="/hizmetler/' + $item.slug + '?konu=' + $_.slug + '">' + $_.title + '</a></li>' }) -join "`n")
    '<section class="ut-mega-group"><h3><a href="/hizmetler/' + $item.slug + '">' + (Icon $item.icon) + '<span>' + $item.title + '</span></a></h3><ul>' + $topics + '</ul></section>'
}) -join "`n")
$chevron = Icon 'chevron-down'
$nav = @"
            <nav class="main-nav" id="mainNav" aria-label="Ana menü">
                <div class="ut-nav-item">
                    <a class="nav-link" href="/kurumsal/hakkimizda">Kurumsal</a>
                    <button class="ut-dropdown-toggle" type="button" data-dropdown aria-label="Kurumsal alt menüsünü aç" aria-controls="corporateMenu" aria-expanded="false">$chevron</button>
                    <div class="ut-dropdown-panel" id="corporateMenu" hidden><ul>
                        <li><a href="/kurumsal/hakkimizda">Hakkımızda</a></li>
                        <li><a href="/kurumsal/vizyonumuz">Vizyonumuz</a></li>
                        <li><a href="/kurumsal/misyonumuz">Misyonumuz</a></li>
                    </ul></div>
                </div>
                <div class="ut-nav-item ut-nav-mega">
                    <a class="nav-link" href="/hizmetler">Hizmetlerimiz</a>
                    <button class="ut-dropdown-toggle" type="button" data-dropdown aria-label="Hizmetler mega menüsünü aç" aria-controls="servicesMenu" aria-expanded="false">$chevron</button>
                    <div class="ut-dropdown-panel ut-mega-panel" id="servicesMenu" hidden>
                        <div class="ut-mega-header"><strong>İşinizi ileri taşıyan çözümler.</strong><a href="/hizmetler">Tüm hizmetleri keşfedin →</a></div>
                        <div class="ut-mega-grid">$megaGroups</div>
                        <div class="ut-mega-footer">$(Icon 'headset') İhtiyacınıza uygun çözümü birlikte belirleyelim. <a href="/iletisim">İletişime geçin →</a></div>
                    </div>
                </div>
                <a class="nav-link" href="/is-ortaklarimiz">İş Ortaklarımız</a>
                <div class="ut-nav-item">
                    <a class="nav-link" href="/referanslar/musteri-referanslari">Referanslar</a>
                    <button class="ut-dropdown-toggle" type="button" data-dropdown aria-label="Referanslar alt menüsünü aç" aria-controls="referencesMenu" aria-expanded="false">$chevron</button>
                    <div class="ut-dropdown-panel" id="referencesMenu" hidden><ul>
                        <li><a href="/referanslar/musteri-referanslari">Müşteri Referansları</a></li>
                        <li><a href="/referanslar/projelerimiz">Projelerimiz</a></li>
                    </ul></div>
                </div>
                <a class="nav-link" href="/blog">Blog</a>
                <a class="nav-link" href="/iletisim">İletişim</a>
            </nav>

"@
$text = Replace-Between $text '            <nav class="main-nav"' '            <div class="header-actions">' $nav
$text = $text.Replace('<main role="main">','<main role="main" id="mainContent" tabindex="-1"><div id="page-home" class="ut-view">')
$contact = '<a class="ut-hero-contact" id="heroContact" href="#iletisim">İletişime Geçin ' + (Icon 'arrow') + '</a>'
$text = $text.Replace("            </p>`r`n        </div>`r`n    </div>`r`n`r`n    <ul class=`"hero-features`">", "            </p>`r`n            $contact`r`n        </div>`r`n    </div>`r`n`r`n    <ul class=`"hero-features`">")
if (-not $text.Contains('id="heroContact"')) { throw 'Hero CTA insertion failed.' }
$pause = '<button type="button" class="round-btn" id="heroPause" aria-label="Slaytları duraklat" aria-pressed="false">' + (Icon 'pause') + '</button>'
$text = $text.Replace('<div class="hero-arrows">','<div class="hero-arrows">' + $pause)
$text = $text.Replace('id="heroSlider" aria-roledescription="carousel"','id="heroSlider" role="region" aria-label="Teknoloji çözümlerimiz" aria-roledescription="carousel"')
$heroImageNames = @('uctan-uca-cozumler.svg','guvenli-altyapi.svg','surdurulebilir-teknoloji.svg')
$heroIconNames = @('layers','shield','growth')
for ($i=0; $i -lt $heroImageNames.Count; $i++) {
    $text = $text.Replace('<img src="/img/' + $heroImageNames[$i] + '" alt="" width="28" height="28" />',(Icon $heroIconNames[$i]))
}
$stepNames = @('plan','design','implement','sustain')
$stepIcons = @('compass','layers','server','support')
for ($i=0; $i -lt $stepNames.Count; $i++) { $text = $text.Replace('<img src="/img/step-' + $stepNames[$i] + '.png" alt="" />',(Icon $stepIcons[$i])) }
$solutions = @"
<!-- ÇÖZÜMLER -->
<section class="solutions" id="cozumler">
    <div class="wrap">
        <div class="section-head">
            <div><span class="eyebrow">Hizmetlerimiz</span><h2 class="section-title">Güvenli altyapılar,<br />daha güçlü kurumlar.</h2></div>
            <p class="section-desc">Altyapıdan güvenliğe, danışmanlıktan 7/24 desteğe uçtan uca BT çözümleri. İhtiyacınız olan hizmete ve alt başlıklarına doğrudan ulaşın.</p>
            <a class="link-arrow" href="/hizmetler">Tüm Hizmetlerimiz $(Icon 'arrow')</a>
        </div>
        <div class="ut-service-grid">$cards</div>
    </div>
</section>

"@
$text = Replace-Between $text '<!-- ÇÖZÜMLER -->' '<!-- HAKKIMIZDA + PROJELER -->' $solutions
$why = @"
        <div class="showcase-about-text" id="neden-uniturk">
            <span class="eyebrow eyebrow-light">Teknoloji ile sınırları birlikte aşıyoruz</span>
            <h2>Neden Uniturk?</h2>
            <p>Güvenilir iş ortağınız olarak daha verimli, daha sürdürülebilir bir gelecek için çalışıyoruz. İhtiyaçlarınızı dinliyor, teknolojiyi işinize değer katan çözümlere dönüştürüyoruz.</p>
            <ul class="ut-about-list">
                <li>$(Icon 'compass')<span><strong>İşinize özel yaklaşım</strong><br />İhtiyaçlarınıza uygun, ölçeklenebilir mimariler.</span></li>
                <li>$(Icon 'layers')<span><strong>Uçtan uca uzmanlık</strong><br />Analizden uygulamaya tek noktadan çözüm.</span></li>
                <li>$(Icon 'headset')<span><strong>Sürekli yanınızdayız</strong><br />Destek ve yönetimle sürdürülebilir iş sürekliliği.</span></li>
            </ul>
            <a class="ut-about-link" href="/kurumsal/hakkimizda">Bizi daha yakından tanıyın $(Icon 'arrow')</a>
        </div>
    </div>

"@
$text = Replace-Between $text '        <div class="showcase-about-text">' '    <div class="showcase-projects"' $why
$banner = '<div class="ut-page-banner" aria-hidden="true"><div class="ut-banner-art">' + (Icon 'network') + (Icon 'server') + (Icon 'shield') + '</div></div>'
$servicesPage = @"
<section class="ut-view ut-page" id="page-services" hidden aria-labelledby="services-title">
    $banner
    <div class="wrap ut-page-content">
        <nav class="ut-breadcrumb" aria-label="İçerik yolu"><a href="/">Ana Sayfa</a><span aria-hidden="true">/</span><span aria-current="page">Hizmetlerimiz</span></nav>
        <span class="ut-section-mark" aria-hidden="true"></span>
        <h1 id="services-title" tabindex="-1">Hizmetlerimiz</h1>
        <p class="ut-page-lead">Altyapıdan güvenliğe, danışmanlıktan 7/24 desteğe uçtan uca BT çözüm ve hizmetleri.</p>
        <div class="ut-service-grid">$cards</div>
    </div>
</section>
<section class="ut-view ut-page" id="page-detail" hidden aria-labelledby="detail-title">
    $banner
    <div class="wrap ut-page-content">
        <nav class="ut-breadcrumb" aria-label="İçerik yolu"><a href="/">Ana Sayfa</a><span aria-hidden="true">/</span><a href="/hizmetler">Hizmetlerimiz</a><span aria-hidden="true">/</span><span id="detail-breadcrumb-title" aria-current="page"></span></nav>
        <span class="ut-section-mark" aria-hidden="true"></span><span class="ut-service-icon" id="detail-icon" aria-hidden="true"></span>
        <h1 id="detail-title" tabindex="-1"></h1><p class="ut-page-lead" id="detail-description"></p>
        <div class="ut-detail-layout"><div id="detail-topics"></div><aside class="ut-detail-aside"><h2>Birlikte planlayalım.</h2><p>İhtiyaçlarınıza uygun çözümü belirlemek için uzman ekibimizle iletişime geçin.</p><a href="/iletisim">İletişime Geçin $(Icon 'arrow')</a><a href="mailto:info@uniturk.com.tr">info@uniturk.com.tr</a><a href="tel:+902162125383">+90 216 212 53 83</a></aside></div>
    </div>
</section>
<section class="ut-view ut-page" id="page-info" hidden aria-labelledby="info-title">
    $banner
    <div class="wrap ut-page-content">
        <nav class="ut-breadcrumb" aria-label="İçerik yolu"><a href="/">Ana Sayfa</a><span aria-hidden="true">/</span><span id="info-breadcrumb-title" aria-current="page"></span></nav>
        <span class="ut-section-mark" aria-hidden="true"></span><h1 id="info-title" tabindex="-1"></h1><div class="ut-info-copy" id="info-copy"></div>
        <a class="ut-hero-contact" href="/iletisim">İletişime Geçin $(Icon 'arrow')</a>
    </div>
</section>
"@
$blogPage = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'blog-fragment.html'), [Text.Encoding]::UTF8)
$blogPage = $blogPage.Replace('class="ut-page ut-blog-page"','class="ut-view ut-page ut-blog-page"').Replace('class="wrap"','class="wrap ut-page-content"').Replace('href="#ana-sayfa" data-view="home"','href="/"').Replace('<svg aria-hidden="true">','<svg class="ut-icon" viewBox="0 0 24 24" aria-hidden="true">').Replace('<span><svg','<span class="ut-blog-category"><svg').Replace('class="ut-content-note"','class="ut-page-note"').Replace('<p>BT altyapısı','<p class="ut-page-lead">BT altyapısı')
$text = $text.Replace('    </main>', "    </div>`n$servicesPage`n$blogPage`n    </main>")
# Kurumsal gruptan Neden Uniturk ve Belgelerimiz bağlantılarını çıkar; alt barda topla.
$text = [regex]::Replace($text,'(?m)^.*<li><a href="/kurumsal/neden-uniturk".*\r?\n','')
$text = [regex]::Replace($text,'(?m)^.*<li><a href="/kurumsal/belgelerimiz".*\r?\n','')
$text = [regex]::Replace($text,'(?m)^.*<li><a href="/bilgi-guvenligi-politikasi".*\r?\n','')
$text = [regex]::Replace($text,'(?m)^.*<li><a href="/kvkk-aydinlatma-metni".*\r?\n','')
$text = [regex]::Replace($text,'(?m)^.*<li><a href="/gizlilik-politikasi".*\r?\n','')
$footerGroups = @'
            <div class="footer-group">
                <h3 class="footer-group-title">Kurumsal Bakış</h3>
                <ul><li><a href="/kurumsal/hakkimizda">Hakkımızda</a></li><li><a href="/kurumsal/vizyonumuz">Vizyonumuz</a></li><li><a href="/kurumsal/misyonumuz">Misyonumuz</a></li></ul>
            </div>
            <div class="footer-group">
                <h3 class="footer-group-title">Çözüm Alanları</h3>
                <ul><li><a href="/hizmetler/ag-altyapilari-ve-sd-wan">Ağ Altyapıları ve SD-WAN</a></li><li><a href="/hizmetler/siber-guvenlik">Siber Güvenlik</a></li><li><a href="/hizmetler/veri-merkezi-ve-bulut">Veri Merkezi ve Bulut</a></li></ul>
            </div>
            <div class="footer-group">
                <h3 class="footer-group-title">Ürün &amp; Destek</h3>
                <ul><li><a href="/hizmetler/bt-urunleri-ve-diger-cozumler">BT Ürünleri ve Diğer Çözümler</a></li><li><a href="/hizmetler/teknik-destek">Teknik Destek</a></li><li><a href="/iletisim">İletişim</a></li></ul>
            </div>
        </div>
        <nav class="wrap ut-legal-bar" aria-label="Belgeler ve yasal metinler">
            <a href="/kurumsal/belgelerimiz">BELGE_ICON Belgelerimiz</a>
            <a href="/gizlilik-politikasi">Gizlilik Politikası</a>
            <a href="/kvkk-aydinlatma-metni">KVKK Aydınlatma Metni</a>
            <a href="/bilgi-guvenligi-politikasi">Bilgi Güvenliği Politikası</a>
        </nav>
'@
$footerGroups = $footerGroups.Replace('BELGE_ICON',(Icon 'document'))
$text = Replace-Between $text '            <div class="footer-group">' '    </footer>' $footerGroups
$text = $text.Replace('<img class="brand-logo" src="/img/logo.png" alt="Unitürk" width="331" height="48" />','<img class="brand-logo" src="/img/logo.png" alt="Unitürk" width="331" height="48" /><span class="ut-brand-fallback" hidden aria-hidden="true">uni<span>turk</span></span>')
$symbols = @'
<svg class="ut-symbols" xmlns="http://www.w3.org/2000/svg" aria-hidden="true"><defs>
<symbol id="ut-i-network" viewBox="0 0 24 24"><circle cx="12" cy="4" r="2.5"/><circle cx="5" cy="19" r="2.5"/><circle cx="19" cy="19" r="2.5"/><path d="M12 6.5v6m0-2-6 6m6-6 6 6"/></symbol>
<symbol id="ut-i-shield" viewBox="0 0 24 24"><path d="m12 2-8 3v6c0 5 3.5 9 8 11 4.5-2 8-6 8-11V5Z"/><path d="m8 12 3 3 5-6"/></symbol>
<symbol id="ut-i-server" viewBox="0 0 24 24"><rect x="3" y="3" width="18" height="7" rx="2"/><rect x="3" y="14" width="18" height="7" rx="2"/><path d="M7 6.5h.01M7 17.5h.01M15 6.5h3M15 17.5h3"/></symbol>
<symbol id="ut-i-cloud" viewBox="0 0 24 24"><path d="M7 19h11a4.5 4.5 0 0 0 .4-9A6.5 6.5 0 0 0 6 8a5.5 5.5 0 0 0 1 11Z"/></symbol>
<symbol id="ut-i-compass" viewBox="0 0 24 24"><circle cx="12" cy="12" r="10"/><path d="m16 8-3 5-5 3 3-5Z"/></symbol>
<symbol id="ut-i-monitor" viewBox="0 0 24 24"><rect x="2" y="3" width="20" height="14" rx="2"/><path d="M8 21h8m-4-4v4"/></symbol>
<symbol id="ut-i-layers" viewBox="0 0 24 24"><path d="m12 2 10 6-10 6L2 8Zm-10 11 10 6 10-6M2 18l10 6 10-6"/></symbol>
<symbol id="ut-i-headset" viewBox="0 0 24 24"><path d="M3 14v-3a9 9 0 0 1 18 0v7a4 4 0 0 1-4 4h-3"/><rect x="2" y="11" width="5" height="8" rx="2"/><rect x="17" y="11" width="5" height="8" rx="2"/></symbol>
<symbol id="ut-i-support" viewBox="0 0 24 24"><path d="M3 8a9 9 0 0 1 16-3l2 3M3 2v6h6m12 8a9 9 0 0 1-16 3l-2-3m18 6v-6h-6"/></symbol>
<symbol id="ut-i-growth" viewBox="0 0 24 24"><path d="M3 21h18M5 17v-5m5 5V9m5 8V6m5 11V3M3 8l5-4 5 1 8-4"/></symbol>
<symbol id="ut-i-globe" viewBox="0 0 24 24"><circle cx="12" cy="12" r="10"/><ellipse cx="12" cy="12" rx="4" ry="10"/><path d="M2 12h20M4 6h16M4 18h16"/></symbol>
<symbol id="ut-i-laptop" viewBox="0 0 24 24"><path d="M4 16V4h16v12M2 16h20v4H2Z"/></symbol>
<symbol id="ut-i-document" viewBox="0 0 24 24"><path d="M14 2H5v20h14V7Zm0 0v6h5M8 12h8m-8 4h6"/></symbol>
<symbol id="ut-i-arrow" viewBox="0 0 24 24"><path d="M4 12h16m-6-6 6 6-6 6"/></symbol>
<symbol id="ut-i-chevron-right" viewBox="0 0 24 24"><path d="m9 5 7 7-7 7"/></symbol>
<symbol id="ut-i-chevron-down" viewBox="0 0 24 24"><path d="m5 9 7 7 7-7"/></symbol>
<symbol id="ut-i-pause" viewBox="0 0 24 24"><path d="M8 5v14M16 5v14"/></symbol>
<symbol id="ut-i-play" viewBox="0 0 24 24"><path d="m8 4 12 8-12 8Z"/></symbol>
<symbol id="ut-i-close" viewBox="0 0 24 24"><path d="m6 6 12 12M6 18 18 6"/></symbol>
</defs></svg>
'@
$text = $text.Replace('<body class="has-overlay-header">','<body class="has-overlay-header"><a class="ut-skip-link" href="#mainContent">Ana içeriğe geç</a>' + $symbols)
$text = $text.Replace('</form>', '</form><div class="ut-search-results" id="ut-search-results" aria-live="polite" hidden></div>')
$text = $text.Replace('<link rel="stylesheet" href="/lib/bootstrap/dist/css/bootstrap.min.css" />','')
$legacyLink = '<link rel="stylesheet" href="/css/site.css?v=BZMF6I8mnm2caYx5YETUbaym5d8vuAVBtjcrC8UTOH4" />'
$legacyLoader = @'
<script>
// Orijinal CSS sunucuda varsa koru; tek dosya açılışında gömülü stilleri kullan.
document.documentElement.classList.add('ut-fallback');
if (location.protocol !== 'file:') {
    const bootstrapCss = document.createElement('link');
    bootstrapCss.rel = 'stylesheet';
    bootstrapCss.href = '/lib/bootstrap/dist/css/bootstrap.min.css';
    document.head.append(bootstrapCss);
    const originalCss = document.createElement('link');
    originalCss.rel = 'stylesheet';
    originalCss.href = '/css/site.css?v=BZMF6I8mnm2caYx5YETUbaym5d8vuAVBtjcrC8UTOH4';
    originalCss.addEventListener('load', () => document.documentElement.classList.remove('ut-fallback'));
    document.head.append(originalCss);
}
</script>
'@
$text = $text.Replace($legacyLink,$legacyLoader)
$fallbackCss = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'fallback.css'), [Text.Encoding]::UTF8)
$css = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'enhancements.css'), [Text.Encoding]::UTF8)
$text = $text.Replace('</head>', "<style id=`"uniturk-styles`">`n$fallbackCss`n$css`n</style>`n</head>")
$appScript = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'app.js'), [Text.Encoding]::UTF8)
$tail = @"
<dialog class="ut-dialog" id="blogDialog" aria-labelledby="blog-dialog-title">
    <button type="button" class="ut-dialog-close" id="blogDialogClose" aria-label="Yazıyı kapat">$(Icon 'close')</button>
    <span class="ut-dialog-label">Uniturk Blog · Örnek yazı</span>
    <div id="blogDialogContent"></div>
</dialog>
<script type="application/json" id="ut-service-data">$servicesJson</script>
<script>
$appScript
</script>
"@
$text = Replace-Between $text '    <script src="/lib/jquery' '</body>' $tail
[IO.File]::WriteAllText($pagePath, $text, [Text.UTF8Encoding]::new($false))
Write-Output ('Updated deneme.html: ' + ([IO.FileInfo]$pagePath).Length + ' bytes')
