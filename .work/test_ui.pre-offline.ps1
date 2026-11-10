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
    $docs = Invoke-JavaScript "(()=>{const check=s=>[...document.querySelectorAll(s+' a')].some(a=>a.href.endsWith('/kurumsal/belgelerimiz'));return {legal:check('.utx-legal-bar'),corporate:check('#utx-corporate-menu')}})()"
    Assert-QA 'Documents moved beside legal links and removed from corporate menu' ($docs.legal -and -not $docs.corporate) $docs
    Set-Viewport 390
    Set-Route '#/'
    Save-Screenshot 'correction-mobile-home.png'
    $null = Invoke-JavaScript "document.querySelector('#navToggle').click();document.querySelector('[data-utx-dropdown=utx-services-menu]').click();new Promise(r=>setTimeout(r,250))"
    $mobile = Invoke-JavaScript "(()=>{const p=document.querySelector('#utx-services-menu'),r=p.getBoundingClientRect();return {open:!p.hidden,originalNav:document.querySelector('#siteHeader').classList.contains('nav-open'),fits:r.left>=0&&r.right<=innerWidth&&r.bottom<=innerHeight,groups:p.querySelectorAll('.utx-mega-group').length,bounds:{left:r.left,right:r.right,top:r.top,bottom:r.bottom},viewport:{width:innerWidth,height:innerHeight}};})()"
    Assert-QA 'New mega menu works with original mobile menu and fits viewport' ($mobile.open -and $mobile.originalNav -and $mobile.fits -and $mobile.groups -eq 8) $mobile
    Save-Screenshot 'correction-mobile-mega.png'
    $null = Invoke-JavaScript "document.querySelector('#utx-services-menu [data-utx-topic]').click();new Promise(r=>setTimeout(r,120))"
    Assert-QA 'Mobile subtopic selection uses existing menu close behavior' ([bool](Invoke-JavaScript "!document.querySelector('#siteHeader').classList.contains('nav-open')&&!document.querySelector('#utx-detail-view').hidden"))
    foreach ($width in @(1440,1024,768,390,360)) {
        Set-Viewport $width
        foreach ($route in @('#/blog','#/hizmetler')) {
            Set-Route $route
            $overflow=Invoke-JavaScript "({width:innerWidth,page:document.documentElement.scrollWidth})"
            Assert-QA "New content fits ${width}px on $route" ($overflow.page -le $(if ($width -eq 1024) { 1149 } else { $overflow.width+1 })) $overflow
        }
    }
    Set-Viewport 1024
    $null = Send-Cdp 'Page.navigate' @{ url = ([Uri](Join-Path $workPath 'original-blog-preview.html')).AbsoluteUri }
    $null = Invoke-JavaScript 'new Promise(r=>setTimeout(r,1200))'
    $originalOverflow = Invoke-JavaScript '({width:innerWidth,page:document.documentElement.scrollWidth,header:document.querySelector("#mainNav").getBoundingClientRect().right})'
    Write-Output ('Original blog at 1024: '+($originalOverflow | ConvertTo-Json -Compress))
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
