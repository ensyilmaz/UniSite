$ErrorActionPreference='Stop'
$rootPath=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$pagePath=Join-Path $rootPath 'deneme.html'
$html=[IO.File]::ReadAllText($pagePath,[Text.Encoding]::UTF8)
$services=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'services.json'),[Text.Encoding]::UTF8)|ConvertFrom-Json
$start=$html.IndexOf('<div class="utx-page" id="utx-services-view"',[StringComparison]::Ordinal)
$end=$html.IndexOf('<div class="utx-page" id="utx-blog-view"',$start,[StringComparison]::Ordinal)
if($start -lt 0 -or $end -lt 0){throw 'Expected service and blog view markers were not found.'}
$previousServices=$html.Substring($start,$end-$start)
$banner=[regex]::Match($previousServices,'<section class="page-banner"[^>]*>').Value
if(-not $banner){throw 'Original embedded services banner was not found.'}
$banner=$banner.Replace('class="page-banner"','class="page-banner utx-services-page-banner" aria-hidden="true"')
$iconPaths=@{
 network='<circle cx="12" cy="5" r="2.2"/><circle cx="5" cy="18" r="2.2"/><circle cx="19" cy="18" r="2.2"/><path d="M12 7.2v4.3m0 0-5.3 4.8m5.3-4.8 5.3 4.8"/>'
 shield='<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>'
 server='<rect x="3" y="4" width="18" height="7" rx="1.5"/><rect x="3" y="13" width="18" height="7" rx="1.5"/><path d="M7 7.5h.01M7 16.5h.01"/>'
 compass='<circle cx="12" cy="12" r="9"/><path d="m15.5 8.5-2 5-5 2 2-5Z"/>'
 monitor='<rect x="3" y="4" width="18" height="12" rx="1.5"/><path d="M8 20h8M12 16v4"/>'
 layers='<path d="m12 3 9 5-9 5-9-5Zm-9 10 9 5 9-5"/>'
 headset='<path d="M4 14v-2a8 8 0 0 1 16 0v2"/><rect x="3" y="14" width="4" height="6" rx="1.5"/><rect x="17" y="14" width="4" height="6" rx="1.5"/><path d="M19 20a3 3 0 0 1-3 2h-3"/>'
 laptop='<path d="M4 16V4h16v12M2 16h20v4H2Z"/>'
}
$cards=(@($services|ForEach-Object{
 $service=$_
 '<a class="utx-services-catalog-card" href="#/hizmetler/'+$service.slug+'" data-utx-service="'+$service.slug+'"><div class="utx-services-catalog-head"><span class="utx-services-catalog-icon"><svg class="utx-icon" viewBox="0 0 24 24" aria-hidden="true">'+$iconPaths[$service.icon]+'</svg></span><h2>'+$service.title+'</h2><svg class="utx-services-catalog-arrow" viewBox="0 0 24 24" aria-hidden="true"><path d="m9 5 7 7-7 7"/></svg></div><p>'+$service.description+'</p></a>'
})-join "`r`n")
$view=@"
<div class="utx-page" id="utx-services-view" hidden aria-labelledby="utx-services-page-title">
$banner</section>
<section class="utx-services-page-body"><div class="utx-services-page-wrap">
<div class="utx-services-page-heading"><span class="utx-services-page-mark" aria-hidden="true"></span><h1 id="utx-services-page-title" tabindex="-1">Hizmetlerimiz</h1><p>Altyapıdan güvenliğe, danışmanlıktan 7/24 desteğe uçtan uca BT çözüm ve hizmetleri.</p><p class="utx-services-page-note">Bu sayfanın içeriği hazırlanıyor.</p></div>
<div class="utx-services-catalog">$cards</div></div></section>
</div>
"@
$html=$html.Substring(0,$start)+$view+"`r`n"+$html.Substring($end)
$style=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'services-page.css'),[Text.Encoding]::UTF8)
$html=$html.Replace('</head>',"<style id=`"utx-services-page-style`">`r`n$style`r`n</style>`r`n</head>")
$scriptMatch=[regex]::Match($html,'<script id="utx-enhancements">(?<body>.*?)</script>',[Text.RegularExpressions.RegexOptions]::Singleline)
$script=$scriptMatch.Groups['body'].Value
$oldHandler="            event.stopPropagation();`n            if (activeTrigger === trigger && !openedByHover) closePanel(); else openPanel(trigger);"
$newHandler=@'
            event.stopPropagation();
            if (trigger.dataset.utxDropdown === 'utx-services-menu' && !event.target.closest('.utx-nav-chevron')) {
                navigate('#/hizmetler');
                return;
            }
            if (activeTrigger === trigger && !openedByHover) closePanel(); else openPanel(trigger);
'@
$script=$script.Replace("`r`n","`n")
if(-not $script.Contains($oldHandler)){throw 'Expected dropdown handler was not found; no file was written.'}
$script=$script.Replace($oldHandler,$newHandler.Replace("`r`n","`n"))
$html=$html.Substring(0,$scriptMatch.Groups['body'].Index)+$script+$html.Substring($scriptMatch.Groups['body'].Index+$scriptMatch.Groups['body'].Length)
[IO.File]::WriteAllText($pagePath,$html,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'services-page-view.html'),$view,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'correction.js'),$script.Trim(),[Text.UTF8Encoding]::new($false))
Write-Output 'Updated only the services page, its scoped style and the services heading click handler.'
