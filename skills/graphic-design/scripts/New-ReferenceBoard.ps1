<#
.SYNOPSIS
  抓一张「参考板」：从全球互联网抓研究图（内置四站 + -Url 任意页面/图片直链），下载、记账、拼版。

.DESCRIPTION
  用于设计前的风格研究（不是素材获取）。来源不限，脚本内置四站只是方便，不是白名单；
  任何网站都能用 -Url 喂进来。默认开 Are.na + Design Reviewed，其余用 -Sources 显式开启：

    1. Are.na              —— 设计师/艺术家的公开收藏（当代平面、版式、字体、海报）
    2. Fonts In Use        —— 真实项目的字体使用档案（排版/字体搭配）
    3. Design Reviewed     —— 平面设计史档案（海报、封面、广告，高清原图）
    4. It's Nice That      —— 当代设计媒体（编辑设计、插画、品牌）
    5. -Url 任意页面/直链  —— 用 web_search 找到的任何页面（Behance/Dribbble/站酷/Pinterest/品牌站/档案馆…），
                              自动抽 og:image；带图片扩展名的 URL 直接当图片下载
    6. AIC / Met / Cleveland / Commons / Openverse —— 公共馆藏（默认关闭，但**来源不限**，馆藏也能过审）

  馆藏关键词检索很松（搜 "constructivist poster" 会返回一战美军海报），所以馆藏来源
  必须通过「内容词命中」过滤：查询里的风格/年代/媒介词必须真的出现在标题、分类、
  材质或风格字段里，否则丢弃并给出警告——宁可没有，也不要错的参考。

  下载后统一过质量门槛（默认宽 ≥ 1200px、> 20KB），达不到的不进板子。
  输出 designs\references\<slug>\：img\、refs.json、REFS.md、board.png。

  参考图只做研究，不得置入成品；要进版面请改用 Fetch-FreeAsset.ps1 走素材流程。
  但参考板本身必须跑参考关：逐张精读 + 交付用户过审（refs-approved.md），见
  references/reference-gate.md。

.PARAMETER Query
  一个或多个检索词。风格/年代/媒介词的英文检索效果最好
  （如 "swiss style poster"、"soviet constructivist poster"、"risograph poster"）。

.PARAMETER Url
  一个或多个页面/图片地址（通常来自 web_search 命中的专业设计站页面），
  脚本会抽取页面里的 og:image / twitter:image 主图。

.PARAMETER UrlMeta
  可选：一个 JSON 文件路径，用来给 -Url 里的图片直链补标题与出处。格式：
  [{"imageUrl":"https://…","title":"…","pageUrl":"https://…","creator":"Behance","source":"Web · behance.net"}]
  只影响元数据（标题/来源/页面链接），不改变下载与质量门槛。

.PARAMETER Slug
  参考板目录名（英文/数字/短横线）。缺省从第一个 Query 生成。

.PARAMETER Workspace
  工作区根目录，输出落在 <Workspace>\designs\references\<slug>。默认当前目录。

.PARAMETER Dest
  直接指定输出目录（优先于 Workspace/Slug）。

.PARAMETER Limit
  每个来源、每个检索词最多取几张，默认 4；总数建议 ≤ 16。

.PARAMETER Max
  整张板子最多收几张，默认 16。

.PARAMETER Sources
  来源子集：arena / fontsinuse / designreviewed / itsnicethat / url / aic / met /
  cleveland / commons / openverse。默认 arena|designreviewed；其余需显式指定。
  来源不限——这只是"用脚本内置哪几个站"，任何其他网站走 -Url。
  排序即优先级：前面的先占名额。

.PARAMETER MinWidth
  最小图片宽度（像素），低于此值丢弃，默认 1200。参考图看不清字距/网格就没有研究价值。

.PARAMETER MinHeight
  最小图片高度（像素），默认 0。

.PARAMETER Cols
  拼版列数，默认 4。

.PARAMETER NoSheet
  只下载与记账，不拼版。

.PARAMETER Clean
  清空目标目录里上一次的 img / refs.json / REFS.md / board.png 再重建（换关键词重抓时用，避免旧图残留）。

.PARAMETER AllowSmall
  放宽质量门槛（允许小于 MinWidth 的图），只在确实没有大图时使用，并在交付说明里注明。

.EXAMPLE
  # 首选：专业设计站
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File New-ReferenceBoard.ps1 `
    -Query "soviet constructivist poster" -Slug constructivist-ref

.EXAMPLE
  # 把 web_search 找到的专业页面一并喂进来
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File New-ReferenceBoard.ps1 `
    -Query "art deco poster" `
    -Url "https://www.behance.net/gallery/xxx","https://fontsinuse.com/uses/59656/xxx" `
    -Slug artdeco-ref

.NOTES
  需要联网。脚本文件必须保存为 UTF-8 with BOM。
#>
[CmdletBinding()]
param(
    [string[]]$Query = @(),
    [string[]]$Url = @(),
    [string]$UrlMeta = '',
    [string]$Slug = '',
    [string]$Workspace = (Get-Location).Path,
    [string]$Dest = '',
    [int]$Limit = 4,
    [int]$Max = 16,
    [string[]]$Sources = @('arena', 'designreviewed'),
    [int]$MinWidth = 1200,
    [int]$MinHeight = 0,
    [int]$Cols = 4,
    [switch]$NoSheet,
    [switch]$AllowSmall,
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$script:Warnings = New-Object System.Collections.Generic.List[string]

function Add-Warning([string]$message) {
    $script:Warnings.Add($message) | Out-Null
    Write-Warning $message
}

# 允许从 powershell.exe -File 传参时用 ; 或 | 分隔多值（-File 不支持数组字面量）
function Expand-ListArg([string[]]$values) {
    $out = @()
    foreach ($v in @($values)) {
        if ($null -eq $v) { continue }
        foreach ($part in ($v -split '[;|\r\n]+')) {
            $t = $part.Trim()
            if ($t) { $out += $t }
        }
    }
    return $out
}

$Query = @(Expand-ListArg $Query)
$Url = @(Expand-ListArg $Url)
if ($Query.Count -eq 0 -and $Url.Count -eq 0) { throw 'Query 和 Url 至少要给一个。' }

$validSources = @('arena', 'fontsinuse', 'designreviewed', 'itsnicethat', 'url', 'aic', 'met', 'cleveland', 'commons', 'openverse')
$Sources = @(Expand-ListArg $Sources)
if ($Sources.Count -eq 0) { $Sources = @('arena', 'designreviewed') }
$bad = @($Sources | Where-Object { $_ -notin $validSources })
if ($bad.Count -gt 0) { throw ("Sources 含未知来源：{0}。可用：{1}" -f ($bad -join ', '), ($validSources -join ', ')) }

$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 Safari/537.36'
$AicUA = 'DesignStudioReference/2.0 (design research; local agent)'

function Invoke-Http {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [string]$OutFile = '',
        [string]$Accept = '*/*',
        [string]$Referer = '',
        [int]$TimeoutSec = 30,
        [int]$Retries = 3
    )
    $headers = @{ 'User-Agent' = $UA; 'Accept' = $Accept }
    if ($Referer) { $headers['Referer'] = $Referer }
    if ($Uri -match 'artic\.edu') { $headers['AIC-User-Agent'] = $AicUA }
    $lastError = $null
    for ($attempt = 1; $attempt -le $Retries; $attempt++) {
        try {
            if ($OutFile) {
                Invoke-WebRequest -Uri $Uri -Headers $headers -TimeoutSec $TimeoutSec -UseBasicParsing -OutFile $OutFile | Out-Null
                return $null
            }
            return Invoke-WebRequest -Uri $Uri -Headers $headers -TimeoutSec $TimeoutSec -UseBasicParsing
        } catch {
            $lastError = $_
            if ($attempt -lt $Retries) {
                # 403/429 常见于站点限流，退避后再试
                $wait = 400 * $attempt
                if ($_.Exception.Message -match '\(403\)|\(429\)') { $wait = 1400 * $attempt }
                Start-Sleep -Milliseconds $wait
            }
        }
    }
    throw $lastError
}

