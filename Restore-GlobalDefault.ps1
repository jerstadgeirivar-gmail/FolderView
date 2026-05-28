<#
.SYNOPSIS
    Undo the global-default change made by Set-FolderView.ps1 -SetGlobalDefault.

.DESCRIPTION
    Set-FolderView.ps1 -SetGlobalDefault writes to two registry locations that
    affect ALL folders (not just the target path):

        1. HKCU:\...\Shell\Bags\AllFolders\Shell
           (Mode / LogicalViewMode / IconSize)

        2. HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\
           FolderTypes\{5C4F28B5-F869-4E84-8E60-F11DB97C5CC7}
           (TopViews sub-keys copied from HKLM and overridden)

    This script removes both overrides so Explorer falls back to its
    built-in defaults for any folder that has no per-folder bag yet.

    Per-folder bags written for the specific path are NOT touched —
    those folders will keep their assigned view.  To reset individual
    folders too, run Set-FolderView.ps1 with the desired view and
    without -SetGlobalDefault.

.EXAMPLE
    .\Restore-GlobalDefault.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Off
$ErrorActionPreference = 'SilentlyContinue'

$BAGS = 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags'
$CUFT = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FolderTypes'
$GUID = '{5C4F28B5-F869-4E84-8E60-F11DB97C5CC7}'

function Stop-Explorer {
    if (Get-Process explorer -ErrorAction SilentlyContinue) {
        Stop-Process -Name explorer -Force
        Start-Sleep -Milliseconds 800
        return $true
    }
    return $false
}

function Start-Explorer { Start-Process explorer }

$explorerWasRunning = Stop-Explorer

# ── 1. Remove AllFolders\Shell view values ───────────────────────────────────
$allFoldersShell = "$BAGS\AllFolders\Shell"
if (Test-Path $allFoldersShell) {
    Remove-ItemProperty $allFoldersShell -Name Mode            -ErrorAction SilentlyContinue
    Remove-ItemProperty $allFoldersShell -Name LogicalViewMode -ErrorAction SilentlyContinue
    Remove-ItemProperty $allFoldersShell -Name IconSize        -ErrorAction SilentlyContinue
    Write-Host "Cleared  : AllFolders\Shell view settings"
} else {
    Write-Host "Skipped  : AllFolders\Shell not found (already clean)"
}

# ── 2. Remove the HKCU FolderTypes override ──────────────────────────────────
# Set-FolderView.ps1 copies the HKLM FolderTypes key into HKCU and then
# modifies it.  Deleting the HKCU copy makes Explorer fall back to HKLM.
$ftPath = "$CUFT\$GUID"
if (Test-Path $ftPath) {
    Remove-Item $ftPath -Recurse -Force
    Write-Host "Removed  : HKCU FolderTypes override for $GUID"
} else {
    Write-Host "Skipped  : HKCU FolderTypes override not found (already clean)"
}

if ($explorerWasRunning) { Start-Explorer }

Write-Host ""
Write-Host "Done. Explorer will use its built-in default view for unvisited folders."
Write-Host "Folders that were explicitly set by Set-FolderView.ps1 keep their view."
