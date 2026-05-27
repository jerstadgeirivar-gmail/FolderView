<#
.SYNOPSIS
    Set Windows Explorer view mode for a folder and its subfolders.

.DESCRIPTION
    Writes directly to the Shell Bags registry — the same data Explorer writes
    when you manually change a folder's view.  No GUI, no elevation required.

    Explorer is stopped before writing and restarted after so the changes
    take effect immediately.

.PARAMETER Path
    Root folder to apply the view to.  Example: C:\Slett

.PARAMETER View
    One of: ExtraLargeIcons, LargeIcons (default), MediumIcons, SmallIcons,
            List, Details, Tiles, Content

.PARAMETER Recurse
    Apply to all subfolders recursively (default: true).

.PARAMETER SetGlobalDefault
    Also set the AllFolders global default.  Recommended: ensures folders that
    have never been opened in Explorer will also use the chosen view on first visit.

.EXAMPLE
    .\Set-FolderView.ps1 -Path "C:\Slett" -View LargeIcons -SetGlobalDefault
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $Path,

    [ValidateSet('ExtraLargeIcons', 'LargeIcons', 'MediumIcons', 'SmallIcons',
                 'List', 'Details', 'Tiles', 'Content')]
    [string] $View = 'LargeIcons',

    [switch] $Recurse = $true,
    [switch] $SetGlobalDefault
)

Set-StrictMode -Off
$ErrorActionPreference = 'SilentlyContinue'

#region ── Configuration ─────────────────────────────────────────────────────

$BAGMRU  = 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\BagMRU'
$BAGS    = 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags'
$GUID    = '{5C4F28B5-F869-4E84-8E60-F11DB97C5CC7}'

# LogicalViewMode, Mode, IconSize  (values from WinSetView source)
$VIEW_MAP = @{
    ExtraLargeIcons = 3, 1, 256
    LargeIcons      = 3, 1,  96
    MediumIcons     = 3, 1,  48
    SmallIcons      = 3, 1,  16
    List            = 4, 3,   0
    Details         = 1, 4,   0
    Tiles           = 2, 6,  48
    Content         = 5, 8,   0
}

#endregion

#region ── Functions ─────────────────────────────────────────────────────────

# Stops Explorer; returns $true if it was running.
function Stop-Explorer {
    if (Get-Process explorer -ErrorAction SilentlyContinue) {
        Stop-Process -Name explorer -Force
        Start-Sleep -Milliseconds 800
        return $true
    }
    return $false
}

# Starts Explorer.
function Start-Explorer {
    Start-Process explorer
}

# Searches $parentKey (a BagMRU registry key) for the child entry whose
# SHITEMID encodes the given drive letter.
# Drive-root SHITEMIDs: type byte 0x2F at offset 2, drive letter at offset 3, ':' at offset 4.
# Returns the registry key path of the matching child, or $null.
function Get-DriveNode ([string]$parentKey, [char]$driveLetter) {
    $key = Get-Item $parentKey -ErrorAction SilentlyContinue
    if (-not $key) { return $null }

    foreach ($name in ($key.GetValueNames() | Where-Object { $_ -match '^\d+$' })) {
        [byte[]]$bytes = $key.GetValue($name)
        if ($bytes.Length -ge 6 -and
            $bytes[2] -eq 0x2F -and
            $bytes[4] -eq 0x3A -and
            ([char]$bytes[3]) -ieq $driveLetter) {
            return "$parentKey\$name"
        }
    }
    return $null
}

# Searches $parentKey (a BagMRU registry key) for the child entry whose
# SHITEMID contains $folderName as a Unicode substring.
# Returns the registry key path of the matching child, or $null.
function Get-SubfolderNode ([string]$parentKey, [string]$folderName) {
    $key = Get-Item $parentKey -ErrorAction SilentlyContinue
    if (-not $key) { return $null }

    $pattern = [regex]::Escape($folderName)
    foreach ($name in ($key.GetValueNames() | Where-Object { $_ -match '^\d+$' })) {
        [byte[]]$bytes = $key.GetValue($name)
        if ($bytes.Length -gt 4) {
            $text = [System.Text.Encoding]::Unicode.GetString($bytes)
            if ($text -imatch $pattern) {
                return "$parentKey\$name"
            }
        }
    }
    return $null
}