function Get-JsonDoc([string]$Uri, [string]$Referer = '', [int]$TimeoutSec = 30) {
    $response = Invoke-Http -Uri $Uri -Accept 'application/json' -Referer $Referer -TimeoutSec $TimeoutSec
    return ($response.Content | ConvertFrom-Json)
}

function Get-HtmlDoc([string]$Uri, [string]$Referer = '', [int]$TimeoutSec = 30) {
    $response = Invoke-Http -Uri $Uri -Accept 'text/html,application/xhtml+xml' -Referer $Referer -TimeoutSec $TimeoutSec
    return [string]$response.Content
}

function Get-ExtFromUrl([string]$url) {
    try {
        $path = ([Uri]$url).AbsolutePath
        $ext = [System.IO.Path]::GetExtension($path).ToLowerInvariant()
    } catch { return '.jpg' }
    if ($ext -in @('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.tif', '.tiff')) { return $ext }
    return '.jpg'
}

function Get-ImageSize([string]$path) {
    Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
    try {
        $img = [System.Drawing.Image]::FromFile($path)
        try { return @{ Width = $img.Width; Height = $img.Height } } finally { $img.Dispose() }
    } catch { return @{ Width = 0; Height = 0 } }
}

function Get-Sha256([string]$path) {
    return (Get-FileHash -Path $path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Convert-WebpToJpeg([string]$path) {
    # GDI+ 不认 WebP；Windows 的 WIC（PresentationCore）通常能解，落成 JPEG 后用 GDI+ 统一处理
    $tmpPath = $path + '.tmp.jpg'
    try {
        Add-Type -AssemblyName PresentationCore -ErrorAction Stop
        $src = [System.IO.File]::OpenRead($path)
        try {
            $decoder = [System.Windows.Media.Imaging.BitmapDecoder]::Create(
                $src,
                [System.Windows.Media.Imaging.BitmapCreateOptions]::None,
                [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
            $frame = $decoder.Frames[0]
            if (-not $frame -or $frame.PixelWidth -lt 1) { return $false }
            $encoder = New-Object System.Windows.Media.Imaging.JpegBitmapEncoder
            $encoder.QualityLevel = 92
            $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($frame))
            $out = [System.IO.File]::Create($tmpPath)
            try { $encoder.Save($out) } finally { $out.Close() }
        } finally { $src.Close() }
        Move-Item -LiteralPath $tmpPath -Destination $path -Force
        return $true
    } catch {
        if (Test-Path -LiteralPath $tmpPath) { Remove-Item -LiteralPath $tmpPath -Force -ErrorAction SilentlyContinue }
        return $false
    }
}

function Get-ImageKind([string]$path) {
    try {
        $fs = [System.IO.File]::OpenRead($path)
        $buf = New-Object byte[] 12
        $n = $fs.Read($buf, 0, 12)
        $fs.Close()
        if ($n -lt 4) { return 'unknown' }
        if ($buf[0] -eq 0xFF -and $buf[1] -eq 0xD8 -and $buf[2] -eq 0xFF) { return 'jpg' }
        if ($buf[0] -eq 0x89 -and $buf[1] -eq 0x50 -and $buf[2] -eq 0x4E -and $buf[3] -eq 0x47) { return 'png' }
        if ($buf[0] -eq 0x47 -and $buf[1] -eq 0x49 -and $buf[2] -eq 0x46) { return 'gif' }
        if ($buf[0] -eq 0x52 -and $buf[1] -eq 0x49 -and $buf[2] -eq 0x46 -and $buf[3] -eq 0x46 -and
            $buf[8] -eq 0x57 -and $buf[9] -eq 0x45 -and $buf[10] -eq 0x42 -and $buf[11] -eq 0x50) { return 'webp' }
        if ($buf[0] -eq 0x42 -and $buf[1] -eq 0x4D) { return 'bmp' }
        return 'unknown'
    } catch { return 'unknown' }
}

function Clean-Text([string]$value) {
    if ($null -eq $value) { return '' }
    return (($value -replace '\s+', ' ').Trim())
}

function Convert-HtmlText([string]$value) {
    if ($null -eq $value) { return '' }
    $text = [regex]::Replace([string]$value, '<[^>]+>', ' ')
    $text = [System.Net.WebUtility]::HtmlDecode($text)
    return (Clean-Text $text)
}

function Get-FallbackImage([string]$html, [string]$baseUrl) {
    # 没有 og:image 的站点（社媒、作品集、品牌站、论坛）：退而取页面里最靠前的一张真图
    $candidates = @()
    foreach ($m in [regex]::Matches($html, '<img[^>]+>')) {
        $tag = $m.Value
        $src = ''
        foreach ($attr in @('src', 'data-src', 'data-original', 'data-lazy-src')) {
            $a = [regex]::Match($tag, ('{0}="([^"]+)"' -f $attr))
            if ($a.Success -and $a.Groups[1].Value -and $a.Groups[1].Value -notmatch '^data:') { $src = $a.Groups[1].Value; break }
        }
        if (-not $src) {
            $ss = [regex]::Match($tag, 'srcset="([^"]+)"')
            if ($ss.Success) { $src = (($ss.Groups[1].Value -split ',')[0].Trim() -split ' ')[0] }
        }
        if (-not $src) { continue }
        $w = 0
        $wm = [regex]::Match($tag, 'width="(\d+)"')
        if ($wm.Success) { $w = [int]$wm.Groups[1].Value }
        if ($src -match '\.svg(\?.*)?$') { continue }
        if ($src -match '(?i)logo|icon|avatar|sprite|pixel|1x1') { continue }
        try { $abs = ([Uri]::new([Uri]$baseUrl, $src)).AbsoluteUri } catch { continue }
        $candidates += [pscustomobject]@{ url = $abs; weight = $w }
    }
    if ($candidates.Count -eq 0) { return '' }
    # 有 width 属性的按宽度取最大；没有就按页面顺序取第一张
    $scored = @($candidates | Where-Object { $_.weight -gt 0 } | Sort-Object -Property weight -Descending)
    if ($scored.Count -gt 0) { return $scored[0].url }
    return $candidates[0].url
}

function Get-MetaImage([string]$html) {
    # og:image / twitter:image，兼容 content 写在 property 前或后
    $patterns = @(
        '<meta[^>]+(?:property|name)="(?:og:image|og:image:url|twitter:image|twitter:image:src)"[^>]*>',
        '<meta[^>]+content="([^"]+)"[^>]+(?:property|name)="(?:og:image|og:image:url|twitter:image|twitter:image:src)"[^>]*>'
    )
    foreach ($p in $patterns) {
        foreach ($m in [regex]::Matches($html, $p)) {
            $c = [regex]::Match($m.Value, 'content="([^"]+)"')
            if ($c.Success) { return ([System.Net.WebUtility]::HtmlDecode($c.Groups[1].Value)) }
        }
    }
    $link = [regex]::Match($html, '<link[^>]+rel="image_src"[^>]+href="([^"]+)"')
    if ($link.Success) { return [System.Net.WebUtility]::HtmlDecode($link.Groups[1].Value) }
    return ''
}

# ---- 相关性：内容词必须真的出现在条目文本里（馆藏源专用） ----

$StopWords = @(
    'poster', 'posters', 'design', 'graphic', 'art', 'arts', 'print', 'prints', 'style', 'styles',
    'layout', 'typography', 'cover', 'covers', 'book', 'books', 'magazine', 'modern', 'vintage',
    'illustration', 'advert', 'advertising', 'visual', 'media', 'type', 'typographic'
)

function Get-ContentTokens([string[]]$queries) {
    $tokens = @()
    foreach ($q in $queries) {
        if ($q -match '[\u4e00-\u9fff]') { return @() }   # 中文检索词无法直接匹配英文馆藏元数据
        foreach ($w in ($q.ToLowerInvariant() -split '[^a-z0-9]+')) {
            if ($w.Length -lt 3) { continue }
            if ($w -in $StopWords) { continue }
            if ($tokens -notcontains $w) { $tokens += $w }
        }
    }
    return $tokens
}

function Test-Relevance([string]$text, [string[]]$tokens) {
    if ($tokens.Count -eq 0) { return $true }
    $hay = ([string]$text).ToLowerInvariant()
    foreach ($t in $tokens) {
        if ($hay.Contains($t)) { return $true }
    }
    return $false
}

# ---- 统一条目结构 ----

function New-RefEntry {
    param(
        [string]$title, [string]$creator = '', [string]$date = '',
        [string]$source, [string]$sourceKind, [string]$license,
        [string]$imageUrl, [string]$pageUrl = '', [string]$note = ''
    )
    return [pscustomobject]@{
        title      = (Clean-Text $title)
        creator    = (Clean-Text $creator)
        date       = (Clean-Text $date)
        source     = $source
        sourceKind = $sourceKind
        license    = $license
        imageUrl   = $imageUrl
        pageUrl    = $pageUrl
        note       = $note
    }
}

function Test-JunkTitle([string]$title) {
    if ([string]::IsNullOrWhiteSpace($title)) { return $false }
    return ($title -match '(?i)\btutorial\b|\btemplate\b|free download|\betsy\b|\byoutube\b|\bcourse\b|\budemy\b|wallpaper|logo ?maker|\bcanva\b|\bfigma community\b|google search|screenshot|screen-shot|capture d|pinterest|design ideas|best .* ideas|inspiration\b|tumblr_|indesign|photoshop|illustrator|after ?effects|figma')
}

function Get-Year([string]$value) {
    $m = [regex]::Match([string]$value, '(1[6-9]\d{2}|20\d{2})')
    if ($m.Success) { return $m.Groups[1].Value }
    return ''
}

# ---- 来源 1：Are.na（专业设计/艺术收藏平台，优先） ----

function Search-Arena([string]$query) {
    $take = [Math]::Min([Math]::Max($Limit * 3, 6), 12)
    $per = [Math]::Min([Math]::Max($take * 4, 20), 60)
    $uri = 'https://api.are.na/v2/search?q={0}&type=Image&per={1}' -f [Uri]::EscapeDataString($query), $per
    $json = Get-JsonDoc $uri -Referer 'https://www.are.na/'
    $items = @()
    foreach ($b in @($json.blocks)) {
        if ($items.Count -ge $take) { break }
        if ($null -eq $b) { continue }
        if ($b.class -ne 'Image') { continue }
        if (-not $b.image) { continue }
        if ($b.image.original -and $b.image.original.file_size -and [int]$b.image.original.file_size -lt 40000) { continue }
        $title = [string]$b.title
        if ([string]::IsNullOrWhiteSpace($title)) { $title = [string]$b.generated_title }
        if (Test-JunkTitle $title) { continue }
        if ([string]::IsNullOrWhiteSpace($title) -or $title -eq 'None' -or $title -eq 'image' -or
            $title -match '(?i)\.(jpe?g|png|gif|webp)$' -or $title -match '^[0-9a-f]{12,}') {
            $title = 'Are.na block #' + $b.id
        }
        $img = ''
        if ($b.image.original -and $b.image.original.url) { $img = [string]$b.image.original.url }
        elseif ($b.image.large -and $b.image.large.url) { $img = [string]$b.image.large.url }
        if (-not $img) { continue }
        $creator = ''
        if ($b.user -and $b.user.full_name) { $creator = [string]$b.user.full_name }
        $items += New-RefEntry -title $title -creator $creator -date '' -source 'Are.na' `
            -sourceKind 'design' -license '仅研究（Are.na 作者版权）' -imageUrl $img `
            -pageUrl ('https://www.are.na/block/' + $b.id) -note ('query: ' + $query)
    }
    return $items
}

# ---- 来源 2：Fonts In Use（排版/字体档案） ----

function Search-FontsInUse([string]$query) {
    $uri = 'https://fontsinuse.com/search?q=' + [Uri]::EscapeDataString($query)
    $html = Get-HtmlDoc $uri
    $items = @()
    $anchors = [regex]::Matches($html, '<a[^>]+href="(/uses/[0-9]+/[^"]+)"')
    $seen = @{}
    for ($i = 0; $i -lt $anchors.Count; $i++) {
        if ($items.Count -ge $Limit) { break }
        $href = $anchors[$i].Groups[1].Value
        if ($seen.ContainsKey($href)) { continue }
        $seen[$href] = $true
        $start = $anchors[$i].Index
        $end = if ($i + 1 -lt $anchors.Count) { $anchors[$i + 1].Index } else { [Math]::Min($html.Length, $start + 6000) }
        if ($end - $start -gt 6000) { $end = $start + 6000 }
        $slice = $html.Substring($start, $end - $start)

        $img = [regex]::Match($slice, '<img[^>]+src="(https://assets\.fontsinuse\.com/static/use-media-items/[^"]+)"')
        if (-not $img.Success) { continue }
        $imgUrl = $img.Groups[1].Value -replace '/thumb/', '/original/'
        if ($imgUrl -match '\.webp(\?|$)') { $imgUrl = $imgUrl -replace '\.webp', '.jpeg' }

        $head = [regex]::Match($slice, 'fiu-galleryItem__headline">(.*?)</span>')
        $title = if ($head.Success) { Convert-HtmlText $head.Groups[1].Value } else { 'Fonts In Use' }
        $date = ''
        $d = [regex]::Match($slice, 'fiu-galleryItem__date">(.*?)</span>')
        if ($d.Success) { $date = Convert-HtmlText $d.Groups[1].Value }
        $designers = @()
        $ul = [regex]::Match($slice, '(?s)fiu-galleryItem__designers">(.*?)</ul>')
        if ($ul.Success) {
            foreach ($li in [regex]::Matches($ul.Groups[1].Value, '<li>(.*?)</li>')) {
                $designers += Convert-HtmlText $li.Groups[1].Value
            }
        }
        $items += New-RefEntry -title $title -creator ($designers -join ', ') -date $date `
            -source 'Fonts In Use' -sourceKind 'design' -license '仅研究（Fonts In Use）' `
            -imageUrl $imgUrl -pageUrl ('https://fontsinuse.com' + $href) -note ('query: ' + $query)
    }
    return $items
}

# ---- 来源 3：Design Reviewed（平面设计史档案，WP REST） ----

function Search-DesignReviewed([string]$query, [string[]]$tokens) {
    $per = [Math]::Max($Limit * 2, 6)
    $uri = 'https://designreviewed.com/wp-json/wp/v2/posts?search={0}&per_page={1}&_embed=1' -f [Uri]::EscapeDataString($query), $per
    $posts = Get-JsonDoc $uri
    $items = @()
    foreach ($p in @($posts)) {
        if ($items.Count -ge $Limit) { break }
        if (-not $p.link) { continue }
        $img = ''
        $embedded = $p.PSObject.Properties['_embedded']
        if ($embedded -and $embedded.Value) {
            $media = $embedded.Value.PSObject.Properties['wp:featuredmedia']
            if ($media -and $media.Value) {
                $first = @($media.Value)[0]
                if ($first -and $first.source_url) { $img = [string]$first.source_url }
            }
        }
        if (-not $img -and $p.jetpack_featured_media_url) { $img = [string]$p.jetpack_featured_media_url }
        if (-not $img) { continue }
        $title = Convert-HtmlText $p.title.rendered
        $excerpt = Convert-HtmlText ([string]$p.excerpt.rendered)
        $body = Convert-HtmlText ([string]$p.content.rendered)
        if ($body.Length -gt 600) { $body = $body.Substring(0, 600) }
        if (-not (Test-Relevance ($title + ' ' + $excerpt + ' ' + $body) $tokens)) { continue }
        $items += New-RefEntry -title $title -creator '' -date '' `
            -source 'Design Reviewed' -sourceKind 'design' -license '仅研究（Design Reviewed）' `
            -imageUrl $img -pageUrl ([string]$p.link) -note ('query: ' + $query)
    }
    return $items
}

# ---- 来源 4：It's Nice That（当代设计媒体） ----

function Search-ItsNiceThat([string]$query) {
    $uri = 'https://www.itsnicethat.com/articles?search=' + [Uri]::EscapeDataString($query)
    $html = Get-HtmlDoc $uri
    $links = @()
    foreach ($m in [regex]::Matches($html, 'href="(/articles/[a-z0-9\-]+)"')) {
        $l = $m.Groups[1].Value
        if ($links -notcontains $l) { $links += $l }
    }
    $items = @()
    $want = [Math]::Min($Limit, 3)
    foreach ($l in ($links | Select-Object -First $want)) {
        $pageUrl = 'https://www.itsnicethat.com' + $l
        try {
            $page = Get-HtmlDoc $pageUrl
        } catch {
            Add-Warning ("[itsnicethat] 打开页面失败：{0} — {1}" -f $pageUrl, $_.Exception.Message)
            continue
        }
        $img = Get-MetaImage $page
        if (-not $img) { continue }
        if ($img -match '\.gif(\?|$)') { continue }   # 动图不进参考板
        $title = ''
        $t = [regex]::Match($page, '<meta[^>]+property="og:title"[^>]+content="([^"]+)"')
        if (-not $t.Success) { $t = [regex]::Match($page, '<title>(.*?)</title>') }
        if ($t.Success) { $title = Convert-HtmlText $t.Groups[1].Value }
        if (Test-JunkTitle $title) { continue }
        $items += New-RefEntry -title $title -creator '' -date '' -source "It's Nice That" `
            -sourceKind 'design' -license '仅研究（Its Nice That）' -imageUrl $img `
            -pageUrl $pageUrl -note ('query: ' + $query)
    }
    return $items
}

# ---- 来源 5：显式页面 URL（web_search 命中的专业站页面） ----

function Search-UrlPages([string[]]$urls) {
    $items = @()
    $meta = @{}
    if ($UrlMeta -and (Test-Path -LiteralPath $UrlMeta)) {
        try {
            $rows = Get-Content -LiteralPath $UrlMeta -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($row in @($rows)) {
                if ($row -and $row.imageUrl) { $meta[[string]$row.imageUrl] = $row }
            }
        } catch {
            Add-Warning ('[url] UrlMeta 读不了，按无标题处理：' + $_.Exception.Message)
        }
    }
    foreach ($u in $urls) {
        if ($u -match '\.(jpe?g|png|webp|gif)(\?.*)?$') {
            $m = $meta[$u]
            $title = ''
            if ($m -and $m.title) { $title = [string]$m.title }
            if (-not $title) { $title = [System.IO.Path]::GetFileNameWithoutExtension(([Uri]$u).AbsolutePath) }
            $creator = if ($m -and $m.creator) { [string]$m.creator } else { '' }
            $pageUrl = if ($m -and $m.pageUrl) { [string]$m.pageUrl } else { '' }
            $sourceName = if ($m -and $m.source) { [string]$m.source } else { 'Direct image' }
            $items += New-RefEntry -title $title -creator $creator -date '' `
                -source $sourceName -sourceKind 'design' -license '站点版权，仅研究' `
                -imageUrl $u -pageUrl $pageUrl
            continue
        }
        try {
            $html = Get-HtmlDoc $u
        } catch {
            Add-Warning ("[url] 打开失败（站点可能反爬）：{0} — {1}" -f $u, $_.Exception.Message)
            continue
        }
        $img = Get-MetaImage $html
        if (-not $img) { $img = Get-FallbackImage $html $u }
        if (-not $img) {
            Add-Warning ("[url] 页面里没有可用的图（og:image 与 <img> 都没抽到）：{0}" -f $u)
            continue
        }
        $title = ''
        $t = [regex]::Match($html, '<meta[^>]+property="og:title"[^>]+content="([^"]+)"')
        if (-not $t.Success) { $t = [regex]::Match($html, '<title>(.*?)</title>') }
        if ($t.Success) { $title = Convert-HtmlText $t.Groups[1].Value }
        $hostName = ([Uri]$u).Host -replace '^www\.', ''
        $items += New-RefEntry -title $title -creator '' -date '' -source ('Web · ' + $hostName) `
            -sourceKind 'design' -license '站点版权，仅研究' -imageUrl $img -pageUrl $u
    }
    return $items
}

# ---- 来源 6+：公共馆藏（兜底；必须通过内容词过滤） ----

function Search-Aic([string]$query, [string[]]$tokens) {
    $fields = 'id,title,image_id,artist_display,date_display,is_public_domain,classification_title,department_title,style_title,medium_display'
    $take = [Math]::Max($Limit * 5, 12)
    $uri = 'https://api.artic.edu/api/v1/artworks/search?q={0}&limit={1}&fields={2}' -f [Uri]::EscapeDataString($query), $take, $fields
    $json = Get-JsonDoc $uri
    $items = @()
    foreach ($d in @($json.data)) {
        if ($items.Count -ge $Limit) { break }
        if (-not $d.image_id) { continue }
        $hay = (@($d.title, $d.classification_title, $d.style_title, $d.medium_display, $d.department_title) -join ' ')
        if (-not (Test-Relevance $hay $tokens)) { continue }
        if ($script:RequireGraphic -and $d.classification_title -and $d.classification_title -notmatch $script:GraphicPattern) { continue }
        $pd = ($null -ne $d.is_public_domain -and [bool]$d.is_public_domain)
        $items += New-RefEntry -title $d.title -creator $d.artist_display -date $d.date_display `
            -source 'Art Institute of Chicago' -sourceKind 'museum' `
            -license $(if ($pd) { 'CC0 / Public Domain' } else { 'AIC image — study only' }) `
            -imageUrl ('https://www.artic.edu/iiif/2/{0}/full/1686,/0/default.jpg' -f $d.image_id) `
            -pageUrl ('https://www.artic.edu/artworks/{0}' -f $d.id) -note ('query: ' + $query)
    }
    return $items
}

function Search-Met([string]$query, [string[]]$tokens) {
    $searchUri = 'https://collectionapi.metmuseum.org/public/collection/v1.1/search?hasImages=true&q={0}' -f [Uri]::EscapeDataString($query)
    $search = Get-JsonDoc $searchUri
    if (-not $search.objectIDs) { return @() }
    $ids = @($search.objectIDs) | Select-Object -First ([Math]::Max($Limit * 6, 24))
    $items = @()
    foreach ($id in $ids) {
        if ($items.Count -ge $Limit) { break }
        try {
            $o = Get-JsonDoc ('https://collectionapi.metmuseum.org/public/collection/v1/objects/' + $id)
        } catch { continue }
        if (-not $o.isPublicDomain) { continue }
        if (-not $o.primaryImage) { continue }
        $hay = (@($o.title, $o.objectName, $o.classification, $o.medium, $o.department) -join ' ')
        if (-not (Test-Relevance $hay $tokens)) { continue }
        if ($script:RequireGraphic -and ($o.medium + ' ' + $o.objectName + ' ' + $o.classification) -notmatch $script:GraphicPattern) { continue }
        $items += New-RefEntry -title $o.title -creator $o.artistDisplayName -date $o.objectDate `
            -source 'The Met (Open Access)' -sourceKind 'museum' -license 'CC0 / Public Domain' `
            -imageUrl $o.primaryImage -pageUrl $o.objectURL -note ('query: ' + $query)
    }
    return $items
}

function Search-Cleveland([string]$query, [string[]]$tokens) {
    $uri = 'https://openaccess-api.clevelandart.org/api/artworks/?q={0}&has_image=1&cc0=1&limit={1}' -f [Uri]::EscapeDataString($query), [Math]::Max($Limit * 4, 12)
    $json = Get-JsonDoc $uri
    $items = @()
    foreach ($d in @($json.data)) {
        if ($items.Count -ge $Limit) { break }
        $hay = (@($d.title, $d.type, $d.technique) -join ' ')
        if (-not (Test-Relevance $hay $tokens)) { continue }
        if ($script:RequireGraphic -and $d.type -and $d.type -notmatch $script:GraphicPattern) { continue }
        $img = ''
        if ($d.images.print -and $d.images.print.url) { $img = [string]$d.images.print.url }
        elseif ($d.images.web -and $d.images.web.url) { $img = [string]$d.images.web.url }
        if (-not $img) { continue }
        $creator = ''
        if ($d.creators -and @($d.creators).Count -gt 0) { $creator = [string](@($d.creators)[0].description) }
        $items += New-RefEntry -title $d.title -creator $creator -date $d.creation_date `
            -source 'Cleveland Museum of Art' -sourceKind 'museum' -license 'CC0 / Public Domain' `
            -imageUrl $img -pageUrl $d.url -note ('query: ' + $query)
    }
    return $items
}

function Search-Commons([string]$query, [string[]]$tokens) {
    $qs = @(
        'action=query', 'format=json', 'generator=search',
        ('gsrsearch=' + [Uri]::EscapeDataString($query)),
        'gsrnamespace=6', ('gsrlimit=' + [Math]::Max($Limit * 4, 12)),
        'prop=imageinfo', 'iiprop=url|size|mime|extmetadata', 'iiurlwidth=1600'
    ) -join '&'
    $json = Get-JsonDoc ('https://commons.wikimedia.org/w/api.php?' + $qs)
    $items = @()
    if (-not $json.query -or -not $json.query.pages) { return $items }
    foreach ($prop in $json.query.pages.PSObject.Properties) {
        if ($items.Count -ge $Limit) { break }
        $page = $prop.Value
        $info = @($page.imageinfo)[0]
        if (-not $info) { continue }
        if ($info.mime -notin @('image/jpeg', 'image/png')) { continue }
        if ($info.width -lt $MinWidth) { continue }
        if (-not (Test-Relevance ([string]$page.title) $tokens)) { continue }
        $license = 'See file page'
        try {
            if ($info.extmetadata.LicenseShortName) { $license = [string]$info.extmetadata.LicenseShortName.value }
        } catch { }
        $items += New-RefEntry -title ([string]$page.title -replace '^File:', '') -creator '' -date '' `
            -source 'Wikimedia Commons' -sourceKind 'museum' -license $license `
            -imageUrl ([string]$info.thumburl) -pageUrl ([string]$info.descriptionurl) -note ('query: ' + $query)
    }
    return $items
}

function Search-Openverse([string]$query, [string[]]$tokens) {
    $uri = 'https://api.openverse.org/v1/images/?q={0}&license=cc0,pdm,by,by-sa&page_size={1}&mature=false' -f [Uri]::EscapeDataString($query), [Math]::Max($Limit * 2, 6)
    $json = Get-JsonDoc $uri
    $items = @()
    foreach ($r in @($json.results)) {
        if ($items.Count -ge $Limit) { break }
        if (-not $r.url) { continue }
        if ($null -ne $r.width -and [int]$r.width -lt $MinWidth) { continue }
        if (-not (Test-Relevance ([string]$r.title) $tokens)) { continue }
        $items += New-RefEntry -title $r.title -creator $r.creator -date '' -source 'Openverse' `
            -sourceKind 'museum' -license ([string]$r.license).ToUpperInvariant() `
            -imageUrl ([string]$r.url) -pageUrl ([string]$r.foreign_landing_url) -note ('query: ' + $query)
    }
    return $items
}

# ---- 主流程 ----

if (-not $Slug) {
    if ($Query.Count -gt 0) {
        $raw = ($Query -join '-').ToLowerInvariant()
        $Slug = ($raw -replace '[^a-z0-9]+', '-').Trim('-')
    } else { $Slug = 'reference' }
    if ([string]::IsNullOrWhiteSpace($Slug)) { $Slug = 'reference' }
    if ($Slug.Length -gt 48) { $Slug = $Slug.Substring(0, 48).Trim('-') }
}
if ($Slug -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') { throw "Slug 不合法：'$Slug'。只允许字母、数字、点、下划线、短横线（≤64 字符）。" }
if ($Limit -lt 1 -or $Limit -gt 12) { throw 'Limit 需在 1–12 之间。' }
if ($Max -lt 1 -or $Max -gt 40) { throw 'Max 需在 1–40 之间。' }

$tokens = Get-ContentTokens $Query
$museumSources = @('aic', 'met', 'cleveland', 'commons', 'openverse')
if ($tokens.Count -eq 0 -and $Query.Count -gt 0 -and @($Sources | Where-Object { $_ -in $museumSources }).Count -gt 0) {
    Add-Warning '检索词里没有可比对的内容词（或含中文），馆藏来源不做相关性过滤；专业设计来源不受影响。'
}

$root = if ($Dest) { [System.IO.Path]::GetFullPath($Dest) } else { Join-Path ([System.IO.Path]::GetFullPath($Workspace)) ('designs\references\' + $Slug) }
$imgDir = Join-Path $root 'img'
if ($Clean -and (Test-Path -LiteralPath $root)) {
    foreach ($name in @('img', 'refs.json', 'REFS.md', 'board.png')) {
        $victim = Join-Path $root $name
        if (Test-Path -LiteralPath $victim) { Remove-Item -LiteralPath $victim -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
foreach ($d in @($root, $imgDir)) {
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

$script:RequireGraphic = (($Query -join ' ') -match '(?i)poster|print|book|cover|graphic|typograph|letter|layout|editorial|brochure|flyer|advert|magazine')
$script:GraphicPattern = '(?i)poster|print|drawing|engrav|lithograph|etching|woodcut|book|periodical|ephemeral|graphic|design|typograph|advert|cover|plate|leaflet|flyer|broadside|photograph'
$script:candidates = @()
$seenUrls = @{}
$script:sourceStats = @{}

function Add-Candidates {
    param($items, [string]$sourceName)
    $added = 0
    foreach ($item in @($items)) {
        if (-not $item -or -not $item.imageUrl) { continue }
        if ($seenUrls.ContainsKey($item.imageUrl)) { continue }
        if ($script:candidates.Count -ge 40) { break }
        $seenUrls[$item.imageUrl] = $true
        $script:candidates += $item
        $added++
    }
    $script:sourceStats[$sourceName] = $added
}

# 显式 URL 优先（-Url 不受 -Sources 限制）；其次是来源顺序
if ($Url.Count -gt 0) {
    try { Add-Candidates (Search-UrlPages $Url) 'url' } catch { Add-Warning ('[url] 处理失败：' + $_.Exception.Message) }
}

foreach ($source in $Sources) {
    if ($source -eq 'url') { continue }
    if ($Query.Count -eq 0) { continue }
    foreach ($q in $Query) {
        if ($script:candidates.Count -ge 40) { break }
        try {
            $found = switch ($source) {
                'arena' { Search-Arena $q }
                'fontsinuse' { Search-FontsInUse $q }
                'designreviewed' { Search-DesignReviewed $q $tokens }
                'itsnicethat' { Search-ItsNiceThat $q }
                'aic' { Search-Aic $q $tokens }
                'met' { Search-Met $q $tokens }
                'cleveland' { Search-Cleveland $q $tokens }
                'commons' { Search-Commons $q $tokens }
                'openverse' { Search-Openverse $q $tokens }
            }
        } catch {
            Add-Warning ("[{0}] '{1}' 检索失败：{2}" -f $source, $q, $_.Exception.Message)
            continue
        }
        $found = @($found)
        if ($found.Count -eq 0) {
            Add-Warning ("[{0}] '{1}' 没有通过相关性/质量初筛的条目。" -f $source, $q)
            continue
        }
        Add-Candidates $found $source
    }
}

if ($script:candidates.Count -eq 0) {
    throw ("没有检索到可用图片（Sources=$($Sources -join ',')，Query=$($Query -join ' / ')）。" +
        '换更具体的检索词（movement + medium + decade，如 "swiss style poster 1960s"），' +
        '或先用 web_search 找到页面/图片直链再用 -Url 传入——任何网站都可以，不限专业设计站。')
}

# 下载 + 质量门槛
$records = @()
$soft = @()   # 低清但可用的备选：主列表不足 4 张时补位
$i = 0
$dropped = 0
foreach ($item in $script:candidates) {
    if ($records.Count -ge $Max) { break }
    $i++
    $ext = Get-ExtFromUrl $item.imageUrl
    $fileName = ('{0:D2}{1}' -f $i, $ext)
    $fullPath = Join-Path $imgDir $fileName
    try {
        Invoke-Http -Uri $item.imageUrl -OutFile $fullPath -Accept 'image/jpeg,image/png,image/*' -TimeoutSec 45
    } catch {
        Add-Warning ("下载失败，跳过：{0} — {1}" -f $item.title, $_.Exception.Message)
        continue
    }
    $bytes = (Get-Item -LiteralPath $fullPath).Length
    if ($bytes -lt 20000) {
        Remove-Item -LiteralPath $fullPath -Force -ErrorAction SilentlyContinue
        Add-Warning ("文件过小（{0} KB），疑似缩略图/占位图，丢弃：{1}" -f [Math]::Round($bytes / 1024), $item.title)
        $dropped++
        continue
    }
    # 站点的 Content-Type 常与 URL 后缀不一致（.gif/.png 实际是 WebP），先按字节判真格式再改名
    $kind = Get-ImageKind $fullPath
    if ($kind -eq 'webp') {
        if (Convert-WebpToJpeg $fullPath) { $kind = 'jpg' }
        else {
            Remove-Item -LiteralPath $fullPath -Force -ErrorAction SilentlyContinue
            Add-Warning ("WebP 且本机无解码器，丢弃：{0}" -f $item.title)
            $dropped++
            continue
        }
    }
    $wantExt = ''
    switch ($kind) {
        'jpg' { $wantExt = '.jpg' }
        'png' { $wantExt = '.png' }
        'gif' { $wantExt = '.gif' }
        'bmp' { $wantExt = '.bmp' }
    }
    if ($wantExt) {
        $currentExt = [System.IO.Path]::GetExtension($fullPath).ToLowerInvariant()
        if ($currentExt -ne $wantExt) {
            $newPath = [System.IO.Path]::ChangeExtension($fullPath, $wantExt)
            Move-Item -LiteralPath $fullPath -Destination $newPath -Force
            $fullPath = $newPath
            $fileName = [System.IO.Path]::GetFileName($newPath)
        }
    }
    $size = Get-ImageSize $fullPath
    if ($size.Width -eq 0) {
        Remove-Item -LiteralPath $fullPath -Force -ErrorAction SilentlyContinue
        Add-Warning ("无法解码图片（不支持的格式），丢弃：{0}" -f $item.title)
        $dropped++
        continue
    }
    $isSoft = (-not $AllowSmall -and ($size.Width -lt $MinWidth -or $size.Height -lt $MinHeight))
    if ($isSoft -and $size.Width -lt 600) {
        Remove-Item -LiteralPath $fullPath -Force -ErrorAction SilentlyContinue
        Add-Warning ("分辨率太低（{0}×{1}），丢弃：{2}" -f $size.Width, $size.Height, $item.title)
        $dropped++
        continue
    }
    $sha = Get-Sha256 $fullPath
    if (@($records | Where-Object { $_.sha256 -eq $sha }).Count -gt 0) {
        Remove-Item -LiteralPath $fullPath -Force -ErrorAction SilentlyContinue
        Add-Warning ("重复图片，丢弃：{0}" -f $item.title)
        continue
    }
    $rec = [pscustomobject]@{
        index      = 0
        file       = ('img/' + $fileName)
        title      = $item.title
        creator    = $item.creator
        date       = $item.date
        source     = $item.source
        sourceKind = $item.sourceKind
        license    = $item.license
        pageUrl    = $item.pageUrl
        imageUrl   = $item.imageUrl
        note       = $item.note
        width      = $size.Width
        height     = $size.Height
        bytes      = $bytes
        sha256     = $sha
    }
    if ($isSoft) {
        $soft += $rec
        Add-Warning ("低清备选（{0}×{1}，低于 {2}px）：{3} — 主列表不足 4 张时会自动补位" -f $size.Width, $size.Height, $MinWidth, $item.title)
    } else {
        $records += $rec
    }
}

# 主列表不足 4 张时，用低清备选补位（来源不限，很多平台原图就这么大）
if ($records.Count -lt 4 -and $soft.Count -gt 0) {
    $need = 4 - $records.Count
    $pick = @($soft | Sort-Object -Property width -Descending | Select-Object -First $need)
    foreach ($p in $pick) { $records += $p; Add-Warning ("补入低清参考：{0}（{1}×{2}）" -f $p.title, $p.width, $p.height) }
}

if ($records.Count -eq 0) {
    $msg = '所有候选图片都下载失败、分辨率不足或无法解码（丢弃 {0} 张）。建议：换更具体的检索词；用 -Url 传任意页面/图片直链；或加 -AllowSmall 放宽门槛（交付说明里要注明）。' -f $dropped
    throw $msg
}

for ($k = 0; $k -lt $records.Count; $k++) { $records[$k].index = $k + 1 }

$designCount = @($records | Where-Object { $_.sourceKind -eq 'design' }).Count
$museumCount = @($records | Where-Object { $_.sourceKind -eq 'museum' }).Count
$bySource = @{}
foreach ($r in $records) {
    if ($bySource.ContainsKey($r.source)) { $bySource[$r.source] = $bySource[$r.source] + 1 }
    else { $bySource[$r.source] = 1 }
}

if ($designCount -eq 0) {
    Add-Warning ('本次没有从脚本内置的四站（Are.na / Fonts In Use / Design Reviewed / It''s Nice That）或 -Url 拿到图，' +
        '板子全部来自馆藏兜底。来源不限——馆藏本身完全可以当过审参考；只是如果年代/媒介对不上，' +
        '就换更具体的词，或先用 web_search 找到页面/图片直链再用 -Url 传入。')
}

$manifest = [pscustomobject]@{
    slug        = $Slug
    queries     = $Query
    urls        = $Url
    sources     = $Sources
    createdAt   = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
    purpose     = 'design reference — study only, never place into artwork'
    qualityGate = [pscustomobject]@{ minWidth = $MinWidth; minHeight = $MinHeight; minBytes = 20000; allowSmall = [bool]$AllowSmall }
    count       = $records.Count
    designCount = $designCount
    museumCount = $museumCount
    items       = $records
}
$manifestJson = $manifest | ConvertTo-Json -Depth 6
[System.IO.File]::WriteAllText((Join-Path $root 'refs.json'), $manifestJson, (New-Object System.Text.UTF8Encoding($false)))

$md = New-Object System.Text.StringBuilder
[void]$md.AppendLine('# 参考板：' + $Slug)
[void]$md.AppendLine('')
[void]$md.AppendLine(('- 检索词：' + $(if ($Query.Count) { $Query -join ' / ' } else { '（无，按 -Url 取）' })))
if ($Url.Count -gt 0) { [void]$md.AppendLine(('- 指定页面：' + ($Url -join ' / '))) }
[void]$md.AppendLine(('- 抓取时间：' + $manifest.createdAt))
[void]$md.AppendLine(('- 张数：{0}（内置四站/-Url 来源 {1}，馆藏 {2}）' -f $records.Count, $designCount, $museumCount))
[void]$md.AppendLine(('- 质量门槛：宽 ≥ {0}px{1}、文件 ≥ 20KB' -f $MinWidth, $(if ($MinHeight -gt 0) { '、高 ≥ ' + $MinHeight + 'px' } else { '' })))
[void]$md.AppendLine('- 用途：**仅供设计研究，不得置入成品**（要进版面请走 `Fetch-FreeAsset.ps1` 素材流程）。')
[void]$md.AppendLine('')
if ($designCount -eq 0) {
    [void]$md.AppendLine('> ℹ 本板全部来自馆藏。来源不限，馆藏也能当过审参考；若年代/媒介与需求对不上，换更具体的词或补 `-Url` 即可。')
    [void]$md.AppendLine('')
}
[void]$md.AppendLine('| # | 类型 | 标题 | 作者 / 年代 | 来源 | 许可 | 尺寸 | 页面 |')
[void]$md.AppendLine('|---|---|---|---|---|---|---|---|')
foreach ($r in $records) {
    $creator = (@($r.creator, $r.date) | Where-Object { $_ }) -join ' · '
    $title = ($r.title -replace '\|', '\|')
    $kind = if ($r.sourceKind -eq 'design') { '设计' } else { '馆藏' }
    [void]$md.AppendLine(('| {0} | {1} | {2} | {3} | {4} | {5} | {6}×{7} | {8} |' -f $r.index, $kind, $title, $creator, $r.source, $r.license, $r.width, $r.height, $r.pageUrl))
}
[void]$md.AppendLine('')
[void]$md.AppendLine('## 使用方式')
[void]$md.AppendLine('')
[void]$md.AppendLine('1. `read_image` 看 `board.png` 建立整体印象，再逐张看 `img/0X` 的细节。')
[void]$md.AppendLine('2. 先筛掉「同语法但不同年代/媒介」的图：只留和需求同一个运动、同一种印刷方式、同一个年代的 2–3 张。')
[void]$md.AppendLine('3. 按 `references/reference-hunting.md` 第 3.5 步逐张精读（7 条），写 `designs/<slug>/reference-study.md`。')
[void]$md.AppendLine('4. 按第 4 步写「风格 DNA 卡」：每个字段带 `#NN` 溯源，明确「我不抄的 3 件事」。')
[void]$md.AppendLine('5. 把本板（编号）+ 精读 + 三问交付用户过审，原话写进 `designs/<slug>/refs-approved.md`；没有它不许开方向门/排版。')
[void]$md.AppendLine('6. 只把 3 条可迁移规则写进设计决策单；出稿后和参考做 A/B 诊断。')
[void]$md.AppendLine('')
[void]$md.AppendLine('## 版权')
[void]$md.AppendLine('')
[void]$md.AppendLine('参考图不入成品、不描图、不 1:1 复刻单件布局；当代设计师作品仅用于研究并在交付说明中如实说明。')
[System.IO.File]::WriteAllText((Join-Path $root 'REFS.md'), $md.ToString(), (New-Object System.Text.UTF8Encoding($false)))

$sheet = $null
if (-not $NoSheet) {
    $sheetScript = Join-Path $PSScriptRoot 'New-ContactSheet.ps1'
    if (-not (Test-Path -LiteralPath $sheetScript)) { throw "找不到同目录脚本 New-ContactSheet.ps1：$sheetScript" }
    $images = @($records | ForEach-Object { Join-Path $root ($_.file -replace '/', '\') })
    $labels = @($records | ForEach-Object {
            $creator = (@($_.creator, $_.date) | Where-Object { $_ }) -join ' · '
            $text = $_.title
            if ($creator) { $text = $text + ' — ' + $creator }
            $text + ' [' + $_.source + ']'
        })
    $sheet = & $sheetScript -Images $images -Out (Join-Path $root 'board.png') -Title ('Reference board · ' + $Slug) -Cols $Cols -Labels $labels
}

$summary = [pscustomobject]@{
    ok          = $true
    slug        = $Slug
    dir         = $root
    count       = $records.Count
    designCount = $designCount
    museumCount = $museumCount
    qualityGate = $manifest.qualityGate
    bySource    = $bySource
    manifest    = (Join-Path $root 'refs.json')
    readme      = (Join-Path $root 'REFS.md')
    board       = if ($sheet) { (Join-Path $root 'board.png') } else { $null }
    warnings    = @($script:Warnings)
}
$summary | ConvertTo-Json -Depth 4
