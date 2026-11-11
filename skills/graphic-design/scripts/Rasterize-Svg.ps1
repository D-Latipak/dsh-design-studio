#requires -Version 5.1
<#
.SYNOPSIS
  平面设计工坊 · 把 SVG（图标/矢量素材）光栅化成能放进版面的 PNG

.DESCRIPTION
  DesignCraft 的置图（file.place / place_image）只吃 PNG / JPEG / WebP / GIF / TIFF，**不吃 SVG**；
  PhotoCraft 打开 SVG 会按它自己的内在尺寸栅格化（实测 24×24 的图标出来只有 256px，印刷不够）。
  所以 SVG 要走本脚本：用系统自带的 Edge 无头模式，把 SVG 铺满一个精确像素尺寸的画布截图。

  输出是带透明通道的 PNG（-Background transparent），或者你指定的底色。
  印前口径：图标在版面上的宽度（pt）× 4.1667 = 需要的像素尺寸，取大不取小。

.PARAMETER Path
  一个或多个 .svg 文件。

.PARAMETER Size
  输出正方形边长（px）。默认 1024。

.PARAMETER Background
  transparent（默认）| white | 任意 #rrggbb。

.PARAMETER Out
  输出目录。默认与 SVG 同目录。

.PARAMETER Pad
  图标四周留白比例（0–0.4，默认 0）。给 0.08 就是留 8% 安全边。

.PARAMETER Color
  把 SVG 里所有 currentColor / #000 换成这个颜色（写 #rrggbb）。不填就保持原色。

.EXAMPLE
  .\Rasterize-Svg.ps1 -Path "designs\assets\coffee.svg" -Size 2048 -Out "designs\assets\png"

.EXAMPLE
  .\Rasterize-Svg.ps1 -Path "designs\assets\*.svg" -Size 1024 -Color "#F2E8D5" -Background "#0E1B2A"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string[]]$Path,

    [int]$Size = 1024,
    [string]$Background = 'transparent',
    [string]$Out = '',
    [double]$Pad = 0,
    [string]$Color = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$edge = @(
    (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe')
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

if (-not $edge) { throw '找不到 msedge.exe，无法光栅化 SVG。请换一台装了 Edge 的机器，或让设计师手工导出 PNG。' }

$bgCss = switch -Regex ($Background) {
    '^(?i)transparent$' { 'transparent' }
    '^(?i)white$' { '#ffffff' }
    '^#[0-9a-fA-F]{6}$' { $Background }
    default { throw "Background 只接受 transparent / white / #rrggbb，收到：$Background" }
}
$bgFlag = if ($bgCss -eq 'transparent') { '--default-background-color=00000000' } else { "--default-background-color=$($bgCss.TrimStart('#'))FF" }

$svgFiles = @()
foreach ($p in $Path) {
    $items = Get-Item -LiteralPath $p -ErrorAction SilentlyContinue
    if (-not $items) { Write-Warning ('找不到：' + $p); continue }
    $svgFiles += @($items | Where-Object { $_.Extension -eq '.svg' })
}
if ($svgFiles.Count -eq 0) { throw '没有可处理的 .svg 文件。' }

$results = @()
foreach ($svg in $svgFiles) {
    $outDir = if ($Out) { $Out } else { $svg.DirectoryName }
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
    $png = Join-Path $outDir ($svg.BaseName + '.png')

    $inner = [System.IO.File]::ReadAllText($svg.FullName, [System.Text.Encoding]::UTF8)
    if ($Color -and $Color -match '^#[0-9a-fA-F]{6}$') {
        $inner = $inner -replace 'currentColor', $Color
        $inner = $inner -replace '#000000', $Color
    }
    # 用 data: URI 直接嵌入，省掉相对路径/编码的坑
    $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($inner))
    $padPx = [int][Math]::Round($Size * [Math]::Max(0, [Math]::Min(0.4, $Pad)))
    $box = $Size - 2 * $padPx
    $html = @"
<!doctype html><html><head><meta charset="utf-8"><style>
html,body{margin:0;padding:0;width:${Size}px;height:${Size}px;overflow:hidden;background:$bgCss}
img{display:block;width:${box}px;height:${box}px;margin:${padPx}px}
</style></head><body><img src="data:image/svg+xml;base64,$b64"></body></html>
"@
    $tmpHtml = Join-Path $env:TEMP ('ds-raster-' + [guid]::NewGuid().ToString('N').Substring(0, 10) + '.html')
    [System.IO.File]::WriteAllText($tmpHtml, $html, (New-Object System.Text.UTF8Encoding $true))

    $ud = Join-Path $env:TEMP ('ds-edge-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $uri = ([uri]$tmpHtml).AbsoluteUri
    $edgeArgs = @(
        '--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
        '--hide-scrollbars', '--force-device-scale-factor=1',
        "--user-data-dir=$ud", $bgFlag,
        "--window-size=$Size,$Size",
        "--screenshot=$png",
        $uri
    )
    $proc = Start-Process -FilePath $edge -ArgumentList $edgeArgs -PassThru -Wait -WindowStyle Hidden
    Start-Sleep -Milliseconds 200

    $ok = (Test-Path $png) -and ((Get-Item $png).Length -gt 0)
    if (-not $ok) {
        Write-Warning ('光栅化失败：' + $svg.Name + '（edge exit ' + $proc.ExitCode + '）')
        continue
    }

    $results += [pscustomobject]@{
        svg     = $svg.FullName
        png     = $png
        size    = $Size
        bytes   = (Get-Item $png).Length
        sha256  = (Get-FileHash $png -Algorithm SHA256).Hash.ToLower()
    }
    Write-Host ('[ok] {0} → {1}  {2}px  {3} B' -f $svg.Name, (Split-Path $png -Leaf), $Size, (Get-Item $png).Length)

    Remove-Item $tmpHtml -Force -ErrorAction SilentlyContinue
    Remove-Item $ud -Recurse -Force -ErrorAction SilentlyContinue
}

$results | ConvertTo-Json -Depth 4
