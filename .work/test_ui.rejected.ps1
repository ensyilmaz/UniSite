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
    Set-Viewport 1440
    $null = Send-Cdp 'Page.navigate' @{ url = ([Uri]$pagePath).AbsoluteUri }
    for ($attempt = 0; $attempt -lt 80; $attempt++) {
        $ready = Invoke-JavaScript "document.readyState !== 'loading' && !!document.querySelector('#page-home')"
        if ($ready) { break }
        Start-Sleep -Milliseconds 150
    }
    $null = Invoke-JavaScript 'new Promise(resolve => setTimeout(resolve, 350))'
    if ($Probe) {
        $state = Invoke-JavaScript "({title:document.title,ready:document.readyState,viewport:innerWidth,pages:[...document.querySelectorAll('[id^=page-]')].map(el=>el.id)})"
        Write-Output ($state | ConvertTo-Json -Depth 10)
    }

    Set-Route '#/'
    $homeState = Invoke-JavaScript "({visible:!!document.querySelector('#page-home')&&!document.querySelector('#page-home').hidden,cta:!!document.querySelector('#heroContact'),why:!!document.querySelector('#neden-uniturk')})"
    Assert-QA 'Homepage, contact CTA and why section exist' ($homeState.visible -and $homeState.cta -and $homeState.why) $homeState
    Save-Screenshot 'desktop-home.png'

    $dropdown = Invoke-JavaScript "(()=>{const button=document.querySelector('#mainNav button[data-dropdown],#mainNav [data-dropdown] button');if(!button)return {exists:false};button.click();return {exists:true,expanded:button.getAttribute('aria-expanded')==='true'};})()"
    Assert-QA 'Desktop dropdown opens by click' ($dropdown.exists -and $dropdown.expanded) $dropdown
    $null = Send-Cdp 'Input.dispatchKeyEvent' @{ type = 'keyDown'; key = 'Escape'; code = 'Escape'; windowsVirtualKeyCode = 27 }
    $null = Send-Cdp 'Input.dispatchKeyEvent' @{ type = 'keyUp'; key = 'Escape'; code = 'Escape'; windowsVirtualKeyCode = 27 }
    $closed = Invoke-JavaScript "!document.querySelector('#mainNav button[data-dropdown][aria-expanded=true],#mainNav [data-dropdown] button[aria-expanded=true]')"
    Assert-QA 'Escape closes desktop dropdown' ([bool]$closed)

    $mega = Invoke-JavaScript "(()=>{const button=document.querySelector('[aria-controls=servicesMenu]');button.click();const panel=document.querySelector('#servicesMenu');const bounds=panel.getBoundingClientRect();return {open:button.getAttribute('aria-expanded')==='true'&&!panel.hidden,groups:panel.querySelectorAll('.ut-mega-group').length,topics:panel.querySelectorAll('.ut-mega-group ul a').length,fits:bounds.left>=0&&bounds.right<=innerWidth};})()"
    Assert-QA 'Services mega-menu shows eight groups and 24 topics' ($mega.open -and $mega.groups -eq 8 -and $mega.topics -eq 24 -and $mega.fits) $mega
    Save-Screenshot 'desktop-mega-menu.png'
    $null = Invoke-JavaScript "const servicesButton=document.querySelector('[aria-controls=servicesMenu]');servicesButton.click();servicesButton.focus()"
    $null = Send-Cdp 'Input.dispatchKeyEvent' @{ type = 'keyDown'; key = 'ArrowDown'; code = 'ArrowDown'; windowsVirtualKeyCode = 40 }
    $keyboardMega = Invoke-JavaScript "!document.querySelector('#servicesMenu').hidden&&!!document.activeElement.closest('#servicesMenu')"
    Assert-QA 'ArrowDown enters services mega-menu with keyboard' ([bool]$keyboardMega)
    $null = Send-Cdp 'Input.dispatchKeyEvent' @{ type = 'keyUp'; key = 'ArrowDown'; code = 'ArrowDown'; windowsVirtualKeyCode = 40 }
    $null = Invoke-JavaScript "document.querySelector('#page-home h1').click()"
    $outsideClosed = Invoke-JavaScript "document.querySelector('#servicesMenu').hidden"
    Assert-QA 'Click outside closes mega-menu' ([bool]$outsideClosed)
    $headingToggle = Invoke-JavaScript "(()=>{const oldHash=location.hash;const link=[...document.querySelectorAll('#mainNav a')].find(a=>a.getAttribute('href')==='/hizmetler');link.click();const opened=!document.querySelector('#servicesMenu').hidden;link.click();return {opened,closed:document.querySelector('#servicesMenu').hidden,routeUnchanged:location.hash===oldHash};})()"
    Assert-QA 'Services heading toggles mega-menu without navigating' ($headingToggle.opened -and $headingToggle.closed -and $headingToggle.routeUnchanged) $headingToggle

    Set-Route '#/blog'
    $blog = Invoke-JavaScript "(()=>{const page=document.querySelector('#page-blog'),grid=page?.querySelector('.ut-blog-grid');return {visible:!!page&&!page.hidden,count:grid?.querySelectorAll('.ut-blog-card').length,columns:grid?getComputedStyle(grid).gridTemplateColumns.split(/\s+/).length:0};})()"
    Assert-QA 'Blog displays nine cards in three columns' ($blog.visible -and $blog.count -eq 9 -and $blog.columns -eq 3) $blog
    Save-Screenshot 'desktop-blog.png'
    $article = Invoke-JavaScript "(()=>{const button=document.querySelector('#page-blog [data-blog-open]');button?.click();const dialog=document.querySelector('dialog[open],[role=dialog]:not([hidden])');return {button:!!button,dialog:!!dialog};})()"
    Assert-QA 'Blog read-more opens article' ($article.button -and $article.dialog) $article
    $null = Send-Cdp 'Input.dispatchKeyEvent' @{ type = 'keyDown'; key = 'Escape'; code = 'Escape'; windowsVirtualKeyCode = 27 }
    $null = Send-Cdp 'Input.dispatchKeyEvent' @{ type = 'keyUp'; key = 'Escape'; code = 'Escape'; windowsVirtualKeyCode = 27 }

    Set-Route '#/hizmetler'
    $services = Invoke-JavaScript "(()=>{const page=document.querySelector('#page-services'),grid=page?.querySelector('.ut-service-grid');return {visible:!!page&&!page.hidden,count:grid?.querySelectorAll('.ut-service-card').length,columns:grid?getComputedStyle(grid).gridTemplateColumns.split(/\s+/).length:0,topics:grid?.querySelectorAll('.ut-service-topics').length};})()"
    Assert-QA 'Services display eight cards in four columns with subtopics' ($services.visible -and $services.count -eq 8 -and $services.columns -eq 4 -and $services.topics -eq 8) $services
    Save-Screenshot 'desktop-services.png'

    $null = Invoke-JavaScript "document.querySelector('#page-services .ut-service-topics a').click();new Promise(resolve=>setTimeout(resolve,120))"
    $topicState = Invoke-JavaScript "({visible:!document.querySelector('#page-detail').hidden,route:location.hash,topic:document.activeElement.classList.contains('ut-topic')})"
    Assert-QA 'Service subtopic link opens and focuses its section' ($topicState.visible -and $topicState.route.Contains('konu=') -and $topicState.topic) $topicState

    Set-Route '#/hizmetler/ag-altyapilari-ve-sd-wan'
    $detail = Invoke-JavaScript "(()=>{const page=document.querySelector('#page-detail');return {visible:!!page&&!page.hidden,text:page?.textContent.includes('SD-WAN')};})()"
    Assert-QA 'Service detail navigation works' ($detail.visible -and $detail.text) $detail

    Set-Route '#/'
    $null = Invoke-JavaScript "document.querySelector('#heroContact').click();new Promise(resolve=>setTimeout(resolve,120))"
    $contactState = Invoke-JavaScript "({visible:!document.querySelector('#page-home').hidden,route:location.hash,focused:document.activeElement.id==='iletisim'})"
    Assert-QA 'Hero contact CTA reaches contact section' ($contactState.visible -and $contactState.route.Contains('iletisim') -and $contactState.focused) $contactState
    $documentsState = Invoke-JavaScript "(()=>{const footerLink=[...document.querySelectorAll('footer a')].find(a=>a.getAttribute('href')==='/kurumsal/belgelerimiz');return {exists:!!footerLink,inLegalBar:!!footerLink?.closest('.ut-legal-bar'),corporateLinks:[...document.querySelectorAll('#corporateMenu a')].some(a=>a.textContent.includes('Belgelerimiz')||a.textContent.includes('Neden'))};})()"
    Assert-QA 'Documents link preserves backend URL in legal footer only' ($documentsState.exists -and $documentsState.inLegalBar -and -not $documentsState.corporateLinks) $documentsState
    $null = Invoke-JavaScript "[...document.querySelectorAll('footer a')].find(a=>a.getAttribute('href')==='/kurumsal/belgelerimiz').click();new Promise(resolve=>setTimeout(resolve,120))"
    $documentsView = Invoke-JavaScript "!document.querySelector('#page-info').hidden&&document.querySelector('#info-title').textContent==='Belgelerimiz'"
    Assert-QA 'Documents link opens standalone document view' ([bool]$documentsView)

    Set-Route '#/blog'
    $null = Invoke-JavaScript "document.querySelector('.ut-skip-link').click();new Promise(resolve=>setTimeout(resolve,80))"
    $skipState = Invoke-JavaScript "({blog:!document.querySelector('#page-blog').hidden,route:location.hash,focused:document.activeElement.id==='mainContent'})"
    Assert-QA 'Skip link focuses content without changing blog route' ($skipState.blog -and $skipState.route -eq '#/blog' -and $skipState.focused) $skipState
    $null = Invoke-JavaScript "document.querySelector('#searchToggle').click();document.querySelector('#headerSearch input').value='laptop';document.querySelector('#headerSearch').requestSubmit();new Promise(resolve=>setTimeout(resolve,80))"
    $searchState = Invoke-JavaScript "(()=>{const form=document.querySelector('#headerSearch'),results=document.querySelector('#ut-search-results'),formRect=form.getBoundingClientRect(),resultsRect=results.getBoundingClientRect();return {formVisible:!form.hidden,input:form.querySelector('input').value,resultsVisible:!results.hidden,count:results.querySelectorAll('a').length,noOverlap:resultsRect.top>=formRect.bottom-1,fits:resultsRect.left>=0&&resultsRect.right<=innerWidth};})()"
    Assert-QA 'Search shows results below visible input without overlap' ($searchState.formVisible -and $searchState.input -eq 'laptop' -and $searchState.resultsVisible -and $searchState.count -gt 0 -and $searchState.noOverlap -and $searchState.fits) $searchState
    $null = Invoke-JavaScript "document.querySelector('#ut-search-results a').click();new Promise(resolve=>setTimeout(resolve,120))"
    $searchNavigation = Invoke-JavaScript "!document.querySelector('#page-detail').hidden&&document.querySelector('#headerSearch').hidden&&document.querySelector('#ut-search-results').hidden"
    Assert-QA 'Search result navigates and closes search' ([bool]$searchNavigation)

    foreach ($width in @(1440, 1200, 1120, 1101, 1024, 768, 390, 360)) {
        Set-Viewport $width
        foreach ($route in @('#/', '#/blog', '#/hizmetler')) {
            Set-Route $route
            $overflow = Invoke-JavaScript "({viewport:innerWidth,document:document.documentElement.scrollWidth,body:document.body.scrollWidth})"
            Assert-QA "No horizontal overflow at ${width}px on $route" (($overflow.document -le $overflow.viewport + 1) -and ($overflow.body -le $overflow.viewport + 1)) $overflow
        }
    }
    Set-Viewport 390
    Set-Route '#/hizmetler'
    $mobileGrid = Invoke-JavaScript "(()=>{const grid=document.querySelector('#page-services .ut-service-grid');return getComputedStyle(grid).gridTemplateColumns.split(/\s+/).length;})()"
    Assert-QA 'Mobile services use one column' ($mobileGrid -eq 1) $mobileGrid
    Save-Screenshot 'mobile-services.png'
    $mobileMenu = Invoke-JavaScript "(()=>{const toggle=document.querySelector('#navToggle');toggle?.click();return {exists:!!toggle,expanded:toggle?.getAttribute('aria-expanded')==='true',visible:!!document.querySelector('#mainNav')&&getComputedStyle(document.querySelector('#mainNav')).display!=='none'};})()"
    Assert-QA 'Mobile navigation opens' ($mobileMenu.exists -and $mobileMenu.expanded -and $mobileMenu.visible) $mobileMenu
    $mobileMega = Invoke-JavaScript "(()=>{document.querySelector('[aria-controls=servicesMenu]').click();const panel=document.querySelector('#servicesMenu');const bounds=panel.getBoundingClientRect();return {open:!panel.hidden,groups:panel.querySelectorAll('.ut-mega-group').length,fits:bounds.left>=0&&bounds.right<=innerWidth,overflow:document.documentElement.scrollWidth<=innerWidth};})()"
    Assert-QA 'Mobile services mega-menu shows all groups without overflow' ($mobileMega.open -and $mobileMega.groups -eq 8 -and $mobileMega.fits -and $mobileMega.overflow) $mobileMega
    Save-Screenshot 'mobile-mega-menu.png'
    $null = Invoke-JavaScript "[...document.querySelectorAll('#servicesMenu .ut-mega-group ul a')].at(-1).scrollIntoView({block:'nearest'});new Promise(resolve=>requestAnimationFrame(resolve))"
    $mobileLastLink = Invoke-JavaScript "(()=>{const link=[...document.querySelectorAll('#servicesMenu .ut-mega-group ul a')].at(-1),linkRect=link.getBoundingClientRect(),navRect=document.querySelector('#mainNav').getBoundingClientRect();return {visible:linkRect.top>=navRect.top&&linkRect.bottom<=navRect.bottom,navScroll:document.querySelector('#mainNav').scrollTop};})()"
    Assert-QA 'Last mobile mega-menu topic is reachable by scrolling' ($mobileLastLink.visible -and $mobileLastLink.navScroll -gt 0) $mobileLastLink
    $null = Invoke-JavaScript "[...document.querySelectorAll('#servicesMenu .ut-mega-group ul a')].at(-1).click();new Promise(resolve=>setTimeout(resolve,120))"
    $mobileLink = Invoke-JavaScript "({detail:!document.querySelector('#page-detail').hidden,closed:document.querySelector('#navToggle').getAttribute('aria-expanded')==='false'&&document.querySelector('#servicesMenu').hidden,topic:document.activeElement.classList.contains('ut-topic')})"
    Assert-QA 'Mobile subtopic navigation closes menu and opens detail' ($mobileLink.detail -and $mobileLink.closed -and $mobileLink.topic) $mobileLink
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
