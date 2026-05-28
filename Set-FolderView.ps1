<#
.SYNOPSIS
    Set Windows Explorer view mode for a folder and its subfolders.

.DESCRIPTION
    Updates Shell Bag registry entries so Explorer displays folders with the
    requested view (e.g. Large Icons).

    Explorer creates Shell Bag entries the first time you open a folder.
    This script reads and updates those existing entries.  Folders that have
    never been opened have no entries yet; use -PrimeShellBags to navigate
    Explorer through every folder in the tree first, letting Explorer create
    real Shell Bag entries before this script updates them.

    Explorer is stopped before registry writes and restarted after.

.PARAMETER Path
    Root folder to apply the view to.  Example: C:\MyFolder

.PARAMETER View
    One of: ExtraLargeIcons, LargeIcons (default), MediumIcons, SmallIcons,
            List, Details, Tiles, Content

.PARAMETER Recurse
    Apply to all subfolders recursively (default: true).

.PARAMETER PrimeShellBags
    Navigate Explorer through every folder under -Path first so Explorer
    creates real Shell Bag entries.  The script then stops Explorer and
    updates those entries to the requested view.
    Recommended whenever some folders have never been opened in Explorer.

.PARAMETER DelayMs
    Milliseconds to wait between folder navigations when using -PrimeShellBags.
    Default: 300.  Increase on slow machines if Explorer misses some folders.

.PARAMETER Exclude
    Folder names to skip entirely (the folder and all its subfolders).
    Merged with entries from folderview-exclude.txt in the root -Path folder (if present).
    Example: -Exclude 'node_modules','tmp'

.PARAMETER SetGlobalDefault
    Also set the AllFolders Shell Bag and the generic FolderTypes TopViews so
    every folder without its own bag entry uses this view by default.
    WARNING: affects ALL folders system-wide.  To undo, run Restore-GlobalDefault.ps1.

.EXAMPLE
    # Prime Shell Bags then set Large Icons (works for unvisited folders too)
    .\Set-FolderView.ps1 -Path "C:\MyFolder" -View LargeIcons -PrimeShellBags

.EXAMPLE
    # Update only already-visited folders (fast, no Explorer windows opened)
    .\Set-FolderView.ps1 -Path "C:\MyFolder" -View LargeIcons

.EXAMPLE
    # Also apply as system-wide default for all other folders
    .\Set-FolderView.ps1 -Path "C:\MyFolder" -View LargeIcons -PrimeShellBags -SetGlobalDefault
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $Path,

    [ValidateSet('ExtraLargeIcons', 'LargeIcons', 'MediumIcons', 'SmallIcons',
                 'List', 'Details', 'Tiles', 'Content')]
    [string] $View = 'LargeIcons',

    [switch] $Recurse = $true,
    [switch] $PrimeShellBags,
    [int]    $DelayMs = 100,
    [string[]] $Exclude = @(),
    [switch] $SetGlobalDefault
)

Set-StrictMode -Off
$ErrorActionPreference = 'SilentlyContinue'

#region ── Configuration ─────────────────────────────────────────────────────

$BAGMRU = 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\BagMRU'
$BAGS   = 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags'
$GUID   = '{5C4F28B5-F869-4E84-8E60-F11DB97C5CC7}'

# LogicalViewMode, Mode, IconSize
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

function Start-Explorer { Start-Process explorer }

# Writes Mode / LogicalViewMode / IconSize to a Shell Bag registry key.
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

# Searches $parentKey (a BagMRU registry key) for the child entry whose
# SHITEMID encodes the given drive letter (type byte 0x2F).
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

# Searches $parentKey for the child whose SHITEMID contains $folderName as Unicode.
function Get-SubfolderNode ([string]$parentKey, [string]$folderName) {
    $key = Get-Item $parentKey -ErrorAction SilentlyContinue
    if (-not $key) { return $null }
    $pattern = [regex]::Escape($folderName)
    foreach ($name in ($key.GetValueNames() | Where-Object { $_ -match '^\d+$' })) {
        [byte[]]$bytes = $key.GetValue($name)
        if ($bytes.Length -gt 4) {
            $text = [System.Text.Encoding]::Unicode.GetString($bytes)
            if ($text -imatch $pattern) { return "$parentKey\$name" }
        }
    }
    return $null
}

