param(
    [string]$Original = '.work/deneme.original.html',
    [string]$Updated = 'deneme.html'
)

$ErrorActionPreference = 'Stop'
$workspacePath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$originalPath = if ([IO.Path]::IsPathRooted($Original)) { $Original } else { Join-Path $workspacePath $Original }
$updatedPath = if ([IO.Path]::IsPathRooted($Updated)) { $Updated } else { Join-Path $workspacePath $Updated }
$script:checks = @()
$regexOptions = [Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [Text.RegularExpressions.RegexOptions]::Singleline

function Assert-Preserved {
    param([string]$Name, [bool]$Passed, $Details = $null)
    $script:checks += [pscustomobject]@{ name = $Name; passed = $Passed; details = $Details }
    $label = if ($Passed) { 'PASS' } else { 'FAIL' }
    Write-Output "$label $Name"
    if (-not $Passed -and $null -ne $Details) { Write-Output ($Details | ConvertTo-Json -Depth 12 -Compress) }
}

function Normalize-Newlines {
    param([string]$Text)
    return $Text.Replace("`r`n", "`n").Replace("`r", "`n")
}

function Normalize-OriginalAssetOrigin {
    param([string]$Text)
    $tagPattern = '<(?:link|script|img)\b[^>]*>'
    $attributePattern = '(?<prefix>\b(?:src|href)\s*=\s*["''])https://dev\.munitek\.com(?=/)'
    return [regex]::Replace($Text, $tagPattern, [Text.RegularExpressions.MatchEvaluator]{
        param($tagMatch)
        return [regex]::Replace($tagMatch.Value, $attributePattern, '${prefix}', $regexOptions)
    }, $regexOptions)
}

function Get-Attribute {
    param([string]$Tag, [string]$Name)
    $pattern = '\b' + [regex]::Escape($Name) + '\s*=\s*(?<quote>["''])(?<value>.*?)\k<quote>'
    $match = [regex]::Match($Tag, $pattern, $regexOptions)
    if ($match.Success) { return $match.Groups['value'].Value }
    return $null
}

function Get-OpeningTags {
    param([string]$Html, [string]$TagName)
    return @([regex]::Matches($Html, '<' + [regex]::Escape($TagName) + '\b[^>]*>', $regexOptions))
}

function Get-Element {
    param([string]$Html, [string]$TagName, [string]$Class = '', [string]$Id = '')
    foreach ($opening in (Get-OpeningTags $Html $TagName)) {
        if ($Class -and @((Get-Attribute $opening.Value 'class') -split '\s+') -notcontains $Class) { continue }
        if ($Id -and (Get-Attribute $opening.Value 'id') -ne $Id) { continue }
        $depth = 0
        $tokens = [regex]::Matches($Html.Substring($opening.Index), '</?' + [regex]::Escape($TagName) + '\b[^>]*>', $regexOptions)
        foreach ($token in $tokens) {
            if ($token.Value.StartsWith('</')) { $depth-- }
            elseif (-not $token.Value.EndsWith('/>')) { $depth++ }
            if ($depth -eq 0) { return $Html.Substring($opening.Index, $token.Index + $token.Length) }
        }
        throw "Unclosed $TagName element in source."
    }
    return $null
}

function Get-FirstTag {
    param([string]$Html, [string]$TagName)
    $match = [regex]::Match($Html, '<' + [regex]::Escape($TagName) + '\b[^>]*>', $regexOptions)
    if ($match.Success) { return $match.Value }
    return $null
}

function Test-SameArray {
    param([object[]]$Expected, [object[]]$Actual)
    return (($Expected | ConvertTo-Json -Compress) -ceq ($Actual | ConvertTo-Json -Compress))
}

function Get-StylesheetTags {
    param([string]$Html)
    return @((Get-OpeningTags $Html 'link') | Where-Object { (Get-Attribute $_.Value 'rel') -eq 'stylesheet' } | ForEach-Object { $_.Value })
}

function Split-CssSelectors {
    param([string]$Text)
    $start = 0
    $depth = 0
    for ($index = 0; $index -lt $Text.Length; $index++) {
        $character = $Text[$index]
        if ($character -eq '(' -or $character -eq '[') { $depth++ }
        elseif ($character -eq ')' -or $character -eq ']') { $depth-- }
        elseif ($character -eq ',' -and $depth -eq 0) {
            $Text.Substring($start, $index - $start).Trim()
            $start = $index + 1
        }
    }
    $Text.Substring($start).Trim()
}

function Find-UnscopedCss {
    param([string]$Css)
    $clean = [regex]::Replace($Css, '/\*.*?\*/', '', $regexOptions)
    $invalid = @()
    foreach ($rule in [regex]::Matches($clean, '(?<selector>[^{}]+)\{', $regexOptions)) {
        $selectorText = $rule.Groups['selector'].Value.Trim()
        if ($selectorText.StartsWith('@')) {
            if ($selectorText -notmatch '^@(media|supports|container)\b') { $invalid += $selectorText }
            continue
        }
        foreach ($selector in (Split-CssSelectors $selectorText)) {
            $hasScope = $selector -match '(?<![\w-])[.#]utx-[\w-]+'
            $targetsDocument = $selector -match '(^|[\s>+~,(])(html|body|:root)(?=$|[\s>+~.#:\[,])'
            if (-not $hasScope -or $targetsDocument) { $invalid += $selector }
        }
    }
    return $invalid
}

if (-not (Test-Path -LiteralPath $originalPath)) { throw "Original attachment is missing: $originalPath" }
if (-not (Test-Path -LiteralPath $updatedPath)) { throw "Updated HTML is missing: $updatedPath" }
$sourceHtml = [IO.File]::ReadAllText($originalPath, [Text.Encoding]::UTF8)
$updatedHtml = [IO.File]::ReadAllText($updatedPath, [Text.Encoding]::UTF8)
$sourceHtml = Normalize-OriginalAssetOrigin (Normalize-Newlines $sourceHtml)
$updatedHtml = Normalize-OriginalAssetOrigin (Normalize-Newlines $updatedHtml)

$sourceHash = (Get-FileHash -LiteralPath $originalPath -Algorithm SHA256).Hash
Assert-Preserved 'Comparison uses the unchanged original attachment' ($sourceHash -eq '2E244BAC19B7639F9E08BFF1CC0466074AA0187523E680EB60C68F2A877C5564') $sourceHash

$sourceStyles = @(Get-StylesheetTags $sourceHtml)
$updatedStyles = @(Get-StylesheetTags $updatedHtml)
$sourceStyleHrefs = @($sourceStyles | ForEach-Object { Get-Attribute $_ 'href' })
$retainedStyles = @($updatedStyles | Where-Object { $sourceStyleHrefs -contains (Get-Attribute $_ 'href') })
Assert-Preserved 'Original stylesheet tags, URLs and order are unchanged' (Test-SameArray $sourceStyles $retainedStyles) @{ expected = $sourceStyles; actual = $retainedStyles }

$sourceScripts = @((Get-OpeningTags $sourceHtml 'script') | Where-Object { Get-Attribute $_.Value 'src' } | ForEach-Object { Get-Attribute $_.Value 'src' })
$updatedScripts = @((Get-OpeningTags $updatedHtml 'script') | Where-Object { Get-Attribute $_.Value 'src' } | ForEach-Object { Get-Attribute $_.Value 'src' })
Assert-Preserved 'All three original script URLs retain their order' (Test-SameArray $sourceScripts $updatedScripts) @{ expected = $sourceScripts; actual = $updatedScripts }

$sourceHead = Get-Element $sourceHtml 'head'
$updatedHead = Get-Element $updatedHtml 'head'
$headWithoutExtensions = [regex]::Replace($updatedHead, '<(style|script)\b[^>]*>.*?</\1>', '', $regexOptions)
$sourceHeadComparable = [regex]::Replace($sourceHead, '>\s+<', '><')
$updatedHeadComparable = [regex]::Replace($headWithoutExtensions, '>\s+<', '><')
Assert-Preserved 'Original head metadata and asset declarations are preserved' ($sourceHeadComparable -ceq $updatedHeadComparable)

$sourceImages = @((Get-OpeningTags $sourceHtml 'img') | ForEach-Object { $_.Value })
$sourceImageUrls = @($sourceImages | ForEach-Object { Get-Attribute $_ 'src' })
$retainedImages = @((Get-OpeningTags $updatedHtml 'img') | Where-Object { $sourceImageUrls -contains (Get-Attribute $_.Value 'src') } | ForEach-Object { $_.Value })
Assert-Preserved 'Every original image tag and src remains intact in order' (Test-SameArray $sourceImages $retainedImages) @{ expected = $sourceImages; actual = $retainedImages }

foreach ($tagName in @('html', 'body', 'main', 'header', 'footer')) {
    $sourceOpening = Get-FirstTag $sourceHtml $tagName
    $updatedOpening = Get-FirstTag $updatedHtml $tagName
    Assert-Preserved "Original $tagName opening tag is unchanged" ($sourceOpening -and $sourceOpening -ceq $updatedOpening) @{ expected = $sourceOpening; actual = $updatedOpening }
}

$sourceHeader = Get-Element $sourceHtml 'header'
$updatedHeader = Get-Element $updatedHtml 'header'
$sourceFooter = Get-Element $sourceHtml 'footer'
$updatedFooter = Get-Element $updatedHtml 'footer'
foreach ($area in @('header', 'footer')) {
    $sourceArea = if ($area -eq 'header') { $sourceHeader } else { $sourceFooter }
    $updatedArea = if ($area -eq 'header') { $updatedHeader } else { $updatedFooter }
    $sourceBrand = Get-Element $sourceArea 'a' 'brand'
    $updatedBrand = Get-Element $updatedArea 'a' 'brand'
    Assert-Preserved "Original $area brand markup is unchanged" ($sourceBrand -and $sourceBrand -ceq $updatedBrand)
}
$sourceActions = Get-Element $sourceHeader 'div' 'header-actions'
$updatedActions = Get-Element $updatedHeader 'div' 'header-actions'
Assert-Preserved 'Original search and mobile header action markup is unchanged' ($sourceActions -and $sourceActions -ceq $updatedActions)
$sourceFooterNav = Get-Element $sourceFooter 'nav' 'footer-nav'
$updatedFooterNav = Get-Element $updatedFooter 'nav' 'footer-nav'
Assert-Preserved 'Original footer primary navigation is unchanged' ($sourceFooterNav -and $sourceFooterNav -ceq $updatedFooterNav)
$sourceCopyright = Get-Element $sourceFooter 'div' 'footer-copy'
$updatedCopyright = Get-Element $updatedFooter 'div' 'footer-copy'
Assert-Preserved 'Original footer copyright markup is unchanged' ($sourceCopyright -and $sourceCopyright -ceq $updatedCopyright)

$sourceHero = Get-Element $sourceHtml 'section' 'hero'
$updatedHero = Get-Element $updatedHtml 'section' 'hero'
$contactMarker = '<!--\s*UTX HERO CONTACT START\s*-->.*?<!--\s*UTX HERO CONTACT END\s*-->'
$heroWithoutContact = [regex]::Replace($updatedHero, $contactMarker, '', $regexOptions)
$contactInsertions = [regex]::Matches($updatedHero, $contactMarker, $regexOptions).Count
if ($contactInsertions -eq 0) {
    $heroContact = Get-Element $updatedHero 'a' 'utx-hero-contact'
    if ($heroContact) { $heroWithoutContact = $updatedHero.Replace($heroContact, ''); $contactInsertions = 1 }
}
$sourceHeroComparable = [regex]::Replace($sourceHero, '>\s+<', '><')
$updatedHeroComparable = [regex]::Replace($heroWithoutContact, '>\s+<', '><')
Assert-Preserved 'Hero is unchanged apart from one marked contact CTA' ($contactInsertions -eq 1 -and $sourceHeroComparable -ceq $updatedHeroComparable) @{ contactInsertions = $contactInsertions }

foreach ($sectionClass in @('process', 'partners', 'showcase', 'cta')) {
    $sourceSection = Get-Element $sourceHtml 'section' $sectionClass
    $updatedSection = Get-Element $updatedHtml 'section' $sectionClass
    Assert-Preserved "Original $sectionClass section is exactly preserved" ($sourceSection -and $sourceSection -ceq $updatedSection)
}
$originalSectionClasses = @('hero', 'process', 'partners', 'solutions', 'showcase', 'cta')
$updatedOriginalSectionOrder = @((Get-OpeningTags $updatedHtml 'section') | ForEach-Object {
    $classes = @((Get-Attribute $_.Value 'class') -split '\s+')
    foreach ($sectionClass in $originalSectionClasses) { if ($classes -contains $sectionClass) { $sectionClass } }
})
Assert-Preserved 'Original homepage sections remain once each in their original order' (Test-SameArray $originalSectionClasses $updatedOriginalSectionOrder) $updatedOriginalSectionOrder

$sourceSolutions = Get-Element $sourceHtml 'section' 'solutions'
$updatedSolutions = Get-Element $updatedHtml 'section' 'solutions'
$sourceSolutionOpening = Get-FirstTag $sourceSolutions 'section'
$updatedSolutionOpening = Get-FirstTag $updatedSolutions 'section'
Assert-Preserved 'Existing solutions section opening is retained' ($sourceSolutionOpening -and $sourceSolutionOpening -ceq $updatedSolutionOpening)

$forbiddenMarkers = @('ut-fallback', 'ut-brand-fallback', 'originalCss', 'uniturk-styles', 'page-home', 'ut-service-data')
$foundForbidden = @($forbiddenMarkers | Where-Object { $updatedHtml.Contains($_) })
Assert-Preserved 'Previous global fallback and replacement app are absent' ($foundForbidden.Count -eq 0) $foundForbidden

$extraStyleLinks = @($updatedStyles | Where-Object { $sourceStyleHrefs -notcontains (Get-Attribute $_ 'href') })
Assert-Preserved 'Single HTML adds no external stylesheet dependency' ($extraStyleLinks.Count -eq 0) $extraStyleLinks
$inlineStyles = @([regex]::Matches($updatedHtml, '<style\b(?<attributes>[^>]*)>(?<content>.*?)</style>', $regexOptions))
$invalidStyleIds = @($inlineStyles | Where-Object { (Get-Attribute $_.Value 'id') -notmatch '^utx-' } | ForEach-Object { $_.Groups['attributes'].Value.Trim() })
Assert-Preserved 'Added inline styles identify their isolated utx scope' ($inlineStyles.Count -gt 0 -and $invalidStyleIds.Count -eq 0) $invalidStyleIds
$unscopedSelectors = @($inlineStyles | ForEach-Object { Find-UnscopedCss $_.Groups['content'].Value })
Assert-Preserved 'Added CSS selectors are scoped to utx components' ($unscopedSelectors.Count -eq 0) $unscopedSelectors

$inlineScripts = @([regex]::Matches($updatedHtml, '<script\b(?<attributes>[^>]*)>(?<content>.*?)</script>', $regexOptions) | Where-Object { -not (Get-Attribute $_.Value 'src') })
$invalidScriptIds = @($inlineScripts | Where-Object { (Get-Attribute $_.Value 'id') -notmatch '^utx-' } | ForEach-Object { $_.Groups['attributes'].Value.Trim() })
Assert-Preserved 'Added inline scripts identify the utx extension' ($inlineScripts.Count -gt 0 -and $invalidScriptIds.Count -eq 0) $invalidScriptIds
$legacyInterference = @($inlineScripts | Where-Object { $_.Groups['content'].Value -match '(heroPrev|heroNext|heroProgress|projectsTrack|projectsNext|searchToggle|navToggle)' } | ForEach-Object { Get-Attribute $_.Value 'id' })
Assert-Preserved 'Extension does not replace existing slider, search or mobile handlers' ($legacyInterference.Count -eq 0) $legacyInterference

$footerAnchorTags = @((Get-OpeningTags $updatedFooter 'a') | ForEach-Object { $_.Value })
$footerUrls = @($footerAnchorTags | ForEach-Object { Get-Attribute $_ 'href' })
$updatedHeaderNav = Get-Element $updatedHeader 'nav' 'main-nav'
$headerNavUrls = @((Get-OpeningTags $updatedHeaderNav 'a') | ForEach-Object { Get-Attribute $_.Value 'href' })
Assert-Preserved 'Corporate navigation excludes old why and documents pages' ($headerNavUrls -notcontains '/kurumsal/neden-uniturk' -and $headerNavUrls -notcontains '/kurumsal/belgelerimiz')
Assert-Preserved 'Old corporate why-page link is removed from footer' ($footerUrls -notcontains '/kurumsal/neden-uniturk')
Assert-Preserved 'Documents retains its original backend URL exactly once in footer' (@($footerUrls | Where-Object { $_ -eq '/kurumsal/belgelerimiz' }).Count -eq 1)
$legalArea = Get-Element $updatedFooter 'div' 'utx-legal-bar'
if (-not $legalArea) {
    foreach ($opening in (Get-OpeningTags $updatedFooter 'div')) {
        $classValue = Get-Attribute $opening.Value 'class'
        if ($classValue -and $classValue -match 'utx-legal') { $legalArea = Get-Element $updatedFooter 'div' ($classValue -split '\s+' | Where-Object { $_ -like 'utx-legal*' } | Select-Object -First 1); break }
    }
}
Assert-Preserved 'Documents link appears in added legal footer area' ($legalArea -and $legalArea.Contains('/kurumsal/belgelerimiz'))

$report = [ordered]@{
    original = $originalPath
    updated = $updatedPath
    originalSha256 = $sourceHash
    checks = $script:checks
    passed = @($script:checks | Where-Object passed).Count
    failed = @($script:checks | Where-Object { -not $_.passed }).Count
    verificationLimit = 'Static source preservation only. The sole normalized URL change is qualification of original link/script/img assets with https://dev.munitek.com. Browser verification is recorded separately.'
}
$reportPath = Join-Path $workspacePath '.work/preservation-report.json'
$report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $reportPath -Encoding UTF8
Write-Output ("Completed: {0} passed, {1} failed" -f $report.passed, $report.failed)
Write-Output $report.verificationLimit
if ($report.failed -gt 0) { exit 1 }
