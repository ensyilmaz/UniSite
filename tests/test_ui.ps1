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
