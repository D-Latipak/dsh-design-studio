<#
.SYNOPSIS
  把多张图片拼成一张带编号的「参考板」（contact sheet），一次 read_image 看全。

.DESCRIPTION
  用于设计前的参考研究：把 6–16 张参考图排成网格，每格下方带序号与标签，
  输出单张 PNG。配合 New-ReferenceBoard.ps1 使用，也可单独用于素材审片。

  只读输入文件，不改动原图；输出目录不存在会自动创建。
  支持 jpg / png / bmp / gif / tif（WebP 需先转码，GDI+ 不支持）。

.PARAMETER Images
  图片路径数组（相对路径按当前目录解析）。

.PARAMETER Out
  输出 PNG 路径。

.PARAMETER Title
  画布顶部标题（可选，中文用 Microsoft YaHei）。

.PARAMETER Cols
  列数，默认 4。

.PARAMETER CellWidth / CellHeight
  单格像素尺寸（图区，不含标签条），默认 420 × 520。

.PARAMETER Labels
  与 Images 等长的标签数组；缺省用文件名。索引号由脚本自动加。

.PARAMETER Background
  画布底色，默认 #1A1A1A。

.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File New-ContactSheet.ps1 `
    -Images @("refs\01.jpg","refs\02.jpg") -Out "refs\board.png" -Title "Swiss reference"

.NOTES
  脚本文件必须保存为 UTF-8 with BOM；否则 PowerShell 5.1 会把中文读成乱码。
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string[]]$Images,
    [Parameter(Mandatory = $true)][string]$Out,
    [string]$Title = '',
    [int]$Cols = 4,
    [int]$CellWidth = 420,
    [int]$CellHeight = 520,
    [string[]]$Labels = @(),
    [string]$Background = '#1A1A1A',
    [int]$LabelHeight = 46
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# 允许从 powershell.exe -File 传参时用 ; 或 | 分隔多值（-File 不支持数组字面量）
function Expand-ListArg([string[]]$values) {
    $out = @()
    foreach ($v in @($values)) {
        if ($null -eq $v) { continue }
        foreach ($part in ($v -split '[;|]+')) {
            $t = $part.Trim()
            if ($t) { $out += $t }
        }
    }
    return $out
}

$Images = @(Expand-ListArg $Images)
$Labels = @(Expand-ListArg $Labels)

# 只给一个目录时，自动收集其中的图片文件
if ($Images.Count -eq 1 -and (Test-Path -LiteralPath $Images[0]) -and (Get-Item -LiteralPath $Images[0]).PSIsContainer) {
    $Images = @(Get-ChildItem -LiteralPath $Images[0] -File | Where-Object {
            $_.Extension.ToLowerInvariant() -in @('.jpg', '.jpeg', '.png', '.bmp', '.gif', '.tif', '.tiff')
        } | Sort-Object Name | ForEach-Object { $_.FullName })
}

function ConvertFrom-HexColor([string]$hex, [System.Drawing.Color]$fallback) {
    if ($hex -match '^#?([0-9a-fA-F]{6})$') {
        $v = [Convert]::ToInt32($Matches[1], 16)
        return [System.Drawing.Color]::FromArgb(255, (($v -shr 16) -band 255), (($v -shr 8) -band 255), ($v -band 255))
    }
    return $fallback
}

function Get-FittingRect([System.Drawing.Image]$img, [int]$boxW, [int]$boxH) {
    $scale = [Math]::Min($boxW / $img.Width, $boxH / $img.Height)
    $w = [int][Math]::Max(1, [Math]::Round($img.Width * $scale))
    $h = [int][Math]::Max(1, [Math]::Round($img.Height * $scale))
    return @{ Width = $w; Height = $h }
}

function New-Font([string[]]$families, [float]$size, [System.Drawing.FontStyle]$style = [System.Drawing.FontStyle]::Regular) {
    foreach ($f in $families) {
        try {
            $font = New-Object System.Drawing.Font($f, $size, $style, [System.Drawing.GraphicsUnit]::Pixel)
            if ($font.Name -eq $f -or $font.FontFamily.Name -eq $f) { return $font }
            $font.Dispose()
        } catch { }
    }
    return New-Object System.Drawing.Font('Arial', $size, $style, [System.Drawing.GraphicsUnit]::Pixel)
}

function Get-TruncatedText([System.Drawing.Graphics]$g, [string]$text, [System.Drawing.Font]$font, [int]$maxWidth) {
    if ([string]::IsNullOrEmpty($text)) { return '' }
    if ($g.MeasureString($text, $font).Width -le $maxWidth) { return $text }
    $lo = 0; $hi = $text.Length
    while ($lo -lt $hi) {
        $mid = [int][Math]::Floor(($lo + $hi + 1) / 2)
        $candidate = $text.Substring(0, $mid) + '…'
        if ($g.MeasureString($candidate, $font).Width -le $maxWidth) { $lo = $mid } else { $hi = $mid - 1 }
    }
    if ($lo -le 0) { return '…' }
    return $text.Substring(0, $lo) + '…'
}

$resolved = @()
foreach ($p in $Images) {
    $full = [System.IO.Path]::GetFullPath($p)
    if (-not (Test-Path -LiteralPath $full)) { throw "图片不存在：$full" }
    $resolved += $full
}
if ($resolved.Count -eq 0) { throw 'Images 为空。' }
if ($Cols -lt 1) { throw 'Cols 必须 >= 1。' }
if ($CellWidth -lt 80 -or $CellHeight -lt 80) { throw 'CellWidth / CellHeight 太小。' }

$outFull = [System.IO.Path]::GetFullPath($Out)
$outDir = [System.IO.Path]::GetDirectoryName($outFull)
if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

$bg = ConvertFrom-HexColor $Background ([System.Drawing.Color]::FromArgb(255, 26, 26, 26))
$cellBg = [System.Drawing.Color]::FromArgb(255, 38, 38, 38)
$gridLine = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
$textColor = [System.Drawing.Color]::FromArgb(255, 235, 235, 235)
$mutedColor = [System.Drawing.Color]::FromArgb(255, 150, 150, 150)

$gutter = 18
$pad = 10
$headerH = if ([string]::IsNullOrWhiteSpace($Title)) { 24 } else { 62 }
$rows = [int][Math]::Ceiling($resolved.Count / [double]$Cols)
$canvasW = $Cols * $CellWidth + ($Cols + 1) * $gutter
$canvasH = $headerH + $rows * ($CellHeight + $LabelHeight) + ($rows + 1) * $gutter

$bmp = New-Object System.Drawing.Bitmap($canvasW, $canvasH)
$graphics = [System.Drawing.Graphics]::FromImage($bmp)
try {
    $graphics.Clear($bg)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

    $titleFont = $null
    $labelFont = $null
    $indexFont = $null
    $titleFont = New-Font @('Microsoft YaHei', 'Segoe UI', 'Arial') 26 ([System.Drawing.FontStyle]::Bold)
    $labelFont = New-Font @('Microsoft YaHei', 'Segoe UI', 'Arial') 14
    $indexFont = New-Font @('Segoe UI', 'Arial') 14 ([System.Drawing.FontStyle]::Bold)

    try {
        if (-not [string]::IsNullOrWhiteSpace($Title)) {
            $titleBrush = New-Object System.Drawing.SolidBrush($textColor)
            try { $graphics.DrawString($Title, $titleFont, $titleBrush, [float]($gutter + 2), [float]16) }
            finally { $titleBrush.Dispose() }
        }

        $loaded = 0
        for ($i = 0; $i -lt $resolved.Count; $i++) {
            $col = $i % $Cols
            $row = [int][Math]::Floor($i / $Cols)
            $x = $gutter + $col * ($CellWidth + $gutter)
            $y = $headerH + $gutter + $row * ($CellHeight + $LabelHeight + $gutter)

            $cellRect = New-Object System.Drawing.Rectangle($x, $y, $CellWidth, $CellHeight)
            $bgBrush = New-Object System.Drawing.SolidBrush($cellBg)
            try { $graphics.FillRectangle($bgBrush, $cellRect) } finally { $bgBrush.Dispose() }
            $pen = New-Object System.Drawing.Pen($gridLine, 1)
            try { $graphics.DrawRectangle($pen, $cellRect) } finally { $pen.Dispose() }

            $label = if ($i -lt $Labels.Count -and -not [string]::IsNullOrWhiteSpace($Labels[$i])) {
                $Labels[$i]
            } else {
                [System.IO.Path]::GetFileName($resolved[$i])
            }

            try {
                $bytes = [System.IO.File]::ReadAllBytes($resolved[$i])
                $ms = New-Object System.IO.MemoryStream(, $bytes)
                $img = [System.Drawing.Image]::FromStream($ms)
                try {
                    $fit = Get-FittingRect $img ($CellWidth - 2 * $pad) ($CellHeight - 2 * $pad)
                    $dx = $x + [int](($CellWidth - $fit.Width) / 2)
                    $dy = $y + [int](($CellHeight - $fit.Height) / 2)
                    $graphics.DrawImage($img, (New-Object System.Drawing.Rectangle($dx, $dy, $fit.Width, $fit.Height)))
                    $loaded++
                } finally {
                    $img.Dispose()
                    $ms.Dispose()
                }
            } catch {
                $missingFont = New-Font @('Segoe UI', 'Arial') 14
                $missingBrush = New-Object System.Drawing.SolidBrush($mutedColor)
                try {
                    $graphics.DrawString('[unreadable]', $missingFont, $missingBrush, [float]($x + $pad), [float]($y + $pad))
                } finally {
                    $missingBrush.Dispose()
                    $missingFont.Dispose()
                }
            }

            $idxText = ('{0:D2}' -f ($i + 1))
            $idxBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 242, 200, 90))
            try { $graphics.DrawString($idxText, $indexFont, $idxBrush, [float]($x + 2), [float]($y + $CellHeight + 12)) }
            finally { $idxBrush.Dispose() }

            $labelText = Get-TruncatedText $graphics $label $labelFont ($CellWidth - 36)
            $labelBrush = New-Object System.Drawing.SolidBrush($textColor)
            try { $graphics.DrawString($labelText, $labelFont, $labelBrush, [float]($x + 28), [float]($y + $CellHeight + 11)) }
            finally { $labelBrush.Dispose() }

            $footerBrush = New-Object System.Drawing.SolidBrush($mutedColor)
            try { $graphics.DrawString(('{0}/{1}' -f ($i + 1), $resolved.Count), $labelFont, $footerBrush, [float]($x + 2), [float]($y + $CellHeight + 30)) }
            finally { $footerBrush.Dispose() }
        }

        $bmp.Save($outFull, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        if ($null -ne $titleFont) { $titleFont.Dispose() }
        if ($null -ne $labelFont) { $labelFont.Dispose() }
        if ($null -ne $indexFont) { $indexFont.Dispose() }
    }
} finally {
    $graphics.Dispose()
    $bmp.Dispose()
}

[pscustomobject]@{
    ok      = $true
    out     = $outFull
    count   = $resolved.Count
    loaded  = $loaded
    columns = $Cols
    rows    = $rows
    width   = $canvasW
    height  = $canvasH
} | ConvertTo-Json -Compress