# Resolves the NodeSlot for an EXISTING Shell Bag entry for $folderPath.
# Returns the NodeSlot integer, or $null if no entry exists yet.
# Does NOT create missing entries — Explorer creates Shell Bags, not this script.
function Resolve-FolderSlot ([string]$folderPath) {
    $parts = $folderPath.TrimEnd('\').Split('\')
    $drive = [char]$parts[0][0]

    $rootKey = Get-Item $BAGMRU -ErrorAction SilentlyContinue
    if (-not $rootKey) { return $null }

    $driveNode = $null
    foreach ($child in ($rootKey.GetSubKeyNames() | Where-Object { $_ -match '^\d+$' })) {
        $driveNode = Get-DriveNode "$BAGMRU\$child" $drive
        if ($driveNode) { break }
    }
    if (-not $driveNode) { return $null }

    $current = $driveNode
    for ($i = 1; $i -lt $parts.Length; $i++) {
        $next = Get-SubfolderNode $current $parts[$i]
        if ($next) {
            $current = $next
        } else {
            return $null   # not visited yet; no fabrication
        }
    }

    return Get-ItemPropertyValue $current -Name NodeSlot -ErrorAction SilentlyContinue
}

# Navigates a single Explorer window through every path in $Folders.
# Opens Explorer at $Folders[0] if no window is already open.
# Returns the number of folders successfully visited.
function Invoke-ExplorerVisitFolders ([string[]]$Folders, [int]$DelayMs) {
    if (-not $Folders -or $Folders.Count -eq 0) { return 0 }

    Start-Process explorer.exe "`"$($Folders[0])`""
    Start-Sleep -Seconds 2

    $shell   = New-Object -ComObject Shell.Application
    $visited = 0

    foreach ($folder in $Folders) {
        $window = @($shell.Windows()) |
            Where-Object { $_.FullName -like '*explorer.exe' } |
            Select-Object -First 1

        if ($null -eq $window) {
            Start-Process explorer.exe "`"$folder`""
            Start-Sleep -Seconds 1
            $shell  = New-Object -ComObject Shell.Application
            $window = @($shell.Windows()) |
                Where-Object { $_.FullName -like '*explorer.exe' } |
                Select-Object -First 1
        }

        if ($null -eq $window) {
            Write-Warning "  [visit] Could not obtain Explorer window for: $folder"
            continue
        }

        try {
            $window.Navigate2($folder)
            Start-Sleep -Milliseconds $DelayMs
            $visited++
            Write-Verbose "  [visited]  $folder"
        } catch {
            Write-Warning "  [visit failed]  $folder"
        }
    }

    return $visited
}

# Copies a FolderTypes entry from HKLM to HKCU (via reg export/import) if absent.
function Copy-FolderTypeToHkcu ([string]$lmPath, [string]$cuPath) {
    if (Test-Path $cuPath) { return }
    $tmp = [IO.Path]::GetTempFileName() + '.reg'
    reg export $lmPath $tmp /y 2>$null | Out-Null
    if (-not (Test-Path $tmp)) { return }
    $reg = Get-Content $tmp -Raw
    $reg = $reg -replace 'HKEY_LOCAL_MACHINE', 'HKEY_CURRENT_USER'
    Set-Content $tmp $reg -Encoding Unicode
    reg import $tmp 2>$null | Out-Null
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}

#endregion

#region ── Main ──────────────────────────────────────────────────────────────

