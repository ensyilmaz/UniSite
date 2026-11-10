    Set-Viewport 1440
    Open-VerifiedPage (Join-Path $workPath 'original-preview.html')
    $baseline = Get-OriginalGeometry
    $null = Send-Cdp 'Network.enable'
    $null = Send-Cdp 'Network.setCacheDisabled' @{cacheDisabled=$true}
    $null = Send-Cdp 'Network.emulateNetworkConditions' @{offline=$true;latency=0;downloadThroughput=0;uploadThroughput=0}
    $script:watchOffline=$true
    $script:offlineRequests=@()
    Open-VerifiedPage $pagePath
    $backgroundAudit = @'
(async()=>{
 const styles=[...document.querySelectorAll('style[data-utx-source]')];
 const css=styles.map(style=>style.textContent).join('\n');
 const urls=[...new Set([...css.matchAll(/url\(\s*(?:"([^"]*)"|'([^']*)'|([^)]*))\s*\)/g)].map(m=>m[1]||m[2]||m[3]).filter(u=>u.startsWith('data:image/')))];
 const loaded=await Promise.all(urls.map(url=>new Promise(resolve=>{const img=new Image();img.onload=()=>resolve(img.naturalWidth>0);img.onerror=()=>resolve(false);img.src=url;})));
 const process=getComputedStyle(document.querySelector('.process'));
 return {images:urls.length,allLoaded:loaded.every(Boolean),processPhoto:process.backgroundImage.startsWith('url("data:image/png;base64,'),processColor:process.backgroundColor};
})()
'@
    $backgrounds=Invoke-JavaScript $backgroundAudit
    Assert-QA 'Every embedded CSS image decodes offline' ($backgrounds.images -gt 12 -and $backgrounds.allLoaded) $backgrounds
    Assert-QA 'Original process photo and background color render after embedding' ($backgrounds.processPhoto -and $backgrounds.processColor -eq 'rgb(5, 25, 55)') $backgrounds
    $current=Get-OriginalGeometry
    foreach ($area in @('title','hero','media','brand','nav')) {
        $same=$true
        foreach($dimension in @('x','y','width','height')) { if([Math]::Abs($baseline.$area.$dimension-$current.$area.$dimension)-gt 1){$same=$false} }
        Assert-QA "Offline original $area geometry is preserved" $same @{original=$baseline.$area;offline=$current.$area}
    }
    Save-Screenshot 'offline-home.png'
    $embedded=Invoke-JavaScript "({css:document.querySelectorAll('style[data-utx-source]').length,js:document.querySelectorAll('script[data-utx-source]').length,images:[...document.images].every(i=>i.src.startsWith('data:')&&i.complete&&i.naturalWidth>0),font:[...document.fonts].some(f=>f.family.includes('Plus Jakarta Sans')&&f.status==='loaded'),external:document.querySelectorAll('script[src],link[rel=stylesheet],img[src^=http]').length})"
    Assert-QA 'All original styles, scripts, images and fonts work offline' ($embedded.css -eq 3 -and $embedded.js -eq 3 -and $embedded.images -and $embedded.font -and $embedded.external -eq 0) $embedded
    $menu=Invoke-JavaScript "(()=>{document.querySelector('[data-utx-dropdown=utx-services-menu]').click();const p=document.querySelector('#utx-services-menu'),r=p.getBoundingClientRect();return {open:!p.hidden,titles:p.querySelectorAll('a').length,subtitles:p.querySelectorAll('ul,.utx-mega-grid,[data-utx-topic]').length,width:r.width,columns:getComputedStyle(p).display};})()"
    Assert-QA 'Services use a narrow dropdown with only eight titles' ($menu.open -and $menu.titles -eq 8 -and $menu.subtitles -eq 0 -and $menu.width -le 320) $menu
    Save-Screenshot 'offline-services-menu.png'
    Set-Route '#/blog'
    $blog=Invoke-JavaScript "({count:document.querySelectorAll('#utx-blog-view .utx-blog-card').length,columns:getComputedStyle(document.querySelector('#utx-blog-view .utx-blog-grid')).gridTemplateColumns.split(/\s+/).length,links:[...document.querySelectorAll('#utx-blog-view [data-blog-open]')].every(a=>a.tagName==='A'&&a.getAttribute('href').startsWith('#/blog/'))})"
    Assert-QA 'Blog retains nine cards and real article links in three columns' ($blog.count -eq 9 -and $blog.columns -eq 3 -and $blog.links) $blog
    Save-Screenshot 'offline-blog.png'
    $null=Invoke-JavaScript "document.querySelector('#utx-blog-view [data-blog-open]').click();new Promise(r=>setTimeout(r,150))"
    $article=Invoke-JavaScript "({visible:!document.querySelector('#utx-article-view').hidden,title:document.querySelector('#utx-article-title').textContent,body:document.querySelector('#utx-article-body').textContent.length,headings:document.querySelectorAll('#utx-article-body h2').length,width:document.querySelector('#utx-article-body').getBoundingClientRect().width,serif:getComputedStyle(document.querySelector('#utx-article-body')).fontFamily,cover:!!document.querySelector('#utx-article-cover svg'),related:document.querySelectorAll('#utx-article-related .utx-blog-card').length,popup:!!document.querySelector('dialog,[aria-haspopup=dialog]'),hash:location.hash})"
    Assert-QA 'Read More opens a full editorial article with cover and readable prose' ($article.visible -and $article.body -gt 1500 -and $article.headings -eq 3 -and $article.width -le 700 -and $article.cover -and $article.related -eq 2 -and -not $article.popup -and $article.hash.StartsWith('#/blog/')) $article
    Save-Screenshot 'offline-article.png'
    $articleHash=Invoke-JavaScript 'location.hash'
    $null=Send-Cdp 'Page.reload' @{}
    $articleReloaded=$false
    for($attempt=0;$attempt -lt 100;$attempt++) {
        try { $articleReloaded=Invoke-JavaScript "document.readyState==='complete'&&!!document.querySelector('#utx-article-view')&&!document.querySelector('#utx-article-view').hidden&&document.querySelector('#utx-article-title').textContent.length>0" } catch { $articleReloaded=$false }
        if($articleReloaded){break}
        Start-Sleep -Milliseconds 150
    }
    Assert-QA 'Direct article route survives reload offline' ([bool]$articleReloaded)
    $null=Invoke-JavaScript "document.querySelector('.utx-article-nav a').click();new Promise(r=>setTimeout(r,150))"
    Assert-QA 'Back to Blog returns to list' ([bool](Invoke-JavaScript "location.hash==='#/blog'&&!document.querySelector('#utx-blog-view').hidden"))
    $articleSlugs=Invoke-JavaScript "Object.keys(JSON.parse(document.querySelector('#utx-articles-data').textContent))"
    foreach($slug in $articleSlugs) {
        Set-Route ('#/blog/'+$slug)
        $state=Invoke-JavaScript "({visible:!document.querySelector('#utx-article-view').hidden,body:document.querySelector('#utx-article-body').textContent.length,duplicates:(()=>{const ids=[...document.querySelectorAll('[id]')].map(e=>e.id);return ids.length-new Set(ids).size})()})"
        Assert-QA "Full article loads without duplicate SVG IDs: $slug" ($state.visible -and $state.body -gt 1500 -and $state.duplicates -eq 0) $state
    }
    Set-Route '#/blog/not-a-real-article'
    Assert-QA 'Unknown article routes return to Blog' ([bool](Invoke-JavaScript "location.hash==='#/blog'&&!document.querySelector('#utx-blog-view').hidden"))
    Set-Viewport 390
    Set-Route $articleHash
    Save-Screenshot 'offline-mobile-article.png'
    $mobile=Invoke-JavaScript "({width:innerWidth,page:document.documentElement.scrollWidth,prose:document.querySelector('#utx-article-body').getBoundingClientRect().width})"
    Assert-QA 'Article reads without horizontal overflow on mobile' ($mobile.page -le $mobile.width+1 -and $mobile.prose -lt 390) $mobile
    Set-Route '#/'
    $null=Invoke-JavaScript "document.querySelector('#navToggle').click();document.querySelector('[data-utx-dropdown=utx-services-menu]').click();new Promise(r=>setTimeout(r,250))"
    $mobileMenu=Invoke-JavaScript "(()=>{const p=document.querySelector('#utx-services-menu'),r=p.getBoundingClientRect();return {open:!p.hidden,count:p.querySelectorAll('a').length,left:r.left,right:r.right,bottom:r.bottom,width:document.documentElement.clientWidth,height:visualViewport.height};})()"
    Assert-QA 'Simple service dropdown works with original mobile menu' ($mobileMenu.open -and $mobileMenu.count -eq 8 -and $mobileMenu.left -ge 0 -and $mobileMenu.right -le $mobileMenu.width+1 -and $mobileMenu.bottom -le $mobileMenu.height+1) $mobileMenu
    Save-Screenshot 'offline-mobile-menu.png'
    Assert-QA 'No HTTP resource requests while offline' ($script:offlineRequests.Count -eq 0) $script:offlineRequests
    Assert-QA 'No JavaScript runtime errors' ($script:exceptions.Count -eq 0) $script:exceptions
