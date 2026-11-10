    Set-Viewport 1440
    $null=Send-Cdp 'Network.enable'
    $null=Send-Cdp 'Network.emulateNetworkConditions' @{offline=$true;latency=0;downloadThroughput=0;uploadThroughput=0}
    Open-VerifiedPage $pagePath
    foreach($route in @('#/blog','#/hizmetler')) {
        Set-Route $route
        $state=Invoke-JavaScript "(()=>{const p=document.querySelector(location.hash==='#/blog'?'#utx-blog-view':'#utx-services-view'),b=p.querySelector('.page-banner'),g=p.querySelector('.utx-blog-grid,.utx-service-grid');const r=b.getBoundingClientRect(),s=getComputedStyle(b);return {hash:location.hash,title:document.title,visible:!p.hidden,pageWidth:p.getBoundingClientRect().width,homeVisible:!document.querySelector('.hero').hidden,banner:{x:r.x,y:r.y,width:r.width,height:r.height,background:s.backgroundImage.slice(0,80),styleLength:b.getAttribute('style').length},grid:{columns:getComputedStyle(g).gridTemplateColumns,cards:g.children.length,width:g.getBoundingClientRect().width},viewport:{w:innerWidth,doc:document.documentElement.scrollWidth}}})()"
        Write-Output ($state|ConvertTo-Json -Depth 10)
        Save-Screenshot $(if($route -eq '#/blog'){'probe-blog.png'}else{'probe-services.png'})
    }
