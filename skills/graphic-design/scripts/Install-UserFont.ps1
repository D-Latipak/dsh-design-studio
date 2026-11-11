#requires -Version 5.1
<#
.SYNOPSIS
  平面设计工坊 · 用户级字体安装/卸载（不需要管理员）

.DESCRIPTION
  把下载来的 .ttf / .otf 装进 **当前用户** 的字体目录，并登记到
  HKCU\Software\Microsoft\Windows NT\CurrentVersion\Fonts。
  不写 C:\Windows\Fonts，不碰 HKLM，不要求提权——这是本 agent 唯一允许的"改系统"动作，
  且必须同时满足：许可是 OFL/Apache/MIT 等可商用许可、已写进 designs/assets/manifest.json、已告知用户。

  装完做两件事：AddFontResource 让字体立刻可用；向所有窗口广播 WM_FONTCHANGE，
  让已经跑着的 DesignCraft/PhotoCraft 重新枚举字体（若仍看不到，重开一次引擎进程）。

.PARAMETER Path
  要安装的字体文件（可多个，支持 .ttf / .otf / .ttc）。

.PARAMETER Uninstall
  要卸载的字体文件（给 PATH02 或文件名都行，会去用户字体目录里找）。

.PARAMETER DryRun
  只报告会做什么，不动手。

.EXAMPLE
  .\Install-UserFont.ps1 -Path "designs\assets\fonts\NotoSerifSC[wght].ttf"

.EXAMPLE
  .\Install-UserFont.ps1 -List

.EXAMPLE
  .\Install-UserFont.ps1 -Uninstall "NotoSerifSC[wght].ttf"
#>
[CmdletBinding(DefaultParameterSetName = 'install')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'install', Position = 0)]
    [string[]]$Path,

    [Parameter(Mandatory = $true, ParameterSetName = 'uninstall')]
    [string[]]$Uninstall,

    [Parameter(ParameterSetName = 'list')]
    [switch]$List,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$UserFontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
$RegPath = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
if (-not (Test-Path $UserFontDir)) { New-Item -ItemType Directory -Force -Path $UserFontDir | Out-Null }
if (-not (Test-Path $RegPath)) { New-Item -Path $RegPath -Force | Out-Null }

Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
Add-Type -Namespace DesignStudio -Name NativeFont -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("gdi32.dll", CharSet=System.Runtime.InteropServices.CharSet.Unicode)]
public static extern int AddFontResourceW(string lpFileName);
[System.Runtime.InteropServices.DllImport("gdi32.dll", CharSet=System.Runtime.InteropServices.CharSet.Unicode)]
public static extern bool RemoveFontResourceW(string lpFileName);
[System.Runtime.InteropServices.DllImport("user32.dll", CharSet=System.Runtime.InteropServices.CharSet.Unicode)]
public static extern System.IntPtr SendMessageTimeoutW(System.IntPtr hWnd, uint Msg, System.IntPtr wParam, System.IntPtr lParam, uint fuFlags, uint uTimeout, out System.IntPtr lpdwResult);
'@ -ErrorAction SilentlyContinue

function Send-FontChange {
    try {
        $r = [System.IntPtr]::Zero
        $HWND_BROADCAST = [System.IntPtr]0xffff
        $WM_FONTCHANGE = 0x001D
        $SMTO_ABORTIFHUNG = 0x0002
        [void][DesignStudio.NativeFont]::SendMessageTimeoutW($HWND_BROADCAST, $WM_FONTCHANGE, [System.IntPtr]::Zero, [System.IntPtr]::Zero, $SMTO_ABORTIFHUNG, 1000, [ref]$r)
    }
    catch { Write-Warning ('广播 WM_FONTCHANGE 失败（不影响安装，重启引擎即可）：' + $_.Exception.Message) }
}

function Get-FontFamilies {
    param([string[]]$Files)
    $out = @()
    if (-not ('System.Drawing.Text.PrivateFontCollection' -as [type])) { return $null }
    $pfc = New-Object System.Drawing.Text.PrivateFontCollection
    foreach ($f in $Files) {
        try { $pfc.AddFontFile($f) } catch { Write-Warning ("不是可解析的字体文件：{0} — {1}" -f $f, $_.Exception.Message) }
    }
    foreach ($fam in $pfc.Families) { $out += $fam.Name }
    $pfc.Dispose()
    return $out
}

function Get-InstalledFamilies {
    $col = New-Object System.Drawing.Text.InstalledFontCollection
    return @($col.Families | ForEach-Object { $_.Name })
}

# ---------- -List ----------
if ($List) {
    Write-Host ("用户字体目录：{0}" -f $UserFontDir)
    $files = @(Get-ChildItem $UserFontDir -File -ErrorAction SilentlyContinue)
    if ($files.Count -eq 0) { Write-Host '  （空）' } else { $files | ForEach-Object { Write-Host ('  ' + $_.Name + '  ' + $_.Length + ' B') } }
    Write-Host ''
    Write-Host 'HKCU 字体登记项：'
    $props = Get-ItemProperty $RegPath
    $props.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object { Write-Host ('  {0} = {1}' -f $_.Name, $_.Value) }
    return
}

