    function Open-VerifiedPage([string]$LocalPath) {
        $null = Send-Cdp 'Page.navigate' @{ url = ([Uri]$LocalPath).AbsoluteUri }
        $loaded = $false
        for ($attempt = 0; $attempt -lt 100; $attempt++) {
            $loaded = Invoke-JavaScript "!!document.querySelector('.hero-media') && getComputedStyle(document.querySelector('.hero-media')).maskImage !== 'none' && document.querySelector('.brand-logo').naturalWidth > 0 && document.querySelector('#heroPrev').disabled"
            if ($loaded) { break }
            Start-Sleep -Milliseconds 200
        }
        if (-not $loaded) { throw 'Original site CSS/images/JavaScript did not load. Network verification is required; do not substitute fallback styles.' }
        $null = Invoke-JavaScript 'document.fonts.ready.then(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))))'
    }
    function Get-OriginalGeometry {
        return Invoke-JavaScript "(()=>{const rect=s=>{const r=document.querySelector(s).getBoundingClientRect();return {x:r.x,y:r.y,width:r.width,height:r.height}};return {title:rect('.hero-title'),hero:rect('.hero'),media:rect('.hero-media'),brand:rect('.site-header .brand'),nav:rect('#mainNav'),mask:getComputedStyle(document.querySelector('.hero-media')).maskImage,background:getComputedStyle(document.querySelector('.img-hero-1')).backgroundImage};})()"
    }
    Set-Viewport 1440
    Open-VerifiedPage (Join-Path $workPath 'original-preview.html')
    $baseline = Get-OriginalGeometry
    Save-Screenshot 'correction-original-home.png'
    Assert-QA 'Original source renders with actual site CSS, images and JavaScript' $true
    Open-VerifiedPage $pagePath
    $current = Get-OriginalGeometry
    foreach ($area in @('title','hero','media','brand','nav')) {
        $same = $true
        foreach ($dimension in @('x','y','width','height')) { if ([Math]::Abs($baseline.$area.$dimension-$current.$area.$dimension) -gt 1) { $same=$false } }
        Assert-QA "Original desktop $area geometry is preserved" $same @{original=$baseline.$area;corrected=$current.$area}
    }
    Assert-QA 'Original hero photo and shaped mask are unchanged' ($baseline.mask -ceq $current.mask -and $baseline.background -ceq $current.background)
    Save-Screenshot 'correction-home.png'
    $cta = Invoke-JavaScript "(()=>{const a=document.querySelector('.utx-hero-contact'),r=a.getBoundingClientRect(),f=document.querySelector('.hero-features').getBoundingClientRect(),p=document.querySelector('.hero-lead').getBoundingClientRect();return {exists:!!a,href:a.href,gap:r.top-p.bottom,clear:r.bottom<f.top};})()"
    Assert-QA 'Contact CTA occupies the original gap without covering feature strip' ($cta.exists -and $cta.clear -and $cta.gap -ge 8 -and $cta.href.EndsWith('/iletisim')) $cta
    $mega = Invoke-JavaScript "(()=>{const t=document.querySelector('[data-utx-dropdown=utx-services-menu]');t.click();const p=document.querySelector('#utx-services-menu'),r=p.getBoundingClientRect();return {open:!p.hidden,groups:p.querySelectorAll('.utx-mega-group').length,topics:p.querySelectorAll('[data-utx-topic]').length,fits:r.left>=0&&r.right<=innerWidth};})()"
    Assert-QA 'Services mega menu opens with eight groups and 24 subtopics' ($mega.open -and $mega.groups -eq 8 -and $mega.topics -eq 24 -and $mega.fits) $mega
    Save-Screenshot 'correction-mega.png'
    $null = Send-Cdp 'Input.dispatchKeyEvent' @{type='keyDown';key='Escape';code='Escape';windowsVirtualKeyCode=27}
    $closed = Invoke-JavaScript "document.querySelector('#utx-services-menu').hidden"
    Assert-QA 'Escape closes the new mega menu' ([bool]$closed)
    $null = Send-Cdp 'Input.dispatchKeyEvent' @{type='keyUp';key='Escape';code='Escape';windowsVirtualKeyCode=27}
    $null = Invoke-JavaScript "document.querySelector('[data-utx-dropdown=utx-services-menu]').dispatchEvent(new PointerEvent('pointerenter',{pointerType:'mouse'}));document.querySelector('[data-utx-dropdown=utx-services-menu]').click()"
    $hoverClick = Invoke-JavaScript "!document.querySelector('#utx-services-menu').hidden"
    Assert-QA 'First click after mouse hover keeps mega menu open' ([bool]$hoverClick)
    $null = Invoke-JavaScript "document.querySelector('.hero-title').click()"
    Set-Route '#/blog'
    $blog = Invoke-JavaScript "(()=>{const p=document.querySelector('#utx-blog-view'),g=p.querySelector('.utx-blog-grid');return {visible:!p.hidden,count:g.children.length,columns:getComputedStyle(g).gridTemplateColumns.split(/\s+/).length};})()"
    Assert-QA 'Blog displays nine cards in three columns' ($blog.visible -and $blog.count -eq 9 -and $blog.columns -eq 3) $blog
    Save-Screenshot 'correction-blog.png'
    $null = Invoke-JavaScript "document.querySelector('#utx-blog-view [data-blog-open]').click()"
    Assert-QA 'Blog read-more opens its dialog' ([bool](Invoke-JavaScript "document.querySelector('#utx-blog-dialog').open"))
    Set-Route '#/hizmetler'
    Assert-QA 'View navigation closes article dialog' ([bool](Invoke-JavaScript "!document.querySelector('#utx-blog-dialog').open"))
    $services = Invoke-JavaScript "(()=>{const p=document.querySelector('#utx-services-view'),g=p.querySelector('.utx-service-grid');return {visible:!p.hidden,cards:g.children.length,topics:g.querySelectorAll('.utx-service-topics').length,columns:getComputedStyle(g).gridTemplateColumns.split(/\s+/).length};})()"
    Assert-QA 'Services show eight cards in four columns with visible subheadings' ($services.visible -and $services.cards -eq 8 -and $services.topics -eq 8 -and $services.columns -eq 4) $services
    Save-Screenshot 'correction-services.png'
    $null = Invoke-JavaScript "document.querySelector('#utx-services-view [data-utx-topic]').click();new Promise(r=>setTimeout(r,120))"
    $detail = Invoke-JavaScript "({open:!document.querySelector('#utx-detail-view').hidden,focused:document.activeElement.classList.contains('utx-detail-topic')})"
    Assert-QA 'Service subtopic navigation opens and focuses its content' ($detail.open -and $detail.focused) $detail
    $docs = Invoke-JavaScript "({legal:!!document.querySelector('.utx-legal-bar a[href$=\"/kurumsal/belgelerimiz\"]'),corporate:!!document.querySelector('#utx-corporate-menu a[href$=\"/kurumsal/belgelerimiz\"]')})"
    Assert-QA 'Documents moved beside legal links and removed from corporate menu' ($docs.legal -and -not $docs.corporate) $docs
    Set-Viewport 390
    Set-Route '#/'
    Save-Screenshot 'correction-mobile-home.png'
    $null = Invoke-JavaScript "document.querySelector('#navToggle').click();document.querySelector('[data-utx-dropdown=utx-services-menu]').click()"
    $mobile = Invoke-JavaScript "(()=>{const p=document.querySelector('#utx-services-menu'),r=p.getBoundingClientRect();return {open:!p.hidden,originalNav:document.querySelector('#siteHeader').classList.contains('nav-open'),fits:r.left>=0&&r.right<=innerWidth&&r.bottom<=innerHeight,groups:p.querySelectorAll('.utx-mega-group').length};})()"
    Assert-QA 'New mega menu works with original mobile menu and fits viewport' ($mobile.open -and $mobile.originalNav -and $mobile.fits -and $mobile.groups -eq 8) $mobile
    Save-Screenshot 'correction-mobile-mega.png'
    $null = Invoke-JavaScript "document.querySelector('#utx-services-menu [data-utx-topic]').click();new Promise(r=>setTimeout(r,120))"
    Assert-QA 'Mobile subtopic selection uses existing menu close behavior' ([bool](Invoke-JavaScript "!document.querySelector('#siteHeader').classList.contains('nav-open')&&!document.querySelector('#utx-detail-view').hidden"))
    foreach ($width in @(1440,1024,768,390,360)) {
        Set-Viewport $width
        foreach ($route in @('#/blog','#/hizmetler')) {
            Set-Route $route
            $overflow=Invoke-JavaScript "({width:innerWidth,page:document.documentElement.scrollWidth})"
            Assert-QA "New content fits ${width}px on $route" ($overflow.page -le $overflow.width+1) $overflow
        }
    }
    Assert-QA 'No JavaScript runtime exceptions' ($script:exceptions.Count -eq 0) $script:exceptions
