# FolderView

Set Windows Explorer's view mode for a folder tree — directly via the registry, no GUI needed.

## Quick start

```powershell
# Recommended: prime Shell Bags then set view (works even for never-opened folders)
.\Set-FolderView.ps1 -Path "C:\MyFolder" -View LargeIcons -PrimeShellBags

# Fast: update only folders already visited in Explorer
.\Set-FolderView.ps1 -Path "C:\MyFolder" -View LargeIcons
```

No elevation required. All registry writes are under `HKCU`.

---

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `-Path` | *(required)* | Root folder to apply the view to |
| `-View` | `LargeIcons` | View mode (see table below) |
| `-Recurse` | `$true` | Apply to all subfolders |
| `-PrimeShellBags` | off | Navigate Explorer through every folder first so Explorer creates real Shell Bag entries, then update them all. **Use this whenever some folders have never been opened in Explorer.** |
| `-DelayMs` | `100` | Milliseconds between folder navigations during priming. Increase on slow machines or network drives (e.g. `-DelayMs 500`). |
| `-Exclude` | `@()` | Folder names to skip entirely (and their entire subtree). Merged with `folderview-exclude.txt` in the root folder. |
| `-SetGlobalDefault` | off | Also set the Windows-wide `AllFolders` default. **Side-effect: affects ALL folders system-wide.** To undo, run `Restore-GlobalDefault.ps1`. |

## View modes

| Name | Icon size |
|---|---|
| `ExtraLargeIcons` | 256 px |
| `LargeIcons` | 96 px |
| `MediumIcons` | 48 px |
| `SmallIcons` | 16 px |
| `List` | — |
| `Details` | — |
| `Tiles` | — |
| `Content` | — |

---

## Excluding folders

Place a `folderview-exclude.txt` file in your target folder to permanently skip certain subfolders:

```
# folderview-exclude.txt
# One folder name per line. Folder and all its subfolders are skipped.
.git
.venv
node_modules
Filer
```

Entries are merged with any `-Exclude` values passed on the command line. Matching is case-insensitive and applies at any depth in the tree.

---

## Undoing a global default change

If `-SetGlobalDefault` was used unintentionally:

```powershell
.\Restore-GlobalDefault.ps1
```

This removes the `AllFolders\Shell` override and the HKCU `FolderTypes` copy. Per-folder bags are not touched.

---

## How it works

Windows Explorer stores per-folder view settings in the Shell Bags registry:

```
HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\<N>\Shell\{GUID}
```

Explorer only creates a bag entry the **first time** a folder is opened. This script walks the `BagMRU` tree to find existing entries and updates `Mode`, `LogicalViewMode`, and `IconSize`.

With `-PrimeShellBags`, the script first opens Explorer and navigates it through every folder in the tree via the `Shell.Application` COM interface — letting Explorer create real bag entries — then stops Explorer and updates them all.

Synthetic bag creation (writing BagMRU entries directly) does **not** work: Explorer always creates fresh entries on first navigation and ignores any pre-existing ones.

---

## Using with GitHub Copilot (AI agent)

This repo ships a [Copilot skill](.agents/skills/folder-view/SKILL.md) that teaches the agent exactly how to run the script, what parameters mean, and how to validate results.

### Setup

1. Clone this repo somewhere on your machine.
2. Open it as a VS Code workspace — Copilot picks up `.agents/skills/` automatically.

### Ask Copilot

> *"Set I:\Bilder\Hmm-Jotta to Large Icons, including all subfolders"*

> *"Force C:\Projects to Details view"*

> *"Change C:\Downloads to Medium Icons, skip node_modules"*

### What the skill provides

| Capability | Detail |
|---|---|
| Command generation | Fills in all parameters correctly |
| View mode reference | All 8 modes with icon sizes |
| Registry validation | Shows which reg keys to inspect to confirm the write |
| Visual verification | Links to [capture-window.ps1](.agents/skills/folder-view/scripts/capture-window.ps1) for a `PrintWindow`-based screenshot |
| Known gotchas | PowerShell 5 quirks, synthetic bag creation impossibility, Navigate2 timing |
