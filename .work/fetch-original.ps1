$ErrorActionPreference = 'Stop'
$assetRoot = Join-Path $PSScriptRoot 'original-assets'
$null = New-Item -ItemType Directory -Path $assetRoot -Force
$origin = [Uri]'https://dev.munitek.com/'
$requests = @(
    @{ Url = '/css/site.css'; Name = 'site.css' },
    @{ Url = '/js/site.js'; Name = 'site.js' },
    @{ Url = '/hizmetler'; Name = 'hizmetler.html' },
    @{ Url = '/blog'; Name = 'blog.html' }
)
$clients = @()
$tasks = @()
foreach ($request in $requests) {
    $client = [Net.WebClient]::new()
    $client.Encoding = [Text.Encoding]::UTF8
    $clients += $client
    $tasks += $client.DownloadFileTaskAsync([Uri]::new($origin,$request.Url),(Join-Path $assetRoot $request.Name))
}
try {
    [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]$tasks)
    Get-ChildItem -LiteralPath $assetRoot | Select-Object Name,Length
} finally { foreach ($client in $clients) { $client.Dispose() } }
