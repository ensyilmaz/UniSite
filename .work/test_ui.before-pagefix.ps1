param(
    [switch]$Probe,
    [ValidateRange(1024,65535)][int]$Port = 9230
)

$ErrorActionPreference = 'Stop'
$workspacePath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$workPath = Join-Path $workspacePath '.work'
$edgePath = 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'
$pagePath = Join-Path $workspacePath 'deneme.html'
$script:socket = $null
$script:commandId = 0
$script:exceptions = @()
$script:checks = @()
$edgeProcess = $null

function Send-Cdp {
    param([string]$Method, [hashtable]$Parameters = @{})
    $script:commandId++
    $currentId = $script:commandId
    $payload = @{ id = $currentId; method = $Method; params = $Parameters } | ConvertTo-Json -Depth 30 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($payload)
    $segment = [ArraySegment[byte]]::new($bytes)
    $timeoutSource = [Threading.CancellationTokenSource]::new(20000)
    try {
        $null = $script:socket.SendAsync($segment, [Net.WebSockets.WebSocketMessageType]::Text, $true, $timeoutSource.Token).GetAwaiter().GetResult()
        while ($true) {
            $memory = [IO.MemoryStream]::new()
            try {
                do {
                    $buffer = New-Object byte[] 65536
                    $received = $script:socket.ReceiveAsync([ArraySegment[byte]]::new($buffer), $timeoutSource.Token).GetAwaiter().GetResult()
                    if ($received.MessageType -eq [Net.WebSockets.WebSocketMessageType]::Close) { throw 'Edge closed the CDP connection.' }
                    $memory.Write($buffer, 0, $received.Count)
                } until ($received.EndOfMessage)
                $message = [Text.Encoding]::UTF8.GetString($memory.ToArray()) | ConvertFrom-Json
            } finally { $memory.Dispose() }
            if ($script:watchOffline -and $message.method -eq 'Network.requestWillBeSent' -and $message.params.request.url -match '^https?://') { $script:offlineRequests += [string]$message.params.request.url }
            if ($message.method -eq 'Runtime.exceptionThrown') {
                $details = $message.params.exceptionDetails
                $description = $details.text
                if ($details.exception.description) { $description = $details.exception.description }
                $script:exceptions += [string]$description
            }
            if ($message.id -eq $currentId) {
                if ($message.error) { throw ($message.error | ConvertTo-Json -Compress) }
                return $message.result
            }
        }
    } finally { $timeoutSource.Dispose() }
}

function Invoke-JavaScript {
    param([string]$Expression)
    $evaluation = Send-Cdp 'Runtime.evaluate' @{ expression = $Expression; awaitPromise = $true; returnByValue = $true; userGesture = $true }
    if ($evaluation.exceptionDetails) { throw ($evaluation.exceptionDetails | ConvertTo-Json -Depth 10 -Compress) }
    return $evaluation.result.value
}

function Assert-QA {
    param([string]$Name, [bool]$Passed, $Details = $null)
    $script:checks += [pscustomobject]@{ name = $Name; passed = $Passed; details = $Details }
    $status = if ($Passed) { 'PASS' } else { 'FAIL' }
    Write-Output "$status $Name"
    if (-not $Passed -and $null -ne $Details) { Write-Output ($Details | ConvertTo-Json -Depth 10 -Compress) }
}

function Set-Viewport {
    param([int]$Width, [int]$Height = 1050)
    $null = Send-Cdp 'Emulation.setDeviceMetricsOverride' @{ width = $Width; height = $Height; deviceScaleFactor = 1; mobile = ($Width -lt 600) }
    $null = Invoke-JavaScript 'new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))'
}

function Set-Route {
    param([string]$Route)
    $literal = ConvertTo-Json -InputObject $Route -Compress
    $null = Invoke-JavaScript "location.hash = $literal; new Promise(resolve => setTimeout(resolve, 120))"
}

function Save-Screenshot {
    param([string]$Name)
    $shot = Send-Cdp 'Page.captureScreenshot' @{ format = 'png'; captureBeyondViewport = $false; fromSurface = $true }
    [IO.File]::WriteAllBytes((Join-Path $workPath $Name), [Convert]::FromBase64String($shot.data))
}

