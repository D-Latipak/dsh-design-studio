#requires -Version 5.1
<#
.SYNOPSIS
  读取设计外观记录 designs/_ledger.json，打印最近 N 个交付项目与他们的外观快照（仅作参考，不是限制）。

.DESCRIPTION
  账本文件位于 <designs root>\_ledger.json。designs root 的解析顺序：
  1) -DesignsRoot 指定的目录（相对路径按当前目录解析）；
  2) 当前工作目录下的 designs 目录（不存在则创建）。

  每条记录形如：
    { slug, palette, fonts, layoutSkeleton, dominantHue, note, deliveredAt }

  文件缺失时打印空账本并创建一个空文件；文件损坏时把它备份为
  _ledger.json.corrupt-<时间戳> 后重建，绝不崩溃。

.PARAMETER DesignsRoot
  designs 根目录；默认是当前工作目录下的 designs。

.PARAMETER Last
  显示最近 N 条，默认 5。

.PARAMETER Json
  只输出机器可读 JSON（含 recent 与 recentLooks 参考快照）。

.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\Get-DesignLedger.ps1

.EXAMPLE
  ... -DesignsRoot C:\tmp\designs -Last 3

.NOTES
  脚本文件必须保存为 UTF-8 with BOM；否则 PowerShell 5.1 会把中文读成乱码。
#>
[CmdletBinding()]
param(
  [string]$DesignsRoot = '',
  [int]$Last = 5,
  [switch]$Json
)

$ErrorActionPreference = 'Stop'
$script:Utf8Bom = New-Object System.Text.UTF8Encoding($false)
$script:EmptyLedger = '{"version":1,"entries":[]}'

function Resolve-DesignsRoot {
  param([string]$Root)
  if ($Root) {
    $full = [System.IO.Path]::GetFullPath($Root)
  } else {
    $full = Join-Path (Get-Location).Path 'designs'
  }
  if (-not (Test-Path -LiteralPath $full)) {
    New-Item -ItemType Directory -Path $full -Force | Out-Null
  }
  return $full
}

function Read-LedgerEntries {
  param([string]$Path)
  $entries = New-Object System.Collections.Generic.List[object]
  if (-not (Test-Path -LiteralPath $Path)) { return ,$entries }
  $raw = ''
  try { $raw = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) } catch { return ,$entries }
  if (-not $raw -or -not $raw.Trim()) { return ,$entries }
  try {
    $doc = $raw | ConvertFrom-Json
    $list = $null
    if ($doc -is [System.Array]) {
      $list = $doc
    } elseif ($doc -and ($doc.PSObject.Properties.Name -contains 'entries')) {
      $list = @($doc.entries)
    }
    foreach ($e in @($list)) {
      if ($null -ne $e) { $entries.Add($e) }
    }
  } catch {
    $bak = "$Path.corrupt-" + (Get-Date -Format 'yyyyMMdd-HHmmss')
    try { Move-Item -LiteralPath $Path -Destination $bak -Force } catch { }
    try { [System.IO.File]::WriteAllText($Path, $script:EmptyLedger, $script:Utf8Bom) } catch { }
    Write-Warning "ledger 损坏，已备份到 $bak 并重建空账本。"
  }
  return ,$entries
}

function Get-FieldText {
  param($Entry, [string]$Name)
  if ($null -eq $Entry) { return '' }
  $prop = $Entry.PSObject.Properties[$Name]
  if (-not $prop -or $null -eq $prop.Value) { return '' }
  $v = $prop.Value
  if ($v -is [System.Array]) {
    return (($v | ForEach-Object { [string]$_ } | Where-Object { $_ }) -join ', ')
  }
  return [string]$v
}

$designs = Resolve-DesignsRoot $DesignsRoot
$ledgerPath = Join-Path $designs '_ledger.json'
$entries = Read-LedgerEntries $ledgerPath
if (-not (Test-Path -LiteralPath $ledgerPath)) {
  try { [System.IO.File]::WriteAllText($ledgerPath, $script:EmptyLedger, $script:Utf8Bom) } catch { }
}