# Resolves a local folder path to its Shell Bag NodeSlot number by walking
# the BagMRU registry tree.  Returns the slot integer, or $null if not found.
#
# Tree layout:  BagMRU\  →  <This PC node>\  →  <C:\ node>\  →  <subfolder nodes>...
function Resolve-FolderSlot ([string]$folderPath) {
    $parts  = $folderPath.TrimEnd('\').Split('\')   # e.g. [ 'C:', 'Slett', 'Sub' ]
    $drive  = [char]$parts[0][0]                    # 'C'

    # Drive nodes live one level below root (usually under the 'This PC' node).
    $driveNode = $null
    $rootKey   = Get-Item $BAGMRU -ErrorAction SilentlyContinue
    if (-not $rootKey) { return $null }

    foreach ($child in ($rootKey.GetSubKeyNames() | Where-Object { $_ -match '^\d+$' })) {
        $driveNode = Get-DriveNode "$BAGMRU\$child" $drive
        if ($driveNode) { break }
    }
    if (-not $driveNode) { return $null }

    # Walk the remaining path components (e.g. 'Slett', 'Sub', ...)
    $current = $driveNode
    for ($i = 1; $i -lt $parts.Length; $i++) {
        $current = Get-SubfolderNode $current $parts[$i]
        if (-not $current) { return $null }
    }

    return Get-ItemPropertyValue $current -Name NodeSlot -ErrorAction SilentlyContinue
}

# Writes Mode, LogicalViewMode, and IconSize to a Shell Bag key path.
function Set-BagView ([string]$bagPath, [int]$lvm, [int]$mode, [int]$iconSize) {
    if (-not (Test-Path $bagPath)) { New-Item -Path $bagPath -Force | Out-Null }
    Set-ItemProperty $bagPath -Name Mode            -Value $mode -Type DWord
    Set-ItemProperty $bagPath -Name LogicalViewMode -Value $lvm  -Type DWord
    if ($lvm -eq 3) {
        Set-ItemProperty $bagPath -Name IconSize    -Value $iconSize -Type DWord
    } else {
        Remove-ItemProperty $bagPath -Name IconSize -ErrorAction SilentlyContinue
    }
}

#endregion

#region ── Main ──────────────────────────────────────────────────────────────

# Validate and normalize path
$resolved = Resolve-Path $Path -ErrorAction SilentlyContinue
if ($resolved) { $Path = $resolved.Path }
$Path = $Path.TrimEnd('\')

if (-not (Test-Path $Path)) {
    Write-Error "Path not found: $Path"
    exit 1
}

$lvm, $mode, $iconSize = $VIEW_MAP[$View]

# Collect folders
$folders = [System.Collections.Generic.List[string]]::new()
$folders.Add($Path)
if ($Recurse) {
    Get-ChildItem -Path $Path -Recurse -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { $folders.Add($_.FullName) }
}

Write-Host "View   : $View  (LogicalViewMode=$lvm, Mode=$mode, IconSize=$iconSize)"
Write-Host "Path   : $Path"
Write-Host "Folders: $($folders.Count)"
Write-Host ""

# Stop Explorer so changes are not overwritten when it exits
$explorerWasRunning = Stop-Explorer

# Apply global AllFolders default (covers folders that have no bag yet)
if ($SetGlobalDefault) {
    Write-Host "Setting AllFolders global default..."
    Set-BagView "$BAGS\AllFolders\Shell" $lvm $mode $iconSize

    # Also update FolderTypes TopViews in HKCU so Explorer uses the correct view
    # when it creates a brand-new bag for a folder it has never visited.
    # Explorer reads HKCU over HKLM; copy from HKLM if the HKCU key doesn't exist yet.
    $LMFT = 'HKLM\Software\Microsoft\Windows\CurrentVersion\Explorer\FolderTypes'
    $CUFT = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FolderTypes'
    # {5C4F28B5-...} = Generic/General Items — used for regular filesystem folders
    $genericFT = "{5C4F28B5-F869-4E84-8E60-F11DB97C5CC7}"
    $topViewsPath = "$CUFT\$genericFT\TopViews"

    if (-not (Test-Path $topViewsPath)) {
        Write-Host "Copying FolderTypes\$genericFT from HKLM to HKCU..."
        $tmp = [System.IO.Path]::GetTempFileName() + '.reg'
        reg export "$LMFT\$genericFT" $tmp /y 2>$null | Out-Null
        $content = Get-Content $tmp -Raw
        $content = $content -replace 'HKEY_LOCAL_MACHINE', 'HKEY_CURRENT_USER'
        Set-Content $tmp $content -Encoding Unicode
        reg import $tmp 2>$null | Out-Null
        Remove-Item $tmp -ErrorAction SilentlyContinue
    }

    if (Test-Path $topViewsPath) {
        Write-Host "Updating FolderTypes TopViews..."
        Get-ChildItem $topViewsPath | ForEach-Object {
            Set-ItemProperty $_.PSPath -Name LogicalViewMode -Value $lvm  -Type DWord
            Set-ItemProperty $_.PSPath -Name IconSize        -Value $iconSize -Type DWord
        }
    }
}

# Update per-folder bags
$updated = 0
$noBag   = 0
foreach ($folder in $folders) {
    $slot = Resolve-FolderSlot $folder
    if ($null -ne $slot) {
        Set-BagView "$BAGS\$slot\Shell\$GUID" $lvm $mode $iconSize
        $updated++
        Write-Verbose "  [bag $($slot.ToString().PadLeft(3))]  $folder"
    } else {
        $noBag++
        Write-Verbose "  [no bag]  $folder"
    }
}

Write-Host "Updated: $updated bag(s)   No bag: $noBag folder(s)"
if ($noBag -gt 0 -and -not $SetGlobalDefault) {
    Write-Host "Tip    : Re-run with -SetGlobalDefault so unvisited folders inherit '$View'."
}

# Restart Explorer
if ($explorerWasRunning) { Start-Explorer }

Write-Host "Done."

#endregion