try {
    if (-not (Test-Path -LiteralPath $edgePath)) { throw "Edge was not found at $edgePath" }
    if (-not (Test-Path -LiteralPath $pagePath)) { throw "Page was not found at $pagePath" }
    $portAlreadyInUse = $false
    try {
        $existingDebugger = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json/version" -TimeoutSec 1
        $portAlreadyInUse = [bool]$existingDebugger.webSocketDebuggerUrl
    } catch { }
    if ($portAlreadyInUse) { throw "Port $Port already belongs to another debugger; choose a different -Port." }
    $null = New-Item -ItemType Directory -Path $workPath -Force
    $profilePath = Join-Path $workPath ('edge-qa-' + [Guid]::NewGuid().ToString('N'))
    $arguments = @('--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check', '--disable-background-networking', '--allow-file-access-from-files', "--remote-debugging-port=$Port", "--remote-allow-origins=http://127.0.0.1:$Port", "--user-data-dir=`"$profilePath`"", 'about:blank')
    $edgeProcess = Start-Process -FilePath $edgePath -ArgumentList $arguments -WindowStyle Hidden -PassThru
    $target = $null
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        try {
            $targets = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json/list" -TimeoutSec 2
            $target = @($targets | Where-Object { $_.type -eq 'page' })[0]
            if ($target.webSocketDebuggerUrl) { break }
        } catch { Start-Sleep -Milliseconds 200 }
    }
    if (-not $target.webSocketDebuggerUrl) { throw 'Edge did not expose a CDP page target.' }
    $script:socket = [Net.WebSockets.ClientWebSocket]::new()
    $null = $script:socket.ConnectAsync([Uri]$target.webSocketDebuggerUrl, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
    $null = Send-Cdp 'Page.enable'
    $null = Send-Cdp 'Runtime.enable'
    $null = Send-Cdp 'Emulation.setEmulatedMedia' @{ features = @(@{ name = 'prefers-reduced-motion'; value = 'reduce' }) }
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
        $assetWait = @'
(async()=>{
 const elements=[...document.querySelectorAll('.hero-slide,.process,.showcase-about,.project-media,.site-footer')];
 const urls=[...new Set(elements.flatMap(el=>[...getComputedStyle(el).backgroundImage.matchAll(/url\(["']?([^"')]+)["']?\)/g)].map(m=>m[1])).filter(url=>url.startsWith('http')))];
 return await Promise.all(urls.map(url=>new Promise(resolve=>{const img=new Image();img.onload=()=>resolve(true);img.onerror=()=>resolve(false);img.src=url;})));
})()
'@
        $assetStates = Invoke-JavaScript $assetWait
        if (@($assetStates | Where-Object { -not $_ }).Count -gt 0) { throw 'An original background image could not load.' }
        $null = Invoke-JavaScript 'new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)))'
    }
    function Get-OriginalGeometry {
        return Invoke-JavaScript "(()=>{const rect=s=>{const r=document.querySelector(s).getBoundingClientRect();return {x:r.x,y:r.y,width:r.width,height:r.height}};return {title:rect('.hero-title'),hero:rect('.hero'),media:rect('.hero-media'),brand:rect('.site-header .brand'),nav:rect('#mainNav'),mask:getComputedStyle(document.querySelector('.hero-media')).maskImage,background:getComputedStyle(document.querySelector('.img-hero-1')).backgroundImage};})()"
    }
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

    $report = @{ checks = $script:checks; runtimeErrors = $script:exceptions; passed = @($script:checks | Where-Object passed).Count; failed = @($script:checks | Where-Object { -not $_.passed }).Count }
    $report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $workPath 'ui-report.json') -Encoding UTF8
    Write-Output ("Completed: {0} passed, {1} failed" -f $report.passed, $report.failed)
    if ($report.failed -gt 0) { exit 1 }
} finally {
    if ($script:socket) {
        if ($script:socket.State -eq [Net.WebSockets.WebSocketState]::Open) {
            try { $null = Send-Cdp 'Browser.close' } catch { }
        }
        $script:socket.Dispose()
    }
    if ($edgeProcess) {
        $edgeProcess.Refresh()
        if (-not $edgeProcess.HasExited) { Stop-Process -Id $edgeProcess.Id -ErrorAction SilentlyContinue }
    }
}
