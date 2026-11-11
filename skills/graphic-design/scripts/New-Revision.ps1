#requires -Version 5.1
<#
.SYNOPSIS
  平面设计工坊 · 改稿前新建版本副本（原稿永远不动）

.DESCRIPTION
  用户说「标题再大点」「换个颜色」「重排一版」时，**不许原地改**。
  本脚本把项目文件夹里当前最新的源文件复制成下一个版本（`<slug>-v2.designcraft`、`-v3`…），
  并在 `REVISIONS.md` 里追加一行（谁要求的、改了哪一版、时间、sha256）。
  之后 agent 只打开/编辑/保存**副本**，原稿字节保持不动（收尾用 sha256 复核）。

  为什么不连 PNG/PDF 一起复制：复制过去的会是**上一版的渲染结果**，很容易被当成新稿发出去。
  默认只复制源文件，渲染件由改稿后重新导出生成；真要带旧渲染件加 `-CopyRenders`。

.PARAMETER Project
  项目文件夹（如 `designs\free-asset-demo`），或其中的任意一个设计文件。

.PARAMETER Note
  这一版改了什么（写进 REVISIONS.md）。建议写「用户原话 + 实际改动」。

.PARAMETER Base
  一个文件夹里有多个设计时才需要：传源文件名（可带或不带 `-vN` 后缀）。

.PARAMETER CopyRenders
  连 `-vN.png` / `-vN.pdf` 一起复制（默认不复制，见上）。

.PARAMETER DryRun
  只报告会做什么，不写文件。

.EXAMPLE
  .\New-Revision.ps1 -Project designs\free-asset-demo -Note "标题 150→140pt；信息字号 +0.5pt"

.EXAMPLE
  # 从指定版本再开一版
  .\New-Revision.ps1 -Project designs\shan-jian-ri-luo -Base shan-jian-ri-luo-v2 -Note "换配色"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Project,

    [string]$Note = '未说明',

    [string]$Base = '',

    [switch]$CopyRenders,
    [switch]$DryRun,

    # 改完、导出完之后再跑一次 -Seal：只追加一段「封版核对」（各版 sha256 + 有没有渲染件），不改历史行
    [switch]$Seal
)

$ErrorActionPreference = 'Stop'

$DesignExt = '.designcraft'
$RenderExt = @('.png', '.pdf', '.jpg', '.jpeg', '.tif', '.tiff')

# ---------- 解析项目与基准名 ----------
$item = Get-Item -LiteralPath $Project -ErrorAction SilentlyContinue
if (-not $item) { throw "找不到：$Project" }

if ($item.PSIsContainer) {
    $dir = $item.FullName
    $designs = @(Get-ChildItem $dir -File -Filter "*$DesignExt")
}
else {
    $dir = $item.DirectoryName
    $designs = @($item)
    if (-not $Base) { $Base = ($item.BaseName -replace '-v\d+$', '') }
}
if ($designs.Count -eq 0) { throw "文件夹里没有 $DesignExt 源文件：$dir" }

# 从文件名拆出「基准名 + 版本号」
function Split-Version {
    param([string]$Path)
    $b = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    if ($b -match '^(?<base>.+)-v(?<n>\d+)$') {
        return [pscustomobject]@{ base = $Matches['base']; version = [int]$Matches['n'] }
    }
    return [pscustomobject]@{ base = $b; version = 1 }
}

$parsed = @($designs | ForEach-Object { Split-Version $_.FullName })

if ($Base) {
    $group = @($parsed | Where-Object { $_.base -eq $Base })
    if ($group.Count -eq 0) { throw "找不到基准名 '$Base' 的设计文件（现有：" + (($parsed | ForEach-Object { $_.base } | Sort-Object -Unique) -join ', ') + '）' }
    $baseName = $Base
}
else {
    $groups = @($parsed | Group-Object base)
    if ($groups.Count -gt 1) {
        throw ("这个文件夹里有多个设计，请用 -Base 指定一个：" + (($groups | ForEach-Object { $_.Name }) -join ', '))
    }
    $baseName = $groups[0].Name
    $group = @($parsed | Where-Object { $_.base -eq $baseName })
}

$latest = ($group | Sort-Object version -Descending | Select-Object -First 1).version
$newVersion = $latest + 1

