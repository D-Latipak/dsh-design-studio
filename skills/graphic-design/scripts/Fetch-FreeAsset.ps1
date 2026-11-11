#requires -Version 5.1
<#
.SYNOPSIS
  平面设计工坊 · 免费素材抓取器（图片 / 图标 / 纹理 / 公共领域艺术品）

.DESCRIPTION
  从一个开放素材源按关键词检索，挑出**可商用的许可证**，下载到 designs/assets/，
  并同步维护两样东西：
    - manifest.json  每份素材的来源、作者、许可证、落地页、sha256、像素尺寸（给 agent 自己看的账本）
    - CREDITS.md     由 manifest 自动生成的署名页（CC BY / CC BY-SA 的合规底稿，交付时附上）

  许可策略（硬编码，改不了）：只放行 CC0 / 公有领域 / CC BY / CC BY-SA / MIT / ISC / Apache / OFL；
  遇到 NC（禁商用）、ND（禁演绎）、来源不明的一律跳过并打印原因。
  确实要用非放行素材时，显式加 -AllowAnyLicense，记录里会带 licenseRisk=true，交付时必须向用户说明。

.PARAMETER Source
  openverse | wikimedia | met | cleveland | polyhaven | iconify | url

.PARAMETER Query
  检索词。可用英文更稳（Flickr/Commons 的标签以英文为主），中文也可。

.PARAMETER Url
  -Source url 时直接给的直链（字体、已有直链的素材）。

.PARAMETER Limit
  最多下载几个（默认 3）。

.PARAMETER MinWidth
  最小像素宽（默认 1200）。小于它的跳过——印刷稿需要 300dpi，见 references/format-presets.md。
  对 iconify 而言是 SVG 的导出高度。

.PARAMETER Set
  -Source iconify 时的图标集前缀（默认 lucide，ISC 许可）。见 references/free-assets.md 的白名单。

.PARAMETER Role
  素材角色，写进 manifest：photo | icon | texture | artwork | font | graphic。默认按 Source 推断。

.PARAMETER License / Creator / LandingUrl
  -Source url 时必填（否则记录不合法）：你自己声明这份素材的许可证、作者、来源页。

.PARAMETER Dest
  落盘目录。默认 <工作区>/designs/assets；做单个项目时建议 designs/<slug>/assets。

.EXAMPLE
  .\Fetch-FreeAsset.ps1 -Source wikimedia -Query "Sichuan opera mask" -Limit 3 -MinWidth 1600

.EXAMPLE
  .\Fetch-FreeAsset.ps1 -Source openverse -Query "autumn maple leaves" -Dest "designs\shan-jian-ri-luo\assets"

.EXAMPLE
  .\Fetch-FreeAsset.ps1 -Source iconify -Query "coffee cup" -Set lucide -Limit 4 -MinWidth 512

.EXAMPLE
  .\Fetch-FreeAsset.ps1 -Source polyhaven -Query "wood floor" -Limit 2 -MinWidth 1024

