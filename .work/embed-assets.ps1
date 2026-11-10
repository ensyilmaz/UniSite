param(
    [Parameter(Mandatory=$true)][string]$InputPath,
    [string]$OutputPath,
    [switch]$FetchOnly,
    [string]$BaseUrl = 'https://dev.munitek.com/'
)

$ErrorActionPreference = 'Stop'
if (-not $FetchOnly -and -not $OutputPath) { throw 'OutputPath is required unless FetchOnly is selected.' }
$inputFile = [IO.Path]::GetFullPath($InputPath)
if (-not (Test-Path -LiteralPath $inputFile -PathType Leaf)) { throw "Input file was not found: $inputFile" }
$cacheRoot = Join-Path $PSScriptRoot 'asset-cache'
$null = New-Item -ItemType Directory -Path $cacheRoot -Force
$script:assetRecords = @{}
$script:dataUris = @{}
$script:cssStack = @{}
$script:styleCount = 0
$script:scriptCount = 0
$script:imageCount = 0
$script:cssResourceCount = 0
$script:fontCount = 0
$script:cssUrlPattern = 'url\(\s*(?:(?<quote>["''])(?<quoted>.*?)\k<quote>|(?<bare>[^)]*))\s*\)'
$script:regexOptions = [Text.RegularExpressions.RegexOptions]::Singleline -bor [Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [Text.RegularExpressions.RegexOptions]::CultureInvariant
$script:userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

function Get-Hash([string]$Value) {
    $hash = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value)))).Replace('-','').ToLowerInvariant() }
    finally { $hash.Dispose() }
}
function Guess-Mime([string]$Url) {
    $extension = [IO.Path]::GetExtension(([Uri]$Url).AbsolutePath).ToLowerInvariant()
    switch ($extension) {
        '.css' { return 'text/css' }
        '.js' { return 'text/javascript' }
        '.svg' { return 'image/svg+xml' }
        '.png' { return 'image/png' }
        '.jpg' { return 'image/jpeg' }
        '.jpeg' { return 'image/jpeg' }
        '.gif' { return 'image/gif' }
        '.webp' { return 'image/webp' }
        '.avif' { return 'image/avif' }
        '.ico' { return 'image/x-icon' }
        '.woff2' { return 'font/woff2' }
        '.woff' { return 'font/woff' }
        '.ttf' { return 'font/ttf' }
        '.otf' { return 'font/otf' }
        default { return 'application/octet-stream' }
    }
}
function Resolve-AssetUrl([string]$Value,[string]$ContextUrl) {
    $value = [Net.WebUtility]::HtmlDecode($Value.Trim())
    if (-not $value -or $value.StartsWith('#') -or $value -match '^(data|blob|about):') { return $null }
    $uri = [Uri]::new([Uri]$ContextUrl,$value)
    if ($uri.Scheme -notin @('http','https')) { throw "Unsupported asset URL: $value" }
    return $uri.AbsoluteUri
}
function Read-Asset([string]$Url) {
    $uri = [Uri]$Url
    $builder = [UriBuilder]::new($uri)
    $builder.Fragment = ''
    $requestUrl = $builder.Uri.AbsoluteUri
    if ($script:assetRecords.ContainsKey($requestUrl)) { return $script:assetRecords[$requestUrl] }
    $key = Get-Hash $requestUrl
    $binaryPath = Join-Path $cacheRoot ($key+'.bin')
    $metadataPath = Join-Path $cacheRoot ($key+'.json')
    $cached = (Test-Path -LiteralPath $binaryPath -PathType Leaf) -and (Test-Path -LiteralPath $metadataPath -PathType Leaf)
    if ($cached) {
        $metadata = [IO.File]::ReadAllText($metadataPath,[Text.Encoding]::UTF8) | ConvertFrom-Json
        if ($metadata.url -cne $requestUrl) { throw "Asset cache identity mismatch: $requestUrl" }
        $mime = [string]$metadata.mime
        $length = ([IO.FileInfo]$binaryPath).Length
        if ($length -ne [long]$metadata.bytes) { throw "Asset cache is incomplete: $requestUrl" }
    } else {
        $mime = Guess-Mime $requestUrl
        # Reuse the exact originals already downloaded during source comparison.
        $seedName = $null
        if ($uri.Host -eq 'dev.munitek.com' -and $uri.AbsolutePath -eq '/css/site.css') { $seedName = 'site.css' }
        if ($uri.Host -eq 'dev.munitek.com' -and $uri.AbsolutePath -eq '/js/site.js') { $seedName = 'site.js' }
        $seedPath = if ($seedName) { Join-Path (Join-Path $PSScriptRoot 'original-assets') $seedName } else { $null }
        if ($seedPath -and (Test-Path -LiteralPath $seedPath -PathType Leaf)) {
            $bytes = [IO.File]::ReadAllBytes($seedPath)
        } else {
            $request = [Net.HttpWebRequest]::Create($requestUrl)
            $request.UserAgent = $script:userAgent
            $request.Accept = '*/*'
            $request.Timeout = 45000
            $request.ReadWriteTimeout = 45000
            $request.AutomaticDecompression = [Net.DecompressionMethods]::GZip -bor [Net.DecompressionMethods]::Deflate
            $response = $null
            try {
                $response = $request.GetResponse()
                $responseMime = ([string]$response.ContentType -split ';')[0].Trim()
                if ($responseMime -and ($responseMime -notin @('application/octet-stream','binary/octet-stream','text/plain','text/xml','application/xml') -or $mime -eq 'application/octet-stream')) { $mime = $responseMime }
                $stream = $response.GetResponseStream()
                $buffer = [IO.MemoryStream]::new()
                try { $stream.CopyTo($buffer); $bytes = $buffer.ToArray() }
                finally { $buffer.Dispose(); $stream.Dispose() }
            } catch { throw "Failed to download original asset $requestUrl : $($_.Exception.Message)" }
            finally { if ($response) { $response.Dispose() } }
        }
        if ($bytes.Length -eq 0) { throw "Original asset is empty: $requestUrl" }
        if ($mime -match '^text/html' -and $uri.AbsolutePath -notmatch '\.html?$') { throw "Server returned HTML instead of an asset: $requestUrl" }
        [IO.File]::WriteAllBytes($binaryPath,$bytes)
        $length = $bytes.Length
        $metadata = [ordered]@{url=$requestUrl;mime=$mime;bytes=$length;sha256=(Get-FileHash -LiteralPath $binaryPath -Algorithm SHA256).Hash.ToLowerInvariant()}
        [IO.File]::WriteAllText($metadataPath,($metadata | ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
        Write-Output ("Cached {0} bytes: {1}" -f $length,$requestUrl) | Out-Host
    }
    $record = [pscustomobject]@{url=$requestUrl;mime=$mime;bytes=[long]$length;path=$binaryPath;cached=[bool]$cached}
    $script:assetRecords[$requestUrl] = $record
    return $record
}
function Asset-Text([string]$Url) {
    $record = Read-Asset $Url
    return [IO.File]::ReadAllText($record.path,[Text.Encoding]::UTF8).TrimStart([char]0xfeff)
}
function Asset-DataUri([string]$Url) {
    if ($script:dataUris.ContainsKey($Url)) { return $script:dataUris[$Url] }
    $record = Read-Asset $Url
    $data = 'data:'+$record.mime+';base64,'+[Convert]::ToBase64String([IO.File]::ReadAllBytes($record.path))
    $fragment = ([Uri]$Url).Fragment
    if ($fragment) { $data += $fragment }
    $script:dataUris[$Url] = $data
    return $data
}
function Embed-Css([string]$Css,[string]$ContextUrl) {
    $css = [regex]::Replace($Css,'@charset\s+["''][^"'']+["'']\s*;','',$script:regexOptions)
    $importPattern = '@import\s+(?:url\(\s*)?(?:"(?<dq>[^"\r\n]+)"|''(?<sq>[^''\r\n]+)''|(?<bare>[^\s;)]+))\s*\)?\s*(?<media>[^;]*);'
    $css = [regex]::Replace($css,$importPattern,{
        param($match)
        $value = $match.Groups['dq'].Value
        if (-not $value) { $value = $match.Groups['sq'].Value }
        if (-not $value) { $value = $match.Groups['bare'].Value }
        $url = Resolve-AssetUrl $value $ContextUrl
        if (-not $url) { return $match.Value }
        if ($script:cssStack.ContainsKey($url)) { throw "Circular CSS import: $url" }
        $script:cssStack[$url] = $true
        try { $imported = Embed-Css (Asset-Text $url) $url }
        finally { $script:cssStack.Remove($url) }
        $media = $match.Groups['media'].Value.Trim()
        if ($media) { return '@media '+$media+' {'+"`n"+$imported+"`n}" }
        return $imported
    },$script:regexOptions)
    $css = [regex]::Replace($css,$script:cssUrlPattern,{
        param($match)
        $value = if ($match.Groups['quote'].Success) { $match.Groups['quoted'].Value } else { $match.Groups['bare'].Value.Trim() }
        $url = Resolve-AssetUrl $value $ContextUrl
        if (-not $url) { return $match.Value }
        $script:cssResourceCount++
        return 'url("'+(Asset-DataUri $url)+'")'
    },$script:regexOptions)
    # Chromium can reject a var()-containing shorthand when its expanded value
    # also contains a multi-megabyte data URI. Keep the original process
    # background values while separating the small variable from the image.
    $processBackgroundPattern = '(?<prefix>\.process\s*\{[^}]*?)\bbackground\s*:\s*var\(--navy-deep\)\s+(?<image>url\("data:image/png;base64,[A-Za-z0-9+/=]+"\))\s+center\s*/\s*cover\s+no-repeat\s*;'
    $css = [regex]::Replace($css,$processBackgroundPattern,{
        param($match)
        return $match.Groups['prefix'].Value+'background-color: var(--navy-deep);'+"`n  "+'background-image: '+$match.Groups['image'].Value+';'+"`n  "+'background-position: center;'+"`n  "+'background-size: cover;'+"`n  "+'background-repeat: no-repeat;'
    },$script:regexOptions)
    return [regex]::Replace($css,'/\*[#@]\s*sourceMappingURL=.*?\*/','',$script:regexOptions)
}
function Attribute([string]$Tag,[string]$Name) {
    $match = [regex]::Match($Tag,'\b'+[regex]::Escape($Name)+'\s*=\s*(["''])(?<value>.*?)\1',$script:regexOptions)
    if ($match.Success) { return $match.Groups['value'].Value }
    return $null
}

$html = [IO.File]::ReadAllText($inputFile,[Text.Encoding]::UTF8)
# Process inline CSS before inserting large embedded stylesheets.
$html = [regex]::Replace($html,'<style\b(?<attrs>[^>]*)>(?<css>.*?)</style>',{
    param($match)
    return '<style'+$match.Groups['attrs'].Value+'>'+(Embed-Css $match.Groups['css'].Value $BaseUrl)+'</style>'
},$script:regexOptions)
$html = [regex]::Replace($html,'\bstyle\s*=\s*(?<quote>["''])(?<css>.*?)\k<quote>',{
    param($match)
    $css = Embed-Css $match.Groups['css'].Value $BaseUrl
    # data URIs contain no quote bytes; keep the original attribute delimiter.
    $quote = $match.Groups['quote'].Value
    if ($quote -eq '"') { $css = $css.Replace('url("data:','url(''data:').Replace('")',''')') }
    return 'style='+$quote+$css+$quote
},$script:regexOptions)
$html = [regex]::Replace($html,'<link\b[^>]*>',{
    param($match)
    $tag = $match.Value
    $rel = Attribute $tag 'rel'
    if ($rel -match '(^|\s)(preconnect|dns-prefetch)(\s|$)') { return '' }
    if ($rel -notmatch '(^|\s)stylesheet(\s|$)') { return $tag }
    $url = Resolve-AssetUrl (Attribute $tag 'href') $BaseUrl
    if (-not $url) { return $tag }
    $css = Embed-Css (Asset-Text $url) $url
    $css = [regex]::Replace($css,'</style','<\/style',[Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $script:styleCount++
    $media = Attribute $tag 'media'
    $mediaAttribute = if ($media) { ' media="'+[Net.WebUtility]::HtmlEncode($media)+'"' } else { '' }
    return '<style id="utx-embedded-css-'+$script:styleCount+'" data-utx-source="'+[Net.WebUtility]::HtmlEncode($url)+'"'+$mediaAttribute+'>'+"`n"+$css+"`n</style>"
},$script:regexOptions)
$html = [regex]::Replace($html,'<script\b(?<attrs>[^>]*)>(?<body>.*?)</script>',{
    param($match)
    $src = Attribute ('<script'+$match.Groups['attrs'].Value+'>') 'src'
    if (-not $src) { return $match.Value }
    $url = Resolve-AssetUrl $src $BaseUrl
    if (-not $url) { return $match.Value }
    $code = Asset-Text $url
    $code = [regex]::Replace($code,'(?m)^\s*//[#@]\s*sourceMappingURL=.*$','')
    $code = [regex]::Replace($code,'</script','<\/script',[Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $script:scriptCount++
    return '<script id="utx-embedded-js-'+$script:scriptCount+'" data-utx-source="'+[Net.WebUtility]::HtmlEncode($url)+'">'+"`n"+$code+"`n</script>"
},$script:regexOptions)
$html = [regex]::Replace($html,'<img\b[^>]*>',{
    param($match)
    $tag = $match.Value
    $src = Attribute $tag 'src'
    if (-not $src) { return $tag }
    $url = Resolve-AssetUrl $src $BaseUrl
    if (-not $url) { return $tag }
    $dataUri = Asset-DataUri $url
    $script:imageCount++
    return [regex]::Replace($tag,'\bsrc\s*=\s*(["'']).*?\1',('src="'+$dataUri+'"'),$script:regexOptions)
},$script:regexOptions)

# Perform the shorthand split on the finished document as well. Nested regex
# callbacks use PowerShell scopes; this final pass guarantees the emitted rule.
$html = [regex]::Replace($html,'background\s*:\s*var\(--navy-deep\)\s+(?<image>url\("data:image/png;base64,[A-Za-z0-9+/=]+"\))\s+center\s*/\s*cover\s+no-repeat\s*;',{
    param($match)
    return 'background-color: var(--navy-deep); background-image: '+$match.Groups['image'].Value+'; background-position: center; background-size: cover; background-repeat: no-repeat;'
},$script:regexOptions)
$externalDependencies = @()
foreach ($tagMatch in [regex]::Matches($html,'<(?:img|script|link|source|video|audio|iframe)\b[^>]*>',$script:regexOptions)) {
    $tag = $tagMatch.Value
    foreach ($attributeName in @('src','srcset','poster','href')) {
        $attributeValue = Attribute $tag $attributeName
        if ($attributeValue -match '^(https?:)?//' -or ($attributeName -eq 'srcset' -and $attributeValue -match 'https?://')) { $externalDependencies += $tag.Substring(0,[Math]::Min($tag.Length,300)) }
    }
}
foreach ($styleMatch in [regex]::Matches($html,'<style\b[^>]*>(?<css>.*?)</style>|\bstyle\s*=\s*(?<quote>["''])(?<inline>.*?)\k<quote>',$script:regexOptions)) {
    $css = $styleMatch.Groups['css'].Value+$styleMatch.Groups['inline'].Value
    foreach ($urlMatch in [regex]::Matches($css,$script:cssUrlPattern,$script:regexOptions)) {
        $value = if ($urlMatch.Groups['quote'].Success) { $urlMatch.Groups['quoted'].Value } else { $urlMatch.Groups['bare'].Value.Trim() }
        if ($value -notmatch '^(data:|#|$)') { $externalDependencies += $value }
    }
}
$externalDependencies = @($externalDependencies | Select-Object -Unique)
if ($externalDependencies.Count -gt 0) { throw ('Unembedded resource dependencies remain: '+($externalDependencies -join ', ')) }
$records = @($script:assetRecords.Values | Sort-Object url)
$downloadBytes = [long]0
foreach ($record in $records) { $downloadBytes += $record.bytes }
$fontRecords = @($records | Where-Object { $_.mime -match 'font|woff|truetype|opentype' -or $_.url -match '\.(woff2?|ttf|otf)(\?|$)' })
$outputFile = if ($OutputPath) { [IO.Path]::GetFullPath($OutputPath) } else { $null }
if (-not $FetchOnly) { [IO.File]::WriteAllText($outputFile,$html,[Text.UTF8Encoding]::new($false)) }
$report = [ordered]@{
    input=$inputFile;output=$outputFile;fetchOnly=[bool]$FetchOnly
    uniqueAssets=$records.Count;sourceAssetBytes=$downloadBytes;htmlBytes=[Text.Encoding]::UTF8.GetByteCount($html)
    stylesheets=$script:styleCount;scripts=$script:scriptCount;imageTags=$script:imageCount;cssResourceReferences=$script:cssResourceCount;fontFiles=$fontRecords.Count
    externalResourceDependencies=$externalDependencies
    assets=@($records | Select-Object url,mime,bytes,path,cached)
}
$reportPath = Join-Path $PSScriptRoot 'embedded-assets-report.json'
[IO.File]::WriteAllText($reportPath,($report | ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
Write-Output ("Embedded {0} unique original assets ({1:N2} MB); {2} stylesheet(s), {3} script(s), {4} image tag(s), {5} font file(s)." -f $records.Count,($downloadBytes/1MB),$script:styleCount,$script:scriptCount,$script:imageCount,$fontRecords.Count)
if ($FetchOnly) { Write-Output 'FetchOnly completed; the output HTML was not written.' }
else { Write-Output ("Output: {0} ({1:N2} MB)" -f $outputFile,([Text.Encoding]::UTF8.GetByteCount($html)/1MB)) }
Write-Output ('Manifest: '+$reportPath)
