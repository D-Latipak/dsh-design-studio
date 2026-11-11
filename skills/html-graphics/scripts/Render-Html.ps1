<#
.SYNOPSIS
    Render an HTML/SVG file to PNG or PDF with the local Chromium/Edge engine.

.DESCRIPTION
    Thin PowerShell wrapper around scripts/render.mjs. Finds Node.js and a
    Chromium-based browser (Edge / Chrome / Playwright cache), renders the file,
    optionally runs the layout audit, and prints the JSON result.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File Render-Html.ps1 `
        -In poster.html -Out poster.png -Width 794 -Height 1123 -Dpi 300 -Audit

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File Render-Html.ps1 `
        -In long.html -Out long.png -Width 1080 -FullPage

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File Render-Html.ps1 `
        -In logo.svg -Out logo.png -Selector svg -Width 512 -Height 512 -Transparent
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$In,
    [Parameter(Mandatory = $true)][string]$Out,
    [int]$Width = 0,
    [int]$Height = 0,
    [ValidateSet('px', 'mm', 'in', 'pt')][string]$Unit = 'px',
    [double]$Scale = 0,
    [int]$Dpi = 0,
    [string]$Selector = '',
    [switch]$Transparent,
    [switch]$Pdf,
    [switch]$FullPage,
    [switch]$Audit,
    [string]$AuditOut = '',
    [int]$Wait = 0,
    [string]$Browser = '',
    [string]$Node = ''
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$renderer = Join-Path $scriptDir 'render.mjs'
if (-not (Test-Path -LiteralPath $renderer)) { throw "renderer missing: $renderer" }

# --- locate node -----------------------------------------------------------
if (-not $Node) {
    $cmd = Get-Command node.exe -ErrorAction SilentlyContinue
    if ($cmd) { $Node = $cmd.Source }
}
if (-not $Node -or -not (Test-Path -LiteralPath $Node)) {
    $candidates = @(
        "$env:ProgramFiles\nodejs\node.exe",
        "$env:LOCALAPPDATA\Programs\nodejs\node.exe",
        "${env:ProgramFiles(x86)}\nodejs\node.exe"
    )
    foreach ($c in $candidates) { if (Test-Path -LiteralPath $c) { $Node = $c; break } }
}
if (-not $Node) { throw 'Node.js not found. Install Node.js or pass -Node <path to node.exe>.' }

# --- validate input --------------------------------------------------------
$inPath = if (Test-Path -LiteralPath $In) { (Resolve-Path -LiteralPath $In).Path } else { $In }
if (-not (Test-Path -LiteralPath $inPath) -and $In -notmatch '^https?://') {
    throw "input not found: $In"
}

$cliArgs = @($renderer, '--in', $inPath, '--out', $Out)
if ($Width -gt 0) { $cliArgs += @('--width', "$Width") }
if ($Height -gt 0) { $cliArgs += @('--height', "$Height") }
if ($Unit -ne 'px') { $cliArgs += @('--unit', $Unit) }
if ($Dpi -gt 0) { $cliArgs += @('--dpi', "$Dpi") }
elseif ($Scale -gt 0) { $cliArgs += @('--scale', "$Scale") }
if ($Selector) { $cliArgs += @('--selector', $Selector) }
if ($Transparent) { $cliArgs += '--transparent' }
if ($Pdf) { $cliArgs += '--pdf' }
if ($FullPage) { $cliArgs += '--full-page' }
if ($Audit -or $AuditOut) { $cliArgs += '--audit' }
if ($AuditOut) { $cliArgs += @('--audit-out', $AuditOut) }
if ($Wait -gt 0) { $cliArgs += @('--wait', "$Wait") }
if ($Browser) { $cliArgs += @('--browser', $Browser) }

$outDir = Split-Path -Parent $Out
if ($outDir -and -not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }

$raw = & $Node @cliArgs 2>&1
$code = $LASTEXITCODE
$raw | ForEach-Object { Write-Output $_ }
if ($code -ne 0) {
    switch ($code) {
        3 { Write-Warning 'No Chromium/Edge browser found. Set $env:DSH_BROWSER or pass -Browser.' }
        5 { Write-Warning 'Layout audit found blocking issues (overflow / clipped text / broken image). See audit above; fix or justify before delivery.' }
        default { Write-Warning "render failed with exit code $code" }
    }
}
exit $code
