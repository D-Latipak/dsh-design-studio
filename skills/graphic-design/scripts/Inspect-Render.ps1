#requires -Version 5.1
<#
Inspect-Render.ps1 - render a design and cut it into inspection crops.

Why: reading one 1080px thumbnail hides detail (1pt misalignment, crowded tracking,
tiny text). This renders at 2-3x and cuts the page into top / middle / bottom bands
plus a downscaled full view, so each read_image call shows a real-size region.

Usage:
  ... -File Inspect-Render.ps1 -Design designs\x\x.designcraft
  ... -Design x.designcraft -Scale 3 -OutDir designs\.inspect
  ... -Png x.png -OutDir designs\.inspect
  ... -Design a.designcraft -Compare b.designcraft     (side-by-side PNG)

Outputs (in -OutDir):
  <name>-full.png     downscaled whole page (max side 1400)
  <name>-top.png      0-33% of the page height, at render scale
  <name>-mid.png      33-66%
  <name>-bottom.png   66-100%
  <name>-compare.png  A | B side by side (with -Compare)
#>
param(
  [string]$Design,
  [string]$Png,
  [int]$Scale = 2,
  [string]$OutDir = '',
  [string]$Compare,
  [string]$Cli = ''
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing | Out-Null

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$mcp = Join-Path $here 'mcp-client.mjs'
$node = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $node) { Write-Error 'node not found on PATH'; exit 2 }
if (-not $Cli) { $Cli = Join-Path $env:LOCALAPPDATA 'Programs\ArtCraft\DesignCraft\designcraft-cli.exe' }
if (-not (Test-Path $Cli)) { Write-Error "designcraft-cli not found: $Cli"; exit 2 }
if (-not $Design -and -not $Png) { Write-Error 'give -Design and/or -Png'; exit 2 }

$target = if ($Design) { $Design } else { $Png }
$name = [System.IO.Path]::GetFileNameWithoutExtension($target)
if (-not $OutDir) { $OutDir = Join-Path (Split-Path -Parent (Resolve-Path $target).Path) '.inspect' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Render-One([string]$designPath, [string]$pngPath) {
  if ($pngPath -and (Test-Path $pngPath)) { return (Resolve-Path $pngPath).Path }
  if (-not $designPath) { throw 'no design to render' }
  $session = @(
    @{ tool = 'open_document'; arguments = @{ path = (Resolve-Path $designPath).Path } },
    @{ tool = 'export_png'; arguments = @{ page = 0; path = $pngPath; scale = $Scale } }
  )
  $sessionPath = Join-Path ([System.IO.Path]::GetTempPath()) ("ir-" + [guid]::NewGuid().ToString('N') + ".json")
  [System.IO.File]::WriteAllText($sessionPath, ($session | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
  $raw = & $node $mcp --session $sessionPath --cli $Cli 2>$null
  if (-not $raw) { throw 'MCP call produced no output' }
  $results = $raw | ConvertFrom-Json
  $bad = $results | Where-Object { -not $_.ok }
  if ($bad) { throw ("render failed: " + ($bad | ConvertTo-Json -Depth 4 -Compress)) }
  if (-not (Test-Path $pngPath)) { throw "render not written: $pngPath" }
  return (Resolve-Path $pngPath).Path
}

function Save-Crop([System.Drawing.Bitmap]$src, [int]$x, [int]$y, [int]$w, [int]$h, [string]$out) {
  $rect = New-Object System.Drawing.Rectangle($x, $y, $w, $h)
  $crop = $src.Clone($rect, $src.PixelFormat)
  try { $crop.Save($out, [System.Drawing.Imaging.ImageFormat]::Png) } finally { $crop.Dispose() }
}

$renderA = Render-One $Design (Join-Path $OutDir "$name-render.png")
$bmp = [System.Drawing.Bitmap]::new($renderA)
$outputs = @()
try {
  $w = $bmp.Width; $h = $bmp.Height
  $fullMax = 1400
  $fscale = [Math]::Min(1.0, $fullMax / [Math]::Max($w, $h))
  $fw = [int][Math]::Round($w * $fscale); $fh = [int][Math]::Round($h * $fscale)
  $full = New-Object System.Drawing.Bitmap($fw, $fh)
  $g = [System.Drawing.Graphics]::FromImage($full)
  try {
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.DrawImage($bmp, 0, 0, $fw, $fh)
  } finally { $g.Dispose() }
  $p = Join-Path $OutDir "$name-full.png"; $full.Save($p, [System.Drawing.Imaging.ImageFormat]::Png); $full.Dispose(); $outputs += $p

  foreach ($band in @(@('top', 0.00, 0.34), @('mid', 0.33, 0.67), @('bottom', 0.66, 1.00))) {
    $y0 = [int][Math]::Floor($h * $band[1]); $y1 = [int][Math]::Ceiling($h * $band[2])
    $bh = [Math]::Min($y1 - $y0, $h - $y0)
    $p = Join-Path $OutDir ("$name-" + $band[0] + ".png")
    Save-Crop $bmp 0 $y0 $w $bh $p
    $outputs += $p
  }
} finally { $bmp.Dispose() }

if ($Compare) {
  $cmpName = [System.IO.Path]::GetFileNameWithoutExtension($Compare)
  $cmpPng = if ($Compare -like '*.png') { $Compare } else { Join-Path $OutDir "$cmpName-render.png" }
  $renderB = Render-One $Compare $cmpPng
  $a = [System.Drawing.Bitmap]::new($renderA)
  $b = [System.Drawing.Bitmap]::new($renderB)
  try {
    $targetH = 1200
    $aw = [int][Math]::Round($a.Width * ($targetH / $a.Height))
    $bw = [int][Math]::Round($b.Width * ($targetH / $b.Height))
    $gap = 48
    $canvas = New-Object System.Drawing.Bitmap(($aw + $gap + $bw), $targetH)
    $g = [System.Drawing.Graphics]::FromImage($canvas)
    try {
      $g.Clear([System.Drawing.Color]::FromArgb(255, 240, 240, 240))
      $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
      $g.DrawImage($a, 0, 0, $aw, $targetH)
      $g.DrawImage($b, ($aw + $gap), 0, $bw, $targetH)
    } finally { $g.Dispose() }
    $p = Join-Path $OutDir "$name-compare.png"
    $canvas.Save($p, [System.Drawing.Imaging.ImageFormat]::Png); $canvas.Dispose()
    $outputs += $p
  } finally { $a.Dispose(); $b.Dispose() }
}

foreach ($o in $outputs) { Write-Host ("[ok] " + $o) }
exit 0