# ---------- -Uninstall ----------
if ($PSCmdlet.ParameterSetName -eq 'uninstall') {
    foreach ($u in $Uninstall) {
        $file = if (Test-Path $u) { Get-Item $u } else { Get-Item (Join-Path $UserFontDir ([System.IO.Path]::GetFileName($u))) -ErrorAction SilentlyContinue }
        if (-not $file) { Write-Warning ('找不到：' + $u); continue }
        $fams = Get-FontFamilies -Files @($file.FullName)
        if ($DryRun) { Write-Host ('[dry] 将卸载 {0}（家族：{1}）' -f $file.FullName, ($fams -join ', ')); continue }

        [void][DesignStudio.NativeFont]::RemoveFontResourceW($file.FullName)
        $label = $file.BaseName
        $props = Get-ItemProperty $RegPath
        $props.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' -and $_.Value -and ($_.Value -like ('*' + $file.Name)) } | ForEach-Object {
            Remove-ItemProperty -Path $RegPath -Name $_.Name -Force
            Write-Host ('  移除登记项：' + $_.Name)
        }
        Remove-Item $file.FullName -Force
        Write-Host ('[已卸载] {0}' -f $file.Name)
    }
    Send-FontChange
    return
}

# ---------- -Path（安装） ----------
$targets = @()
foreach ($p in $Path) {
    $item = Get-Item -LiteralPath $p -ErrorAction SilentlyContinue
    if (-not $item) { Write-Warning ('找不到文件：' + $p); continue }
    if ($item.Extension -notin '.ttf', '.otf', '.ttc') {
        Write-Warning ('跳过（不是字体文件）：' + $item.Name)
        continue
    }
    $bytes = [System.IO.File]::ReadAllBytes($item.FullName)
    if ($bytes.Length -lt 4) { Write-Warning ('跳过（文件损坏）：' + $item.Name); continue }
    $magic = ($bytes[0..3] | ForEach-Object { '{0:x2}' -f $_ }) -join ''
    if ($magic -in '774f4632', '774f4646') {   # wOF2 / wOFF
        Write-Warning ('跳过（{0} 是网页字体 woff/woff2，DesignCraft 用不了；请下载 ttf/otf）' -f $item.Name)
        continue
    }
    if ($magic -notin '00010000', '4f54544f', '74746366') {
        Write-Warning ('跳过（不是 TrueType/OpenType 骨架，magic={0}）：{1}' -f $magic, $item.Name)
        continue
    }
    $targets += $item
}

if ($targets.Count -eq 0) {
    Write-Warning '没有可安装的字体。'
    return
}

$installedBefore = Get-InstalledFamilies
foreach ($t in $targets) {
    $fams = Get-FontFamilies -Files @($t.FullName)
    $famText = if ($fams) { ($fams -join ' / ') } else { $t.BaseName }
    $already = @($fams | Where-Object { $installedBefore -contains $_ })
    if ($already.Count -gt 0) {
        Write-Host ('[跳过] 家族已在系统中：{0}（{1}）' -f $famText, $t.Name)
        continue
    }
    $destFile = Join-Path $UserFontDir $t.Name
    if ($DryRun) {
        Write-Host ('[dry] 将安装 {0} → {1}（家族：{2}）' -f $t.Name, $destFile, $famText)
        continue
    }
    Copy-Item -LiteralPath $t.FullName -Destination $destFile -Force
    [void][DesignStudio.NativeFont]::AddFontResourceW($destFile)

    $ext = $t.Extension.ToLower()
    $typeLabel = switch ($ext) { '.otf' { '(OpenType)' } '.ttc' { '(TrueType collection)' } default { '(TrueType)' } }
    $regName = ('{0} {1}' -f $t.BaseName, $typeLabel)
    New-ItemProperty -Path $RegPath -Name $regName -Value $destFile -PropertyType String -Force | Out-Null
    Write-Host ('[已安装] {0}  →  {1}' -f $t.Name, $famText)
}

Send-FontChange
Start-Sleep -Milliseconds 300
Write-Host ''
Write-Host '提示：DesignCraft 直接扫字体目录（不读注册表）。若引擎进程已经在跑，执行 mcp__designcraft__execute {"command":"font.reload"} 即可看到新字体，不必重启。'
$after = Get-InstalledFamilies
Write-Host ''
Write-Host '当前可见的字体家族（新装的应出现在这里；DesignCraft font.list 应能查到同名）：'
$targets | ForEach-Object {
    $fams = Get-FontFamilies -Files @($_.FullName)
    if (-not $fams) { $fams = @($_.BaseName) }
    foreach ($f in $fams) {
        $seen = $after -contains $f
        Write-Host ('  {0} {1}' -f $(if ($seen) { '[ok]' } else { '[!] ' }), $f)
    }
}