.EXAMPLE
  # 字体 / 已知直链：必须自己声明许可
  .\Fetch-FreeAsset.ps1 -Source url -Url "https://raw.githubusercontent.com/google/fonts/main/ofl/notoserifsc/NotoSerifSC%5Bwght%5D.ttf" `
      -License OFL-1.1 -Creator "Google / Adobe" -LandingUrl "https://fonts.google.com/noto/specimen/Noto+Serif+SC" -Role font

.NOTES
  验证状态写在 references/free-assets.md「实测状态」列。改本脚本后请在真实网络下跑一遍再改状态。
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('openverse', 'wikimedia', 'met', 'cleveland', 'polyhaven', 'iconify', 'url')]
    [string]$Source,

    [string]$Query,
    [string]$Url,

    [int]$Limit = 3,
    [int]$MinWidth = 1200,
    [string]$Set = 'lucide',
    [string]$Role = '',

    [string]$License = '',
    [string]$Creator = '',
    [string]$LandingUrl = '',

    [string]$Root = '',
    [string]$Dest = '',
    [string]$UserAgent = 'DesignStudioAgent/1.0 (DSH graphic-design agent; free-asset fetch; contact: localuser@example.invalid)',

    [int]$TimeoutSec = 25,   # Openverse 匿名请求很慢，超时设小一点，让失败快速可见
    [switch]$AllowAnyLicense,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

# ---------- 路径与状态 ----------
if (-not $Root) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
}
if (-not $Dest) { $Dest = Join-Path $Root 'designs\assets' }
if (-not (Test-Path $Dest)) { New-Item -ItemType Directory -Force -Path $Dest | Out-Null }

$ManifestPath = Join-Path $Dest 'manifest.json'
$CreditsPath = Join-Path $Dest 'CREDITS.md'

if (-not $Role) {
    $Role = switch ($Source) {
        'iconify' { 'icon' }
        'polyhaven' { 'texture' }
        'met' { 'artwork' }
        'cleveland' { 'artwork' }
        default { 'photo' }
    }
}

if ($Source -eq 'url') {
    if (-not $Url) { throw '-Source url 需要 -Url' }
    if (-not $License) { throw '-Source url 需要 -License（例：OFL-1.1 / CC0 / CC BY 4.0）。记录不合法等于没账本。' }
    if (-not $LandingUrl) { $LandingUrl = $Url }
}
elseif (-not $Query) {
    throw "-Source $Source 需要 -Query"
}

$Slug = if ($Source -eq 'url') {
    [System.IO.Path]::GetFileNameWithoutExtension(([uri]$Url).AbsolutePath)
} else {
    $Query
}
$Slug = ($Slug -replace '[^\w\u4e00-\u9fa5\-]+', '-').Trim('-').ToLower()
if (-not $Slug) { $Slug = 'asset' }
if ($Slug.Length -gt 40) { $Slug = $Slug.Substring(0, 40) }

$Stats = [ordered]@{ source = $Source; query = $Query; candidates = 0; downloaded = 0; skipped = @(); files = @() }

# ---------- 小工具 ----------
function Invoke-Retry {
    param([scriptblock]$Action, [int]$Tries = 3)
    for ($i = 1; $i -le $Tries; $i++) {
        try { return (& $Action) }
        catch {
            $msg = $_.Exception.Message
            $isRate = $msg -match '429|Too many requests|操作超时|timed out'
            if ($i -eq $Tries) { throw }
            Start-Sleep -Seconds ([Math]::Min(10, $i * 3))
            if (-not $isRate) { throw }
        }
    }
}

function Get-Web {
    param([string]$Uri, [string]$OutFile)
    $p = @{
        Uri             = $Uri
        Headers         = @{ 'User-Agent' = $UserAgent; 'Accept' = '*/*' }
        TimeoutSec      = $TimeoutSec
        UseBasicParsing = $true
    }
    if ($OutFile) { $p.OutFile = $OutFile }
    Invoke-Retry { Invoke-WebRequest @p }
}

function Get-Json { param([string]$Uri) (Get-Web $Uri).Content | ConvertFrom-Json }

function Test-LicenseOk {
    param([string]$Name)
    if (-not $Name) { return $false }
    if ($Name -match '(?i)(?<![A-Za-z])(NC|ND)(?![A-Za-z])|non-?commercial|no-?deriv|非商业|禁止演绎|禁止商用') { return $false }
    return [bool]($Name -match '(?i)CC0|CC[\s-]?BY|Public\s*Domain|PDM|公有领域|Apache|MIT|ISC|OFL|Unlicense|WTFPL')
}

function Get-Hash { param([string]$Path) (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLower() }

function Get-ImageSize {
    param([string]$Path)
    $fs = [System.IO.File]::OpenRead($Path)
    try {
        $br = New-Object System.IO.BinaryReader($fs)
        $b = $br.ReadBytes(32)
        if ($b.Length -ge 24 -and $b[0] -eq 0x89 -and $b[1] -eq 0x50) {
            return @(([int]$b[16] -shl 24) -bor ([int]$b[17] -shl 16) -bor ([int]$b[18] -shl 8) -bor [int]$b[19],
                     ([int]$b[20] -shl 24) -bor ([int]$b[21] -shl 16) -bor ([int]$b[22] -shl 8) -bor [int]$b[23])
        }
        if ($b.Length -ge 4 -and $b[0] -eq 0xFF -and $b[1] -eq 0xD8) {
            $fs.Position = 2
            while ($fs.Position -lt ($fs.Length - 8)) {
                if ($br.ReadByte() -ne 0xFF) { continue }
                $m = $br.ReadByte()
                if ($m -eq 0xD8 -or $m -eq 0x01 -or ($m -ge 0xD0 -and $m -le 0xD7)) { continue }
                $len = ([int]$br.ReadByte() -shl 8) -bor [int]$br.ReadByte()
                if ($m -in 0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF) {
                    $null = $br.ReadByte()
                    $h = ([int]$br.ReadByte() -shl 8) -bor [int]$br.ReadByte()
                    $w = ([int]$br.ReadByte() -shl 8) -bor [int]$br.ReadByte()
                    return @($w, $h)
                }
                $fs.Position += ($len - 2)
            }
        }
        return @(0, 0)
    }
    finally { $fs.Dispose() }
}

function Get-ExtFromUrl {
    param([string]$Uri, [string]$ContentType)
    $path = ([uri]$Uri).AbsolutePath
    $ext = [System.IO.Path]::GetExtension($path).ToLower()
    if ($ext -in '.jpg', '.jpeg', '.png', '.svg', '.webp', '.gif', '.tif', '.tiff', '.ttf', '.otf', '.woff2', '.zip') { return $ext }
    if ($ContentType -match 'svg') { return '.svg' }
    if ($ContentType -match 'png') { return '.png' }
    if ($ContentType -match 'webp') { return '.webp' }
    return '.jpg'
}

# ConvertFrom-Json 把数组当成**一个**对象写进管道，@() 一包就成了嵌套数组（旧版这里写过 System.Object[]）。
# 逐条吐出来，让调用方的 @(Read-Manifest) 拿到扁平记录列表。
function Read-Manifest {
    if (-not (Test-Path $ManifestPath)) { return }
    $raw = Get-Content -Path $ManifestPath -Raw -Encoding UTF8
    if (-not $raw -or -not $raw.Trim()) { return }
    foreach ($record in ($raw | ConvertFrom-Json)) { $record }
}

# PS 5.1 的 ConvertTo-Json 对管道里的数组会各自序列化，容易写出 {value,Count} 的畸形 JSON；
# 这里逐条序列化再拼成合法数组，保证 manifest.json 永远是 [ {...}, {...} ]。
function Save-Manifest {
    param([object[]]$Items)
    $arr = @($Items)
    if ($arr.Count -eq 0) {
        Set-Content -Path $ManifestPath -Value '[]' -Encoding UTF8
        return
    }
    $parts = @()
    foreach ($it in $arr) {
        $parts += ((($it | ConvertTo-Json -Depth 8) -replace '\r?\n', ' ').Trim())
    }
    $json = "[`n  " + ($parts -join ",`n  ") + "`n]"
    Set-Content -Path $ManifestPath -Value $json -Encoding UTF8
}