$resolved = Resolve-Path $Path -ErrorAction SilentlyContinue
if ($resolved) { $Path = $resolved.Path }
$Path = $Path.TrimEnd('\')

if (-not (Test-Path $Path)) {
    Write-Error "Path not found: $Path"
    exit 1
}

$lvm, $mode, $iconSize = $VIEW_MAP[$View]
[int]$lvm = $lvm; [int]$mode = $mode; [int]$iconSize = $iconSize

# Load exclusions from config file at root path, merged with -Exclude parameter
$configFile = Join-Path $Path 'folderview-exclude.txt'
if (Test-Path $configFile) {
    $fileExcludes = Get-Content $configFile | Where-Object { $_.Trim() -ne '' -and -not $_.TrimStart().StartsWith('#') } | ForEach-Object { $_.Trim() }
    $Exclude = @($Exclude) + @($fileExcludes) | Select-Object -Unique
    Write-Verbose "  [config]  Loaded $(($fileExcludes | Measure-Object).Count) exclusion(s) from $configFile"
}

$folders = [System.Collections.Generic.List[string]]::new()
$folders.Add($Path)
if ($Recurse) {
    Get-ChildItem -Path $Path -Recurse -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object {
            $rel = $_.FullName.Substring($Path.Length).TrimStart('\')
            -not ($rel.Split('\') | Where-Object { $Exclude -icontains $_ })
        } |
        ForEach-Object { $folders.Add($_.FullName) }
}

Write-Host "View   : $View  (LogicalViewMode=$lvm, Mode=$mode, IconSize=$iconSize)"
Write-Host "Path   : $Path"
Write-Host "Exclude: $(if ($Exclude) { $Exclude -join ', ' } else { '(none)' })"
Write-Host "Folders: $($folders.Count)"
Write-Host ''

# ── Step 1 : Prime Shell Bags via Explorer navigation (optional) ──────────────
$visited = 0
if ($PrimeShellBags) {
    Write-Host 'Priming Shell Bags: navigating Explorer through folder tree...'
    $visited = Invoke-ExplorerVisitFolders -Folders $folders.ToArray() -DelayMs $DelayMs
    Write-Host "  Visited: $visited folder(s)"
    Write-Host 'Waiting for Explorer to persist Shell Bags...'
    Start-Sleep -Seconds 2
}

# ── Step 2 : Stop Explorer before writing to the registry ────────────────────
$explorerWasRunning = Stop-Explorer

# ── Step 3 : Optional AllFolders global default ───────────────────────────────
if ($SetGlobalDefault) {
    Write-Host 'Setting AllFolders global default...'
    Set-BagView "$BAGS\AllFolders\Shell" $lvm $mode $iconSize

    $LMFT   = 'HKLM\Software\Microsoft\Windows\CurrentVersion\Explorer\FolderTypes'
    $CUFT   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FolderTypes'
    $genTop = "$CUFT\$GUID\TopViews"

    Copy-FolderTypeToHkcu "$LMFT\$GUID" "$CUFT\$GUID"

    if (Test-Path $genTop) {
        Get-ChildItem $genTop -ErrorAction SilentlyContinue | ForEach-Object {
            Set-ItemProperty $_.PSPath -Name LogicalViewMode -Value $lvm      -Type DWord
            Set-ItemProperty $_.PSPath -Name IconSize        -Value $iconSize -Type DWord
        }
        Write-Host 'AllFolders default view updated.'
    }
}

# ── Step 4 : Update Shell Bag entries ─────────────────────────────────────────
$updated = 0
$noBag   = 0
foreach ($folder in $folders) {
    $slot = Resolve-FolderSlot $folder
    if ($null -ne $slot) {
        Set-BagView "$BAGS\$slot\Shell\$GUID" $lvm $mode $iconSize
        $updated++
        Write-Verbose "  [bag $($slot.ToString().PadLeft(4))]  $folder"
    } else {
        $noBag++
        Write-Verbose "  [no bag]  $folder"
    }
}

# ── Step 5 : Restart Explorer ─────────────────────────────────────────────────
if ($explorerWasRunning -or $PrimeShellBags) { Start-Explorer }

# ── Report ────────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host "Updated : $updated bag(s)"
if ($noBag -gt 0) {
    Write-Host "No bag  : $noBag folder(s) had no Shell Bag entry$(if ($PrimeShellBags) { ' even after priming' } else { ' -- rerun with -PrimeShellBags' })"
}
if ($PrimeShellBags)   { Write-Host "Primed  : $visited folder(s) visited by Explorer" }
if ($SetGlobalDefault) { Write-Host 'Global  : AllFolders default set' }
Write-Host 'Done.'

#endregion
