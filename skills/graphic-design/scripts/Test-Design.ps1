#requires -Version 5.1
<#
Test-Design.ps1 - automated design QA for DesignCraft documents.

Checks (structural, from inspect_document):
  * text overflow (overset)
  * text outside the page / inside the 3mm safe inset
  * graphic items completely off-canvas
  * empty text frames
  * overlapping text frames
Checks (pixel, from a 2x render):
  * text frames whose area has almost no luminance variation -> text likely invisible

This script checks hard defects only. It never judges style: palette size, item count,
centred vs left-aligned, ALL-CAPS labels, numbering, or any other visual choice is the
designer's (or the user's) call, not an error.

Usage:
  powershell -NoProfile -ExecutionPolicy Bypass -File Test-Design.ps1 -Design designs\x\x.designcraft
  ... -Design x.designcraft -Png x.png      (reuse an existing render)
  ... -Design x.designcraft -Json           (machine-readable only)
  ... -Strict                               (warnings fail too)

Exit code: 0 = pass, 1 = errors (or warnings with -Strict), 2 = could not run.
#>
param(
  [string]$Design,
  [string]$Png,
  [double]$SafeInset = 8.5,
  [int]$Scale = 2,
  [switch]$Json,
  [switch]$Strict,
  [string]$Cli = ''
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing | Out-Null

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$mcp = Join-Path $here 'mcp-client.mjs'
$node = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $node) { Write-Error 'node not found on PATH'; exit 2 }
if (-not (Test-Path $mcp)) { Write-Error "missing helper: $mcp"; exit 2 }
if (-not $Cli) {
  $Cli = Join-Path $env:LOCALAPPDATA 'Programs\ArtCraft\DesignCraft\designcraft-cli.exe'
}
if (-not (Test-Path $Cli)) { Write-Error "designcraft-cli not found: $Cli"; exit 2 }
if (-not $Design -and -not $Png) { Write-Error 'give -Design and/or -Png'; exit 2 }

$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$metrics = [ordered]@{}

$inspect = $null
$renderPath = $Png
$tmpPng = $null

if ($Design) {
  if (-not (Test-Path $Design)) { Write-Error "no such design: $Design"; exit 2 }
  $tmpPng = Join-Path ([System.IO.Path]::GetTempPath()) ("qa-" + [guid]::NewGuid().ToString('N') + ".png")
  $session = @(
    @{ tool = 'open_document'; arguments = @{ path = (Resolve-Path $Design).Path } },
    @{ tool = 'inspect_document'; arguments = @{} }
  )
  if (-not $renderPath) {
    $session += @{ tool = 'export_png'; arguments = @{ page = 0; path = $tmpPng; scale = $Scale } }
  }
  $sessionPath = Join-Path ([System.IO.Path]::GetTempPath()) ("qa-" + [guid]::NewGuid().ToString('N') + ".json")
  [System.IO.File]::WriteAllText($sessionPath, ($session | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))

  $raw = & $node $mcp --session $sessionPath --cli $Cli 2>$null
  if (-not $raw) { Write-Error 'MCP call produced no output'; exit 2 }
  $results = $raw | ConvertFrom-Json
  $open = $results | Where-Object { $_.tool -eq 'open_document' }
  if (-not $open.ok) { Write-Error ("open_document failed: " + $open.error + ($open.result | ConvertTo-Json -Depth 4 -Compress)); exit 2 }
  $insp = $results | Where-Object { $_.tool -eq 'inspect_document' }
  $inspect = $insp.result.content[0].text | ConvertFrom-Json
  if (-not $renderPath) { $renderPath = $tmpPng }
}

if (-not (Test-Path $renderPath)) { Write-Error "render not found: $renderPath"; exit 2 }