function Update-Credits {
    $items = @(Read-Manifest)
    if ($items.Count -eq 0) { return }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('# 素材署名页（CREDITS）')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('本文件由 `skills/graphic-design/scripts/Fetch-FreeAsset.ps1` 从 `manifest.json` 自动生成，不要在 `manifest.json` 之外手改。')
    [void]$sb.AppendLine('')
    $need = @($items | Where-Object { $_.license -match '(?i)CC[\s-]?BY' })
    $free = @($items | Where-Object { $_.license -notmatch '(?i)CC[\s-]?BY' })
    [void]$sb.AppendLine('## 需要署名（CC BY / CC BY-SA）')
    [void]$sb.AppendLine('')
    if ($need.Count -eq 0) {
        [void]$sb.AppendLine('_无_')
    }
    else {
        [void]$sb.AppendLine('| 文件 | 标题 | 作者 | 许可证 | 来源页 |')
        [void]$sb.AppendLine('|---|---|---|---|---|')
        foreach ($a in $need) {
            [void]$sb.AppendLine(('| `{0}` | {1} | {2} | {3} | {4} |' -f (Split-Path $a.asset -Leaf), ($a.title -replace '\|', '/'), ($a.creator -replace '\|', '/'), $a.license, $a.landingUrl))
        }
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## 无需署名（CC0 / 公有领域 / 开放许可代码类）')
    [void]$sb.AppendLine('')
    if ($free.Count -eq 0) {
        [void]$sb.AppendLine('_无_')
    }
    else {
        [void]$sb.AppendLine('| 文件 | 标题 | 作者 | 许可证 | 来源页 |')
        [void]$sb.AppendLine('|---|---|---|---|---|')
        foreach ($a in $free) {
            [void]$sb.AppendLine(('| `{0}` | {1} | {2} | {3} | {4} |' -f (Split-Path $a.asset -Leaf), ($a.title -replace '\|', '/'), ($a.creator -replace '\|', '/'), $a.license, $a.landingUrl))
        }
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('`licenseRisk=true` 的条目表示许可不在放行名单内，交付前必须向用户说明风险。')
    Set-Content -Path $CreditsPath -Value $sb.ToString() -Encoding UTF8
}

function Save-Asset {
    param(
        [string]$DownloadUrl,
        [string]$Title,
        [string]$Author,
        [string]$AssetLicense,
        [string]$LicUrl,
        [string]$Page,
        [string]$Provider,
        [int]$Index
    )

    # URL 里可能带空格（博物馆 API 的原图直链常见），不转义会 404
    $DownloadUrl = ($DownloadUrl -replace ' ', '%20')
    $Page = ($Page -replace ' ', '%20')

    $licOk = Test-LicenseOk $AssetLicense
    if (-not $licOk -and -not $AllowAnyLicense) {
        $Stats.skipped += [pscustomobject]@{ title = $Title; license = $AssetLicense; reason = 'license-not-allowed' }
        Write-Warning ("跳过（许可不放行）：{0} — {1}" -f $Title, $AssetLicense)
        return $null
    }

    $probe = $null
    try { $probe = Get-Web -Uri $DownloadUrl } catch {
        $Stats.skipped += [pscustomobject]@{ title = $Title; license = $AssetLicense; reason = ('download-failed: ' + $_.Exception.Message) }
        Write-Warning ("下载失败：{0} — {1}" -f $Title, $_.Exception.Message)
        return $null
    }
    $ctype = $probe.Headers['Content-Type']
    if ($ctype -is [array]) { $ctype = $ctype[0] }
    $ext = Get-ExtFromUrl -Uri $DownloadUrl -ContentType ([string]$ctype)
    if ($ext -in '.tif', '.tiff', '.zip') {
        $Stats.skipped += [pscustomobject]@{ title = $Title; license = $AssetLicense; reason = ('format-unsupported: ' + $ext) }
        Write-Warning ("跳过（格式不适合直接排版）：{0} — {1}" -f $Title, $ext)
        return $null
    }

    $stamp = (Get-Date -Format 'HHmmss')
    $safeTitle = ($Title -replace '[^\w\u4e00-\u9fa5\-]+', '-').Trim('-').ToLower()
    if (-not $safeTitle) { $safeTitle = 'asset' }
    if ($safeTitle.Length -gt 32) { $safeTitle = $safeTitle.Substring(0, 32) }
    if ($safeTitle -eq $Slug) {
        $fileName = '{0}-{1}-{2}{3}' -f $Slug, $stamp, $Index, $ext
    }
    else {
        $fileName = '{0}-{1}-{2}-{3}{4}' -f $Slug, $safeTitle, $stamp, $Index, $ext
    }
    $target = Join-Path $Dest $fileName

    $raw = $probe.Content
    if ($raw -isnot [byte[]]) {
        if ($probe.RawContentStream) {
            $probe.RawContentStream.Position = 0
            $raw = $probe.RawContentStream.ToArray()
        }
        else {
            $raw = [System.Text.Encoding]::UTF8.GetBytes([string]$raw)
        }
    }
    [System.IO.File]::WriteAllBytes($target, [byte[]]$raw)

    $size = Get-ImageSize -Path $target
    $bytes = (Get-Item $target).Length

    if ($size[0] -gt 0 -and $size[0] -lt $MinWidth) {
        Remove-Item $target -Force
        $Stats.skipped += [pscustomobject]@{ title = $Title; license = $AssetLicense; reason = ("too-small: {0}x{1} < {2}px" -f $size[0], $size[1], $MinWidth) }
        Write-Warning ("跳过（太小）：{0} — {1}x{2}" -f $Title, $size[0], $size[1])
        return $null
    }

    $rec = [pscustomobject]@{
        asset       = $target
        file        = $fileName
        role        = $Role
        source      = $Source
        provider    = $Provider
        title       = $Title
        creator     = $Author
        license     = $AssetLicense
        licenseUrl  = $LicUrl
        landingUrl  = $Page
        downloadUrl = $DownloadUrl
        width       = $size[0]
        height      = $size[1]
        bytes       = $bytes
        sha256      = (Get-Hash $target)
        licenseRisk = (-not $licOk)
        fetchedAt   = (Get-Date).ToString('s')
    }

    if (-not $DryRun) {
        $items = @(Read-Manifest)
        $items += $rec
        Save-Manifest $items
        Update-Credits
    }

    $Stats.downloaded++
    $Stats.files += [pscustomobject]@{ file = $fileName; path = $target; width = $size[0]; height = $size[1]; license = $AssetLicense }
    Write-Host ("[ok] {0}  {1}x{2}  {3}  {4}" -f $fileName, $size[0], $size[1], $AssetLicense, $Title)
    return $rec
}

function Strip-Html { param([string]$s) if (-not $s) { return '' } ([System.Net.WebUtility]::HtmlDecode(($s -replace '<[^>]+>', ' ')) -replace '\s+', ' ').Trim() }

# ---------- 各源 ----------
$candidates = @()

switch ($Source) {

    'openverse' {
        # 匿名请求硬限额：page_size <= 20、翻页深度 <= 240；别贪。
        $u = 'https://api.openverse.org/v1/images/?q={0}&license=cc0,pdm,by,by-sa&extension=jpg,png&page_size={1}&mature=false' -f [uri]::EscapeDataString($Query), [Math]::Min(20, [Math]::Max($Limit * 3, 6))
        try { $j = Get-Json $u }
        catch {
            throw ('Openverse 检索失败（匿名限流很常见：突发约 20 次请求后要冷却约 5 分钟）。改用 -Source cleveland / wikimedia / met，或过几分钟再试。原始错误：' + $_.Exception.Message)
        }
        # provider=wikimedia 的 url 才是真原图；别的 provider 常把 960w 缩略图当 url 给。
        # 元数据尺寸会骗人（实测声称 6016x4016、实得 960x641），所以先排序、下载后再按实测像素筛。
        $results = @($j.results | Where-Object { $_.url } | Sort-Object { if ($_.source -eq 'wikimedia') { 0 } else { 1 } })
        $candidates = @($results | ForEach-Object {
                [pscustomobject]@{
                    url     = $_.url
                    title   = if ($_.title) { $_.title } else { 'untitled' }
                    author  = if ($_.creator) { $_.creator } else { 'unknown' }
                    license = ('CC ' + ($_.license -replace '^cc-', '').ToUpper() + ' ' + $_.license_version).Trim()
                    licUrl  = $_.license_url
                    page    = $_.foreign_landing_url
                    provider= $_.source
                }
            })
    }

    'wikimedia' {
        $params = @{
            action       = 'query'
            format       = 'json'
            generator    = 'search'
            gsrsearch    = "$Query filetype:bitmap"
            gsrnamespace = '6'
            gsrlimit     = [string]([Math]::Max($Limit * 3, 6))
            prop         = 'imageinfo'
            iiprop       = 'url|size|extmetadata'
            iiurlwidth   = '1920'   # 只认 20/40/60/120/250/330/500/960/1280/1920/3840 这些档位；随手写 1600/2400 会 400
        }
        $qs = ($params.GetEnumerator() | ForEach-Object { '{0}={1}' -f $_.Key, [uri]::EscapeDataString([string]$_.Value) }) -join '&'
        Start-Sleep -Milliseconds 600
        $j = Get-Json ('https://commons.wikimedia.org/w/api.php?' + $qs)
        $candidates = @($j.query.pages.PSObject.Properties | ForEach-Object {
                $pg = $_.Value
                $ii = $pg.imageinfo | Select-Object -First 1
                if (-not $ii) { return }
                [pscustomobject]@{
                    url      = ($ii.thumburl -split '\?')[0]
                    title    = (Strip-Html $pg.title) -replace '^File:', ''
                    author   = Strip-Html $ii.extmetadata.Artist.value
                    license  = Strip-Html $ii.extmetadata.LicenseShortName.value
                    licUrl   = Strip-Html $ii.extmetadata.LicenseUrl.value
                    page     = $ii.descriptionurl
                    provider = 'Wikimedia Commons'
                }
            })
    }

    'met' {
        Start-Sleep -Milliseconds 400
        # v1/search 已于 2026-10-01 退役（后端换成 Elastic，必须分页）：用 v1.1 + offset/limit
        $j = Get-Json ('https://collectionapi.metmuseum.org/public/collection/v1.1/search?hasImages=true&offset=0&limit={0}&q={1}' -f [Math]::Max($Limit * 25, 50), [uri]::EscapeDataString($Query))
        $ids = @($j.objectIDs | Select-Object -First 25)
        foreach ($id in $ids) {
            if ($candidates.Count -ge ($Limit * 2)) { break }
            try { $o = Get-Json ('https://collectionapi.metmuseum.org/public/collection/v1/objects/' + $id) } catch { continue }
            Start-Sleep -Milliseconds 300
            if (-not $o.primaryImage) { continue }
            if (-not $o.isPublicDomain) { continue }   # v1.1 检索结果里会混进非 PD 条目，必须逐条核
            $candidates += [pscustomobject]@{
                url      = $o.primaryImage
                title    = if ($o.title) { $o.title } else { "object $id" }
                author   = if ($o.artistDisplayName) { $o.artistDisplayName } else { 'unknown (Met Open Access)' }
                license  = if ($o.isPublicDomain) { 'CC0 (The Met Open Access)' } else { 'copyrighted (The Met)' }
                licUrl   = 'https://www.metmuseum.org/about-the-met/policies-and-documents/open-access'
                page     = $o.objectURL
                provider = 'The Met'
            }
        }
    }

    'cleveland' {
        # 一个 JSON 就给 web / print / full 三档图，最省请求的 CC0 艺术源；元数据尺寸与实际一致（实测）
        $j = Get-Json ('https://openaccess-api.clevelandart.org/api/artworks/?q={0}&cc0=1&has_image=1&limit={1}' -f [uri]::EscapeDataString($Query), [Math]::Max($Limit * 3, 6))
        $candidates = @($j.data | Where-Object { $_.images -and $_.images.print -and $_.images.print.url } | ForEach-Object {
                [pscustomobject]@{
                    url      = $_.images.print.url
                    title    = $_.title
                    author   = if ($_.creators) { ($_.creators | ForEach-Object { $_.description }) -join '; ' } else { 'unknown' }
                    license  = 'CC0 (Cleveland Museum of Art)'
                    licUrl   = 'https://www.clevelandart.org/open-access'
                    page     = ('https://www.clevelandart.org/art/' + $_.id)
                    provider = 'Cleveland Museum of Art'
                }
            })
    }

    'polyhaven' {
        $all = Get-Json 'https://api.polyhaven.com/assets?t=textures'
        $rx = [regex]::Escape(($Query -split '\s+')[0])
        $picks = @($all.PSObject.Properties | Where-Object { $_.Name -match $rx } | Select-Object -First ([Math]::Max($Limit * 2, 4)))
        foreach ($p in $picks) {
            try { $files = Get-Json ('https://api.polyhaven.com/files/' + $p.Name) } catch { continue }
            Start-Sleep -Milliseconds 300
            $map = $files.PSObject.Properties | Where-Object { $_.Name -match '(?i)diffuse|albedo|color' } | Select-Object -First 1
            if (-not $map) { continue }
            $res = $map.Value.PSObject.Properties | Where-Object { $_.Name -match '^(1k|2k)$' } | Select-Object -Last 1
            if (-not $res) { continue }
            $jpg = $res.Value.PSObject.Properties | Where-Object { $_.Name -eq 'jpg' } | Select-Object -First 1
            if (-not $jpg) { continue }
            $candidates += [pscustomobject]@{
                url      = $jpg.Value.url
                title    = ($p.Name -replace '_', ' ')
                author   = 'Poly Haven contributors'
                license  = 'CC0'
                licUrl   = 'https://polyhaven.com/license'
                page     = 'https://polyhaven.com/a/' + $p.Name
                provider = 'Poly Haven'
            }
        }
    }

    'iconify' {
        # 图标集许可按 prefix 变：GPL 的（wordpress/gridicons/dashicons/icomoon-free/et/gala）
        # 和 CC BY-NC 的（ps/cbi）一律不用。lucide 是 ISC；mdi/carbon/material-symbols 是 Apache-2.0，tabler/ph 是 MIT。
        $badSets = @('wordpress', 'gridicons', 'dashicons', 'icomoon-free', 'et', 'gala', 'ps', 'cbi')
        if ($badSets -contains $Set.ToLower()) {
            throw ('图标集 ' + $Set + ' 的许可证（GPL / CC BY-NC）不能用在商业稿里。换 lucide / mdi / tabler / ph / carbon / simple-icons。')
        }
        $s = Get-Json ('https://api.iconify.design/search?query={0}&limit={1}&prefix={2}' -f [uri]::EscapeDataString($Query), [Math]::Max($Limit * 3, 6), [uri]::EscapeDataString($Set))
        Start-Sleep -Milliseconds 300
        $meta = $null
        try { $meta = (Get-Json ('https://api.iconify.design/collections?prefix=' + [uri]::EscapeDataString($Set))) } catch { }
        $licTitle = if ($meta) { $meta.$Set.license.title } else { 'unknown' }
        $licUrl = if ($meta) { $meta.$Set.license.url } else { '' }
        $author = if ($meta) { $meta.$Set.author.name } else { 'unknown' }
        $candidates = @($s.icons | ForEach-Object {
                $parts = $_ -split ':', 2
                [pscustomobject]@{
                    url      = ('https://api.iconify.design/{0}/{1}.svg?height={2}&color=%23000000' -f $parts[0], $parts[1], [Math]::Max($MinWidth, 256))
                    title    = $parts[1]
                    author   = $author
                    license  = $licTitle
                    licUrl   = $licUrl
                    page     = ('https://icon-sets.iconify.design/{0}/{1}/' -f $parts[0], $parts[1])
                    provider = 'Iconify/' + $parts[0]
                }
            })
    }

    'url' {
        $candidates = @([pscustomobject]@{
                url      = $Url
                title    = [System.IO.Path]::GetFileNameWithoutExtension(([uri]$Url).AbsolutePath)
                author   = $Creator
                license  = $License
                licUrl   = ''
                page     = $LandingUrl
                provider = ([uri]$Url).Host
            })
    }
}

$Stats.candidates = @($candidates).Count

# ---------- 下载 ----------
$i = 0
foreach ($c in $candidates) {
    if ($Stats.downloaded -ge $Limit) { break }
    $i++
    Start-Sleep -Milliseconds 500
    $null = Save-Asset -DownloadUrl $c.url -Title $c.title -Author $c.author -AssetLicense $c.license `
        -LicUrl $c.licUrl -Page $c.page -Provider $c.provider -Index $i
}

# ---------- 汇总 ----------
Write-Host ''
Write-Host ("完成：候选 {0} 个，落盘 {1} 个，跳过 {2} 个 → {3}" -f $Stats.candidates, $Stats.downloaded, @($Stats.skipped).Count, $Dest)
if (@($Stats.skipped).Count -gt 0) {
    Write-Host '跳过的原因：'
    $Stats.skipped | Group-Object reason | ForEach-Object { Write-Host ("  {0} × {1}" -f $_.Count, $_.Name) }
}
if (Test-Path $CreditsPath) { Write-Host ("署名页：{0}" -f $CreditsPath) }
Write-Host ''
$Stats | ConvertTo-Json -Depth 6