# ---------- -Seal：只追加「封版核对」，不改历史行 ----------
if ($Seal) {
    $revPath = Join-Path $dir 'REVISIONS.md'
    if (-not (Test-Path $revPath)) { throw "没有 $revPath，先正常跑一次生成改稿记录。" }
    $versions = @($group.version | Sort-Object -Unique)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine(('### 封版核对 {0}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm')))
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| 版本 | 源文件 | sha256 | 渲染件 |')
    [void]$sb.AppendLine('|---|---|---|---|')
    foreach ($v in $versions) {
        $design = if ($v -eq 1) { Join-Path $dir "$baseName$DesignExt" } else { Join-Path $dir ('{0}-v{1}{2}' -f $baseName, $v, $DesignExt) }
        if (-not (Test-Path $design)) { continue }
        $h = (Get-FileHash $design -Algorithm SHA256).Hash.ToLower()
        $renders = @()
        foreach ($e in $RenderExt) {
            if (Test-Path ([System.IO.Path]::ChangeExtension($design, $e))) { $renders += $e.TrimStart('.') }
        }
        $renderText = if ($renders.Count -gt 0) { $renders -join ' / ' } else { '—（未导出）' }
        [void]$sb.AppendLine(('| v{0} | `{1}` | `{2}` | {3} |' -f $v, (Split-Path $design -Leaf), $h, $renderText))
    }
    Add-Content -Path $revPath -Value $sb.ToString() -Encoding UTF8
    Write-Host ('[封版核对] 已追加到 {0}' -f $revPath)
    [pscustomobject]@{ sealed = $true; project = $dir; versions = $versions } | ConvertTo-Json -Depth 3
    return
}

# ---------- 选定要复制的文件 ----------
$targets = @(Get-ChildItem $dir -File | Where-Object {
        $p = Split-Version $_.FullName
        $p.base -eq $baseName -and $p.version -eq $latest -and ($_.Extension -eq $DesignExt -or ($CopyRenders -and $_.Extension -in $RenderExt))
    } | Sort-Object Extension)

if (@($targets | Where-Object { $_.Extension -eq $DesignExt }).Count -eq 0) {
    throw "v$latest 没有 $DesignExt 源文件，没法开新版本。"
}

$copies = @()
foreach ($t in $targets) {
    $dst = Join-Path $dir ("{0}-v{1}{2}" -f $baseName, $newVersion, $t.Extension)
    if ((Test-Path $dst) -and -not $DryRun) { throw "目标已存在，停手：$dst" }
    $copies += [pscustomobject]@{ from = $t.FullName; to = $dst; ext = $t.Extension }
    if (-not $DryRun) { Copy-Item -LiteralPath $t.FullName -Destination $dst -Force }
}

# ---------- 记账 ----------
$rev = Join-Path $dir 'REVISIONS.md'
if (-not (Test-Path $rev) -and -not $DryRun) {
    $head = @"
# 改稿记录（REVISIONS）

**原稿永远保留**：无版本后缀的 ``$baseName$DesignExt`` 是初稿，任何改稿都另存为 ``-vN``，
不覆盖它。渲染件（png/pdf）在改稿后重新导出，不复用上一版。

| 版本 | 时间 | 改了什么 | 源文件 |
|---|---|---|---|---|
| v1 | $((Get-Date).ToString('yyyy-MM-dd')) | 初稿 | ``$baseName$DesignExt`` |
"@
    Set-Content -Path $rev -Value $head -Encoding UTF8
}


$newDesign = Join-Path $dir ("{0}-v{1}$DesignExt" -f $baseName, $newVersion)
$row = '| v{0} | {1} | {2} | `{3}` |' -f $newVersion, (Get-Date).ToString('yyyy-MM-dd HH:mm'), ($Note -replace '\|', '/'), (Split-Path $newDesign -Leaf)
if (-not $DryRun) { Add-Content -Path $rev -Value $row -Encoding UTF8 }

# ---------- 输出 ----------
Write-Host ''
Write-Host ("项目：{0}" -f $dir)
Write-Host ("基准：{0}  当前版本：v{1}  →  新版本：v{2}" -f $baseName, $latest, $newVersion)
foreach ($c in $copies) { Write-Host ("  [copy] {0}  →  {1}" -f (Split-Path $c.from -Leaf), (Split-Path $c.to -Leaf)) }
Write-Host ''
Write-Host '接下来（必须按这个顺序）：'
Write-Host ("  1) 打开副本：mcp__designcraft__open_document {{""path"": ""{0}""}}" -f $newDesign)
Write-Host '  2) 只在副本上改；保存用 save_document 不带 path（写回副本），或显式给副本路径'
Write-Host ("  3) 导出新渲染件：export_png / file.exportPdf 的 path 用 {0}-v{1}.png / .pdf" -f $baseName, $newVersion)
Write-Host ("  4) 收尾复核原稿没被动过：Get-FileHash {0}{1}" -f (Join-Path $dir $baseName), $DesignExt)
if (Test-Path $rev) { Write-Host ("  5) 改稿记录：{0}" -f $rev) }
Write-Host ''
[pscustomobject]@{
    project     = $dir
    base        = $baseName
    fromVersion = $latest
    toVersion   = $newVersion
    design      = $newDesign
    copies      = @($copies | ForEach-Object { Split-Path $_.to -Leaf })
} | ConvertTo-Json -Depth 4