# ---------- structural checks ----------
if ($inspect) {
  $pw = [double]$inspect.settings.pageWidth
  $ph = [double]$inspect.settings.pageHeight
  if ($inspect.settings.facingPages) { $pw = $pw * 2 }
  $metrics.pageWidth = $pw
  $metrics.pageHeight = $ph
  $metrics.intent = $inspect.settings.intent

  $stories = @{}
  foreach ($s in @($inspect.stories)) { if ($s) { $stories[[string]$s.id] = $s } }

  $items = @()
  foreach ($sp in @($inspect.spreads)) { foreach ($it in @($sp.items)) { $items += $it } }
  $metrics.items = $items.Count

  # 只统计“设计师自己加的”色板：内置默认色（[None]/[Paper]/C=… M=…）不算
  $sw = @($inspect.swatches | Where-Object { $_ -and $_ -notlike '`[*' -and $_ -notmatch '^[CRGKB]=\d' })
  $metrics.swatches = $sw.Count
  # Palette size and item count are design decisions, not defects: metrics only, no warnings.

  $textRects = @()
  foreach ($it in $items) {
    $b = @($it.bounds)
    if ($b.Count -ne 4) { continue }
    $x0 = [double]$b[0]; $y0 = [double]$b[1]; $x1 = [double]$b[2]; $y1 = [double]$b[3]
    $kind = [string]$it.kind

    if ($x1 -lt 0 -or $y1 -lt 0 -or $x0 -gt $pw -or $y0 -gt $ph) {
      $errors.Add(("item {0} ({1}) is entirely off-canvas: [{2},{3},{4},{5}]" -f $it.id, $kind, $x0, $y0, $x1, $y1))
      continue
    }

    if ($kind -eq '<text frame>') {
      $textRects += ,@($x0, $y0, $x1, $y1, $it.story, $it.id)
      if ($it.story -ne $null) {
        $st = $stories[[string]$it.story]
        if ($st) {
          if ($st.overset -eq $true) {
            $errors.Add(("text overflow (overset) in frame {0} story {1}: {2}" -f $it.id, $it.story, $st.preview))
          }
          if ([int]$st.length -le 0) { $warnings.Add(("empty text frame {0}" -f $it.id)) }
        }
      }
      if ($x0 -lt $SafeInset -or $y0 -lt $SafeInset -or $x1 -gt ($pw - $SafeInset) -or $y1 -gt ($ph - $SafeInset)) {
        if ($x0 -lt 0 -or $y0 -lt 0 -or $x1 -gt $pw -or $y1 -gt $ph) {
          $errors.Add(("text frame {0} is outside the page: [{1},{2},{3},{4}]" -f $it.id, $x0, $y0, $x1, $y1))
        } else {
          $warnings.Add(("text frame {0} is inside the {1}pt safe inset: [{2},{3},{4},{5}]" -f $it.id, $SafeInset, $x0, $y0, $x1, $y1))
        }
      }
    }
  }

  for ($i = 0; $i -lt $textRects.Count; $i++) {
    for ($j = $i + 1; $j -lt $textRects.Count; $j++) {
      $a = $textRects[$i]; $b = $textRects[$j]
      $ox = [Math]::Max(0, [Math]::Min($a[2], $b[2]) - [Math]::Max($a[0], $b[0]))
      $oy = [Math]::Max(0, [Math]::Min($a[3], $b[3]) - [Math]::Max($a[1], $b[1]))
      $inter = $ox * $oy
      if ($inter -le 0) { continue }
      $areaA = ($a[2] - $a[0]) * ($a[3] - $a[1])
      $areaB = ($b[2] - $b[0]) * ($b[3] - $b[1])
      $small = [Math]::Max(1, [Math]::Min($areaA, $areaB))
      if (($inter / $small) -gt 0.35) {
        $pct = [int][Math]::Round(100.0 * $inter / $small)
        $warnings.Add("text frames " + $a[5] + " and " + $b[5] + " overlap by " + $pct + "%")
      }
    }
  }

  # ---------- pixel contrast proxy ----------
  $bmp = [System.Drawing.Bitmap]::new((Resolve-Path $renderPath).Path)
  try {
    $k = $bmp.Width / $pw
    foreach ($r in $textRects) {
      $x0 = [int][Math]::Floor($r[0] * $k) + 2
      $y0 = [int][Math]::Floor($r[1] * $k) + 2
      $x1 = [int][Math]::Ceiling($r[2] * $k) - 2
      $y1 = [int][Math]::Ceiling($r[3] * $k) - 2
      if ($x0 -lt 0) { $x0 = 0 }
      if ($y0 -lt 0) { $y0 = 0 }
      if ($x1 -ge $bmp.Width) { $x1 = $bmp.Width - 1 }
      if ($y1 -ge $bmp.Height) { $y1 = $bmp.Height - 1 }
      if ($x1 -le $x0 -or $y1 -le $y0) { continue }
      # 用亮度直方图算 5%-95% 分位差：小字号文字占比低，std 会偏小误判；
      # 分位差对“稀疏但高对比”的字更稳，对“同色字”则接近 0。固定 256 桶，不做动态分配。
      $hist = @(0) * 256
      $total = 0
      for ($yy = $y0; $yy -le $y1; $yy += 3) {
        for ($xx = $x0; $xx -le $x1; $xx += 3) {
          $pix = $bmp.GetPixel($xx, $yy)
          $lum = [int](0.2126 * $pix.R + 0.7152 * $pix.G + 0.0722 * $pix.B)
          if ($lum -lt 0) { $lum = 0 }
          if ($lum -gt 255) { $lum = 255 }
          $hist[$lum] = $hist[$lum] + 1
          $total++
        }
      }
      if ($total -lt 30) { continue }
      $lo = [int]($total * 0.01)
      $hi = [int]($total * 0.99)
      if ($lo -lt 1) { $lo = 1 }
      if ($hi -ge $total) { $hi = $total - 1 }
      $p05 = 0
      $p95 = 0
      $acc = 0
      $got05 = $false
      for ($bidx = 0; $bidx -lt 256; $bidx++) {
        $acc += $hist[$bidx]
        if (-not $got05 -and $acc -ge $lo) { $p05 = $bidx; $got05 = $true }
        if ($acc -ge $hi) { $p95 = $bidx; break }
      }
      $contrast = $p95 - $p05
      $metrics["contrast_$($r[5])"] = [Math]::Round($contrast, 1)
      if ($contrast -lt 25) {
        # Not an error: a deliberately low-contrast treatment is a style choice. Report it so the
        # designer can confirm the user asked for it, then keep going.
        $warnings.Add(("text frame {0} has almost no contrast against its background (p99-p1 = {1:N1} < 25): if the user did not ask for a low-contrast effect, add a scrim or change colour" -f $r[5], $contrast))
      }
    }
  } finally {
    $bmp.Dispose()
  }
}

if ($tmpPng -and (Test-Path $tmpPng)) { Remove-Item $tmpPng -Force -ErrorAction SilentlyContinue }

$result = [ordered]@{
  pass     = ($errors.Count -eq 0) -and (-not ($Strict -and $warnings.Count -gt 0))
  design   = $Design
  render   = $renderPath
  errors   = @($errors)
  warnings = @($warnings)
  metrics  = $metrics
}

if ($Json) {
  $result | ConvertTo-Json -Depth 6
} else {
  foreach ($e in $errors) { Write-Host ("ERROR   " + $e) }
  foreach ($w in $warnings) { Write-Host ("WARN    " + $w) }
  Write-Host ("--- {0} errors, {1} warnings, {2} items, out={3}" -f $errors.Count, $warnings.Count, $metrics.items, $renderPath)
  if ($result.pass) { Write-Host 'PASS' } else { Write-Host 'FAIL' }
}

if ($result.pass) { exit 0 } else { exit 1 }
