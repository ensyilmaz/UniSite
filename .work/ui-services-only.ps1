    Set-Viewport 1440
    $null=Send-Cdp 'Network.enable'
    $null=Send-Cdp 'Network.emulateNetworkConditions' @{offline=$true;latency=0;downloadThroughput=0;uploadThroughput=0}
    $script:watchOffline=$true
    $script:offlineRequests=@()
    Open-VerifiedPage $pagePath
    $null=Invoke-JavaScript "document.querySelector('[data-utx-dropdown=utx-services-menu]').click();new Promise(r=>setTimeout(r,180))"
    $catalog=Invoke-JavaScript "(()=>{const p=document.querySelector('#utx-services-view'),g=p.querySelector('.utx-services-catalog');const cards=[...g.children];return {visible:!p.hidden,hash:location.hash,columns:getComputedStyle(g).gridTemplateColumns.split(/\s+/).length,count:cards.length,allLinks:cards.every(c=>c.tagName==='A'&&c.getAttribute('href').startsWith('#/hizmetler/')),firstRow:cards.slice(0,4).map(c=>c.getBoundingClientRect().top),secondRow:cards.slice(4).map(c=>c.getBoundingClientRect().top),banner:p.querySelector('.page-banner').getBoundingClientRect().height};})()"
    Assert-QA 'Navbar Services title opens its own local page' ($catalog.visible -and $catalog.hash -eq '#/hizmetler') $catalog
    Assert-QA 'Services match the four-by-two clickable card layout' ($catalog.count -eq 8 -and $catalog.columns -eq 4 -and $catalog.allLinks -and @($catalog.firstRow|Select-Object -Unique).Count -eq 1 -and @($catalog.secondRow|Select-Object -Unique).Count -eq 1 -and $catalog.secondRow[0] -gt $catalog.firstRow[0]) $catalog
    Assert-QA 'Services use the requested short image banner' ($catalog.banner -eq 160) $catalog.banner
    Save-Screenshot 'services-fixed-desktop.png'
    $serviceEntries=Invoke-JavaScript "JSON.parse(document.querySelector('#utx-services-data').textContent).map(s=>({slug:s.slug,title:s.title}))"
    foreach($service in $serviceEntries) {
        Set-Route '#/hizmetler'
        $slugLiteral=ConvertTo-Json -InputObject $service.slug -Compress
        $null=Invoke-JavaScript "[...document.querySelectorAll('.utx-services-catalog-card')].find(a=>a.dataset.utxService===$slugLiteral).click();new Promise(r=>setTimeout(r,120))"
        $detail=Invoke-JavaScript "({visible:!document.querySelector('#utx-detail-view').hidden,title:document.querySelector('#utx-detail-title').textContent,topics:document.querySelectorAll('#utx-detail-topics .utx-detail-topic').length})"
        Assert-QA ('Card opens correct service: '+$service.title) ($detail.visible -and $detail.title -ceq $service.title -and $detail.topics -eq 3) $detail
    }
    Set-Route '#/'
    $null=Invoke-JavaScript "document.querySelector('[data-utx-dropdown=utx-services-menu] .utx-nav-chevron').dispatchEvent(new MouseEvent('click',{bubbles:true,cancelable:true}));new Promise(r=>setTimeout(r,240))"
    $dropdown=Invoke-JavaScript "({open:!document.querySelector('#utx-services-menu').hidden,links:document.querySelectorAll('#utx-services-menu a').length,hash:location.hash})"
    Assert-QA 'Services arrow retains the simple eight-title dropdown' ($dropdown.open -and $dropdown.links -eq 8 -and $dropdown.hash -eq '#/') $dropdown
    Set-Route '#/hizmetler'
    $null=Send-Cdp 'Page.reload' @{}
    $reloaded=$false
    for($attempt=0;$attempt -lt 100;$attempt++) {
        try {$reloaded=Invoke-JavaScript "document.readyState==='complete'&&!!document.querySelector('#utx-services-view')&&!document.querySelector('#utx-services-view').hidden&&document.querySelectorAll('.utx-services-catalog-card').length===8"}catch{$reloaded=$false}
        if($reloaded){break}
        Start-Sleep -Milliseconds 150
    }
    Assert-QA 'Services page opens correctly after direct reload offline' ([bool]$reloaded)
    Set-Viewport 390
    $mobile=Invoke-JavaScript "(()=>{const g=document.querySelector('.utx-services-catalog'),r=g.getBoundingClientRect();return {columns:getComputedStyle(g).gridTemplateColumns.split(/\s+/).length,left:r.left,right:r.right,width:document.documentElement.clientWidth};})()"
    Assert-QA 'Service cards fit a single column on mobile' ($mobile.columns -eq 1 -and $mobile.left -ge 0 -and $mobile.right -le $mobile.width+1) $mobile
    Save-Screenshot 'services-fixed-mobile.png'
    $before=[IO.File]::ReadAllText((Join-Path $workPath 'before-services-only.html'),[Text.Encoding]::UTF8)
    $after=[IO.File]::ReadAllText($pagePath,[Text.Encoding]::UTF8)
    $blogStart='<div class="utx-page" id="utx-blog-view"'
    $blogEnd='<div class="utx-page" id="utx-detail-view"'
    $oldStart=$before.IndexOf($blogStart);$oldEnd=$before.IndexOf($blogEnd,$oldStart)
    $newStart=$after.IndexOf($blogStart);$newEnd=$after.IndexOf($blogEnd,$newStart)
    Assert-QA 'Working Blog page markup is exactly unchanged' ($before.Substring($oldStart,$oldEnd-$oldStart) -ceq $after.Substring($newStart,$newEnd-$newStart))
    $articleStart='<div class="utx-page utx-article-page"'
    $oldStart=$before.IndexOf($articleStart);$oldEnd=$before.IndexOf('</main>',$oldStart)
    $newStart=$after.IndexOf($articleStart);$newEnd=$after.IndexOf('</main>',$newStart)
    Assert-QA 'Working full article page markup is exactly unchanged' ($before.Substring($oldStart,$oldEnd-$oldStart) -ceq $after.Substring($newStart,$newEnd-$newStart))
    Assert-QA 'No online resource requests from fixed Services page' ($script:offlineRequests.Count -eq 0) $script:offlineRequests
    Assert-QA 'No JavaScript runtime exceptions' ($script:exceptions.Count -eq 0) $script:exceptions
