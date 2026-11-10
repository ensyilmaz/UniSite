$ErrorActionPreference = 'Stop'
$rootPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sourcePath = 'C:/Users/EnesYılmaz/.codex/attachments/1f2795c8-dcd4-451f-b480-08e52a6b6c74/Pasted text.txt'
$source = [IO.File]::ReadAllText($sourcePath,[Text.Encoding]::UTF8)
$text = $source
$servicesJson = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'services.json'),[Text.Encoding]::UTF8)
$services = $servicesJson | ConvertFrom-Json
$oldOutput = Join-Path $PSScriptRoot 'rejected-design.html'
if (-not (Test-Path -LiteralPath $oldOutput)) { Copy-Item -LiteralPath (Join-Path $rootPath 'deneme.html') -Destination $oldOutput }
function Icon([string]$name) {
    $paths = @{
        network='<circle cx="12" cy="5" r="2.2"/><circle cx="5" cy="18" r="2.2"/><circle cx="19" cy="18" r="2.2"/><path d="M12 7.2v4.3m0 0-5.3 4.8m5.3-4.8 5.3 4.8"/>'
        shield='<path d="m12 3-7.5 3v5.5c0 4.6 3.2 8.4 7.5 9.5 4.3-1.1 7.5-4.9 7.5-9.5V6Z"/><path d="m8.8 12 2.2 2.2 4.3-4.4"/>'
        server='<rect x="3" y="4" width="18" height="7" rx="1.5"/><rect x="3" y="13" width="18" height="7" rx="1.5"/><path d="M7 7.5h.01M7 16.5h.01"/>'
        cloud='<path d="M7 18.5h10.5a4 4 0 0 0 .6-7.95A6 6 0 0 0 6.5 9.2 4.7 4.7 0 0 0 7 18.5Z"/>'
        compass='<circle cx="12" cy="12" r="9"/><path d="m15.5 8.5-2 5-5 2 2-5Z"/>'
        monitor='<rect x="3" y="4" width="18" height="12" rx="1.5"/><path d="M8 20h8M12 16v4"/>'
        layers='<path d="m12 3 9 5-9 5-9-5Zm-9 10 9 5 9-5"/>'
        headset='<path d="M4 14v-2a8 8 0 0 1 16 0v2"/><rect x="3" y="14" width="4" height="6" rx="1.5"/><rect x="17" y="14" width="4" height="6" rx="1.5"/><path d="M19 20a3 3 0 0 1-3 2h-3"/>'
        laptop='<path d="M4 16V4h16v12M2 16h20v4H2Z"/>'
        arrow='<path d="M5 12h14m-6-6 6 6-6 6"/>'
        support='<path d="M3 8a9 9 0 0 1 16-3l2 3M3 2v6h6m12 8a9 9 0 0 1-16 3l-2-3m18 6v-6h-6"/>'
        growth='<path d="M3 21h18M5 17v-5m5 5V9m5 8V6m5 11V3M3 8l5-4 5 1 8-4"/>'
        globe='<circle cx="12" cy="12" r="10"/><ellipse cx="12" cy="12" rx="4" ry="10"/><path d="M2 12h20M4 6h16M4 18h16"/>'
    }
    return '<svg class="utx-icon" viewBox="0 0 24 24" aria-hidden="true">' + $paths[$name] + '</svg>'
}
function Between([string]$html,[string]$start,[string]$end,[string]$replacement) {
    $first=$html.IndexOf($start,[StringComparison]::Ordinal)
    if($first -lt 0){throw "Missing marker: $start"}
    $last=$html.IndexOf($end,$first,[StringComparison]::Ordinal)
    if($last -lt 0){throw "Missing marker: $end"}
    return $html.Substring(0,$first)+$replacement+$html.Substring($last)
}
function Service-Url($service) { if($service.slug -eq 'bt-urunleri-ve-diger-cozumler'){return '/hizmetler/sektorler'}; return '/hizmetler/'+$service.slug }
function Cards {
    return (@($services | ForEach-Object {
        $service=$_; $url=Service-Url $service
        $topics=(@($service.topics | ForEach-Object { '<li><a href="'+$url+'#'+$_.slug+'" data-utx-service="'+$service.slug+'" data-utx-topic="'+$_.slug+'">'+$_.title+'</a></li>'}) -join "`n")
        '<article class="utx-service-card"><div class="utx-service-head"><span class="utx-service-icon">'+(Icon $service.icon)+'</span><h3 class="utx-service-title"><a href="'+$url+'" data-utx-service="'+$service.slug+'">'+$service.title+'</a></h3></div><p>'+$service.description+'</p><ul class="utx-service-topics" aria-label="'+$service.title+' alt başlıkları">'+$topics+'</ul></article>'
    }) -join "`n")
}
$cards = Cards
# Sadece istenen hizmet kartları alanını değiştir; bölümün mevcut başlığını koru.
$gridStart = $text.IndexOf('        <div class="solution-grid">',[StringComparison]::Ordinal)
$gridEnd = $text.IndexOf('<!-- HAKKIMIZDA + PROJELER -->',$gridStart,[StringComparison]::Ordinal)
$text = $text.Substring(0,$gridStart) + '<div class="utx-service-grid">' + $cards + "</div>`r`n    </div>`r`n</section>`r`n`r`n" + $text.Substring($gridEnd)
# Hero'nun mevcut 80px boşluğuna, yerleşimi büyütmeden mevcut buton stiliyle ekle.
$cta='<!-- UTX HERO CONTACT START --><div class="utx-hero-actions"><a class="btn-ut btn-ut-primary utx-hero-contact" href="/iletisim">İletişime Geçin '+(Icon 'arrow')+'</a></div><!-- UTX HERO CONTACT END -->'
$heroParagraph='(<p class="hero-lead">.*?</p>)'
$heroMatch=[regex]::Match($text,$heroParagraph,[Text.RegularExpressions.RegexOptions]::Singleline)
$text=$text.Insert($heroMatch.Index+$heroMatch.Length,$cta)
# Doğrudan navbar bağlantılarını koru; sarmalayıcı ve yeni header tasarımı oluşturma.
$chevron='<svg class="utx-nav-chevron" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path d="m6 9 6 6 6-6"/></svg>'
foreach($entry in @(@{Href='/kurumsal/hakkimizda';Label='Kurumsal';Id='utx-corporate-menu'},@{Href='/hizmetler';Label='Hizmetlerimiz';Id='utx-services-menu'},@{Href='/referanslar/musteri-referanslari';Label='Referanslar';Id='utx-references-menu'})) {
    $old='<a class="nav-link" href="'+$entry.Href+'">'+$entry.Label+'</a>'
    $new='<a class="nav-link utx-nav-trigger" href="'+$entry.Href+'" data-utx-dropdown="'+$entry.Id+'" aria-controls="'+$entry.Id+'" aria-expanded="false">'+$entry.Label+$chevron+'</a>'
    $text=$text.Replace($old,$new)
}
$serviceLinks=(@($services | ForEach-Object {
    $service=$_; $url=Service-Url $service
    '<a href="'+$url+'" data-utx-service="'+$service.slug+'">'+$service.title+'</a>'
}) -join "`n")
$panels=@"
<div class="utx-panel" id="utx-corporate-menu" aria-label="Kurumsal alt menüsü" hidden><a href="/kurumsal/hakkimizda">Hakkımızda</a><a href="/kurumsal/vizyonumuz">Vizyonumuz</a><a href="/kurumsal/misyonumuz">Misyonumuz</a></div>
<div class="utx-panel utx-services-list" id="utx-services-menu" aria-label="Hizmetler alt menüsü" hidden>$serviceLinks</div>
<div class="utx-panel" id="utx-references-menu" aria-label="Referanslar alt menüsü" hidden><a href="/referanslar/musteri-referanslari">Müşteri Referansları</a><a href="/referanslar/projelerimiz">Projelerimiz</a></div>
"@
$text=$text.Replace('    </header>',"    </header>`r`n$panels")
$why=@"
<!-- UTX NEDEN UNITURK START -->
<section class="utx-about" id="utx-neden-uniturk" aria-labelledby="utx-about-heading"><div class="wrap utx-about-inner"><div><span class="eyebrow">Hakkımızda</span><h2 class="utx-about-heading" id="utx-about-heading">Neden Uniturk?</h2><p class="utx-about-description">Güvenilir iş ortağınız olarak daha verimli, daha sürdürülebilir bir gelecek için çalışıyoruz. İhtiyaçlarınıza uygun, güvenli ve yönetilebilir BT altyapılarıyla teknolojiyi işiniz için anlamlı kılıyoruz.</p></div><ul class="utx-about-points"><li>$(Icon 'compass')<div><h3>İhtiyacınıza özel yaklaşım</h3><p>İş hedeflerinize uygun teknoloji planlaması.</p></div></li><li>$(Icon 'layers')<div><h3>Uçtan uca çözümler</h3><p>Analizden uygulamaya bir bütün olarak hizmet.</p></div></li><li>$(Icon 'shield')<div><h3>Güvenilir altyapılar</h3><p>Güvenlik ve iş sürekliliğini gözeten tasarım.</p></div></li><li>$(Icon 'headset')<div><h3>Sürekli destek</h3><p>Yönetim ve teknik destekle yanınızdayız.</p></div></li></ul></div></section>
<!-- UTX NEDEN UNITURK END -->
"@
$text=$text.Replace('<!-- HAKKIMIZDA + PROJELER -->',$why+"`r`n<!-- HAKKIMIZDA + PROJELER -->")
# Belgelerimiz bağlantısını değiştirmeden yasal bağlantıların yanına taşı.
$docs=[regex]::Match($text,'<li><a href="/kurumsal/belgelerimiz">.*?</li>').Value
$text=$text.Replace($docs,'')
$text=[regex]::Replace($text,'(?m)^.*<li><a href="/kurumsal/neden-uniturk".*\r?\n','')
$legalHeader='                <h3 class="footer-group-title">Yasal &amp; Gizlilik</h3>'
$legalIndex=$text.IndexOf($legalHeader,[StringComparison]::Ordinal)
$groupIndex=$text.LastIndexOf('<div class="footer-group">',$legalIndex,[StringComparison]::Ordinal)
$text=$text.Remove($groupIndex,'<div class="footer-group">'.Length).Insert($groupIndex,'<div class="footer-group utx-legal-bar">')
$legalIndex=$text.IndexOf($legalHeader,[StringComparison]::Ordinal)
$listIndex=$text.IndexOf('<ul>',$legalIndex,[StringComparison]::Ordinal)+4
$text=$text.Insert($listIndex,"`r`n                    "+$docs)
# İç sayfalarda gerçek sitenin mevcut banner ve page-body yapısını kullan.
$servicesSource=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'original-assets/hizmetler.html'),[Text.Encoding]::UTF8)
$blogSource=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'original-assets/blog.html'),[Text.Encoding]::UTF8)
$servicesBanner=[regex]::Match($servicesSource,'<section class="page-banner".*?</section>',[Text.RegularExpressions.RegexOptions]::Singleline).Value
$blogBanner=[regex]::Match($blogSource,'<section class="page-banner".*?</section>',[Text.RegularExpressions.RegexOptions]::Singleline).Value
$servicesBanner=$servicesBanner.Replace('<a href="/" aria-label="Ana Sayfa">','<a href="/" data-utx-view="home" aria-label="Ana Sayfa">')
$blogBanner=$blogBanner.Replace('<a href="/" aria-label="Ana Sayfa">','<a href="/" data-utx-view="home" aria-label="Ana Sayfa">')
$blog=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'blog-fragment.html'),[Text.Encoding]::UTF8)
$blogStart=$blog.IndexOf('<div class="ut-blog-grid">',[StringComparison]::Ordinal)
$blog=$blog.Substring($blogStart)
$blog=$blog.Substring(0,$blog.LastIndexOf('    </div>',[StringComparison]::Ordinal)).Trim()
$blog=$blog.Replace('ut-blog-','utx-blog-').Replace('ut-read-more','utx-read-more')
$blog=$blog.Replace('<span><svg','<span class="utx-blog-category"><svg')
$blog=[regex]::Replace($blog,'<svg aria-hidden="true"><use href="#ut-i-([^"<]+)"/></svg>',{param($match) Icon $match.Groups[1].Value})
$blog=[regex]::Replace($blog,'<template id="blog-content-.*?</template>','',[Text.RegularExpressions.RegexOptions]::Singleline)
$blog=[regex]::Replace($blog,'<button type="button" class="utx-read-more" data-blog-open="([^"]+)" aria-haspopup="dialog">(.*?)</button>',{param($match) '<a class="utx-read-more" data-blog-open="'+$match.Groups[1].Value+'" href="#/blog/'+$match.Groups[1].Value+'">'+$match.Groups[2].Value+'</a>'},[Text.RegularExpressions.RegexOptions]::Singleline)
$serviceCatalogView=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'services-page-view.html'),[Text.Encoding]::UTF8)
$views=@"
$serviceCatalogView
<div class="utx-page" id="utx-blog-view" hidden aria-label="Blog">$blogBanner<section class="page-body"><div class="wrap"><div class="page-placeholder"><h2>Blog</h2><p>BT altyapısı, siber güvenlik ve dijital dönüşüm üzerine güncel yazılar.</p><p class="page-placeholder-note">Örnek yazılar · Yayın içerikleri hazırlanıyor.</p></div>$blog</div></section></div>
<div class="utx-page" id="utx-detail-view" hidden aria-label="Hizmet detayı"><section class="page-banner" style="background-image: url('https://dev.munitek.com/img/sayfa/cozumlerimiz.jpg')"><div class="wrap page-banner-inner"><nav class="breadcrumb-nav" aria-label="Sayfa konumu"><a href="/" data-utx-view="home">Ana Sayfa</a><span> / </span><a href="/hizmetler" data-utx-view="services">Hizmetlerimiz</a></nav><h1 id="utx-detail-title"></h1><p id="utx-detail-description"></p></div></section><section class="page-body"><div class="wrap"><div class="utx-service-detail" id="utx-detail-topics"></div><a class="btn-ut btn-ut-primary" href="/iletisim">İletişime Geçin $(Icon 'arrow')</a></div></section></div>
"@
$articleView=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'article-view.html'),[Text.Encoding]::UTF8)
$articleJson=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'article-content.json'),[Text.Encoding]::UTF8)
$text=$text.Replace('    </main>',"$views`r`n$articleView`r`n    </main>")
$css=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'correction-additions.css'),[Text.Encoding]::UTF8)
$articleCss=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'article.css'),[Text.Encoding]::UTF8)
$css=$css+"`r`n"+$articleCss
$css=$css+"`r`n"+[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'services-page.css'),[Text.Encoding]::UTF8)
$text=$text.Replace('</head>',"<style id=`"utx-additions`">`r`n$css`r`n</style>`r`n</head>")
$script=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'correction.js'),[Text.Encoding]::UTF8)
$tail=@"
<script type="application/json" id="utx-services-data">$servicesJson</script>
<script type="application/json" id="utx-articles-data">$articleJson</script>
<script id="utx-enhancements">$script</script>
"@
$text=$text.Replace('</body>',"$tail`r`n</body>")
# Sadece varlık adreslerini aynı sunucudaki gerçek dosyalara tam URL yap.
# CSS/görsel/JS içerikleri, orijinal görünüm ve kodlar aynen kullanılır.
function Qualify-Assets([string]$html) {
    $html=[regex]::Replace($html,'(<(?:img|script)\b[^>]*\bsrc=")(/[^"<>]+)',{param($match) $match.Groups[1].Value+'https://dev.munitek.com'+$match.Groups[2].Value})
    $html=[regex]::Replace($html,'(<link\b[^>]*\bhref=")(/[^"<>]+)',{param($match) $match.Groups[1].Value+'https://dev.munitek.com'+$match.Groups[2].Value})
    $html=$html.Replace("url('/img/","url('https://dev.munitek.com/img/")
    return $html
}
$text=Qualify-Assets $text
$originalPreview=Qualify-Assets $source
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'connected-draft.html'),$text,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'original-preview.html'),$originalPreview,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'original-blog-preview.html'),(Qualify-Assets $blogSource),[Text.UTF8Encoding]::new($false))
Write-Output ('Prepared connected-draft.html: '+([IO.FileInfo](Join-Path $PSScriptRoot 'connected-draft.html')).Length+' bytes')
