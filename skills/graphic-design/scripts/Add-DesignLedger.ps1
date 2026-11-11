#requires -Version 5.1
<#
.SYNOPSIS
  向设计外观账本 designs/_ledger.json 追加或更新一条记录。

.DESCRIPTION
  账本文件位于 <designs root>\_ledger.json。designs root 的解析顺序：
  1) -DesignsRoot 指定的目录（相对路径按当前目录解析）；
  2) 当前工作目录下的 designs 目录（不存在则创建）。

  按 -Slug 追加 / 更新；同一 slug 已存在时更新它并移到最近位置，
  未显式传入的字段保留旧值。记录字段：
    { slug, palette, fonts, layoutSkeleton, dominantHue, note, deliveredAt }

  文件缺失时自动创建；损坏时先备份为 _ledger.json.corrupt-<时间戳> 再重建，绝不崩溃。

.PARAMETER Slug
  项目标识（通常与 designs\<slug> 目录同名）。

.PARAMETER Palette
  色板，例如 "#F4EFE6,#2B2F36,#C24B2A"；逗号 / 分号 / 竖线分隔都接受。

.PARAMETER Fonts
  字体，例如 "Noto Serif SC,Inter"。

.PARAMETER LayoutSkeleton
  版式骨架的一句话描述（阅读路径 / 分栏 / 焦点）。

.PARAMETER DominantHue
  主色相，例如 "#C24B2A"。

.PARAMETER Note
  备注（来源、用户选择原话摘要等）。

.PARAMETER DesignsRoot
  designs 根目录；默认是当前工作目录下的 designs。

.PARAMETER Json
  输出机器可读 JSON。

.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\Add-DesignLedger.ps1 `
    -Slug "spring-poster" -Palette "#F4EFE6,#2B2F36,#C24B2A" -Fonts "Noto Serif SC,Inter" `
    -LayoutSkeleton "左对齐单栏，焦点在左上三分点" -DominantHue "#C24B2A" -Note "用户选择：就要暖纸感"

.NOTES
  脚本文件必须保存为 UTF-8 with BOM；否则 PowerShell 5.1 会把中文读成乱码。
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Slug,
  [string[]]$Palette = @(),
  [string[]]$Fonts = @(),
  [string]$LayoutSkeleton = '',
  [string]$DominantHue = '',
  [string]$Note = '',
  [string]$DesignsRoot = '',
  [switch]$Json
)

$ErrorActionPreference = 'Stop'
$script:Utf8Bom = New-Object System.Text.UTF8Encoding($true)
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

function Expand-ListArg {
  param([string[]]$Values)
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($v in @($Values)) {
    if ($null -eq $v) { continue }
    foreach ($part in ([string]$v -split '[,;|]+')) {
      $t = $part.Trim()
      if ($t) { $out.Add($t) }
    }
  }
  return $out.ToArray()
}

function Get-OldArray {
  param($Entry, [string]$Name)
  if ($null -eq $Entry) { return @() }
  $prop = $Entry.PSObject.Properties[$Name]
  if (-not $prop -or $null -eq $prop.Value) { return @() }
  return @($prop.Value)
}

function Get-OldText {
  param($Entry, [string]$Name)
  if ($null -eq $Entry) { return '' }
  $prop = $Entry.PSObject.Properties[$Name]
  if (-not $prop -or $null -eq $prop.Value) { return '' }
  return [string]$prop.Value
}

$Slug = $Slug.Trim()
if (-not $Slug) {
  Write-Error '-Slug 不能为空'
  exit 2
}

$designs = Resolve-DesignsRoot $DesignsRoot
$ledgerPath = Join-Path $designs '_ledger.json'
$entries = Read-LedgerEntries $ledgerPath

$old = $null
for ($i = 0; $i -lt $entries.Count; $i++) {
  if ((Get-OldText $entries[$i] 'slug') -eq $Slug) {
    $old = $entries[$i]
    $entries.RemoveAt($i)
    break
  }
}

if ($PSBoundParameters.ContainsKey('Palette')) {
  $paletteList = @(Expand-ListArg $Palette)
} else {
  $paletteList = @(Get-OldArray $old 'palette')
}
if ($PSBoundParameters.ContainsKey('Fonts')) {
  $fontList = @(Expand-ListArg $Fonts)
} else {
  $fontList = @(Get-OldArray $old 'fonts')
}
$layout = if ($PSBoundParameters.ContainsKey('LayoutSkeleton')) { $LayoutSkeleton } else { Get-OldText $old 'layoutSkeleton' }
$hue = if ($PSBoundParameters.ContainsKey('DominantHue')) { $DominantHue } else { Get-OldText $old 'dominantHue' }
$noteText = if ($PSBoundParameters.ContainsKey('Note')) { $Note } else { Get-OldText $old 'note' }

$entry = [ordered]@{
  slug           = $Slug
  palette        = @($paletteList)
  fonts          = @($fontList)
  layoutSkeleton = $layout
  dominantHue    = $hue
  note           = $noteText
  deliveredAt    = (Get-Date).ToString('o')
}
$entries.Add([pscustomobject]$entry)

$payload = [ordered]@{
  version = 1
  entries = $entries.ToArray()
} | ConvertTo-Json -Depth 8

try {
  [System.IO.File]::WriteAllText($ledgerPath, $payload, $script:Utf8Bom)
} catch {
  Write-Error ("ledger 写入失败: " + $_.Exception.Message)
  exit 1
}

$verb = if ($old) { 'Updated' } else { 'Added' }
if ($Json) {
  [ordered]@{
    action = $verb.ToLowerInvariant()
    ledger = $ledgerPath
    count  = $entries.Count
    entry  = $entry
  } | ConvertTo-Json -Depth 8
  return
}

Write-Output ("{0} slug: {1}" -f $verb, $Slug)
Write-Output ("ledger: {0} ({1} entries)" -f $ledgerPath, $entries.Count)
if ($paletteList.Count -gt 0) { Write-Output ("  palette:        " + ($paletteList -join ', ')) }
if ($fontList.Count -gt 0) { Write-Output ("  fonts:          " + ($fontList -join ', ')) }
if ($layout) { Write-Output ("  layoutSkeleton: " + $layout) }
if ($hue) { Write-Output ("  dominantHue:    " + $hue) }
if ($noteText) { Write-Output ("  note:           " + $noteText) }
Write-Output "next: Get-DesignLedger.ps1 prints the last entries and 'avoid these'."