if ($Last -lt 1) { $Last = 5 }
$recent = @($entries | Select-Object -Last $Last)

$palettes = New-Object System.Collections.Generic.List[string]
$fonts = New-Object System.Collections.Generic.List[string]
$skeletons = New-Object System.Collections.Generic.List[string]
$hues = New-Object System.Collections.Generic.List[string]
foreach ($e in $recent) {
  $pal = Get-FieldText $e 'palette'
  if ($pal) { $palettes.Add($pal) }
  $fnt = Get-FieldText $e 'fonts'
  if ($fnt) { $fonts.Add($fnt) }
  $sk = Get-FieldText $e 'layoutSkeleton'
  if ($sk) { $skeletons.Add($sk) }
  $hue = Get-FieldText $e 'dominantHue'
  if ($hue) { $hues.Add($hue) }
}
$avoid = [ordered]@{
  note            = 'Reference only. These are the looks of recent deliveries, NOT a ban list: follow the user brief first.'
  palettes        = @($palettes | Select-Object -Unique)
  fonts           = @($fonts | Select-Object -Unique)
  layoutSkeletons = @($skeletons | Select-Object -Unique)
  dominantHues    = @($hues | Select-Object -Unique)
}

if ($Json) {
  $payload = [ordered]@{
    ledger = $ledgerPath
    count  = $entries.Count
    recent = @($recent | ForEach-Object {
        $e = $_
        [ordered]@{
          slug           = (Get-FieldText $e 'slug')
          palette        = @($e.PSObject.Properties['palette'].Value)
          fonts          = @($e.PSObject.Properties['fonts'].Value)
          layoutSkeleton = (Get-FieldText $e 'layoutSkeleton')
          dominantHue    = (Get-FieldText $e 'dominantHue')
          note           = (Get-FieldText $e 'note')
          deliveredAt    = (Get-FieldText $e 'deliveredAt')
        }
      })
    recentLooks = $avoid
  }
  $payload | ConvertTo-Json -Depth 8
  return
}

Write-Output ("Design ledger: " + $ledgerPath)
Write-Output ("entries: {0}; showing last {1}" -f $entries.Count, $recent.Count)
Write-Output ''
if ($recent.Count -eq 0) {
  Write-Output '(empty - no delivered designs recorded yet)'
} else {
  $i = 0
  foreach ($e in $recent) {
    $i++
    Write-Output ("[{0}] {1}   {2}" -f $i, (Get-FieldText $e 'slug'), (Get-FieldText $e 'deliveredAt'))
    $p = Get-FieldText $e 'palette'
    if ($p) { Write-Output ("    palette:        " + $p) }
    $f = Get-FieldText $e 'fonts'
    if ($f) { Write-Output ("    fonts:          " + $f) }
    $sk = Get-FieldText $e 'layoutSkeleton'
    if ($sk) { Write-Output ("    layoutSkeleton: " + $sk) }
    $hue = Get-FieldText $e 'dominantHue'
    if ($hue) { Write-Output ("    dominantHue:    " + $hue) }
    $note = Get-FieldText $e 'note'
    if ($note) { Write-Output ("    note:           " + $note) }
  }
}

Write-Output ''
Write-Output '--- recent looks (reference only - never a restriction; follow the user brief first) ---'
if ($avoid.palettes.Count -eq 0 -and $avoid.fonts.Count -eq 0 -and
  $avoid.layoutSkeletons.Count -eq 0 -and $avoid.dominantHues.Count -eq 0) {
  Write-Output '(nothing recorded in the recent window)'
} else {
  if ($avoid.palettes.Count -gt 0) { Write-Output ("palettes:        " + ($avoid.palettes -join ' | ')) }
  if ($avoid.fonts.Count -gt 0) { Write-Output ("fonts:           " + ($avoid.fonts -join ' | ')) }
  if ($avoid.layoutSkeletons.Count -gt 0) { Write-Output ("layoutSkeletons: " + ($avoid.layoutSkeletons -join ' | ')) }
  if ($avoid.dominantHues.Count -gt 0) { Write-Output ("dominantHues:    " + ($avoid.dominantHues -join ' | ')) }
}
