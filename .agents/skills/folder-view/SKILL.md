---
name: folder-view
description: >
  Set Windows Explorer view mode (Large Icons, Details, etc.) for a folder tree by writing
  directly to Shell Bags registry — no GUI, no elevation needed. Use when a user wants to
  set the Explorer view mode for a folder, optionally cascading to all subfolders. Restarts Explorer automatically.
  WHEN: set folder to large icons, force explorer view, set view mode recursively, change folder
  view without GUI, set all subfolders to large icons, fix explorer view, shell bags, folder view
  registry, set C:\Something to large icons.
argument-hint: "-Path <folder> -View <ExtraLargeIcons|LargeIcons|MediumIcons|SmallIcons|List|Details|Tiles|Content> [-PrimeShellBags] [-Recurse] [-Exclude 'name1','name2'] [-DelayMs 300] [-SetGlobalDefault]"
---

# FolderView Skill

## What this repo does

`Set-FolderView.ps1` sets the Windows Explorer view mode for a folder and all its subfolders
by writing directly to the Shell Bags registry (`HKCU\...\Shell\Bags`).

No GUI. No elevation. One command.

---

## The command

```powershell
# Recommended: prime Shell Bags then set view (works for unvisited folders too)
powershell -ExecutionPolicy Bypass -File "C:\Tools\FolderView\Set-FolderView.ps1" `
    -Path "C:\YourFolder" -View LargeIcons -PrimeShellBags

# Fast: update only folders already visited in Explorer (no windows opened)
powershell -ExecutionPolicy Bypass -File "C:\Tools\FolderView\Set-FolderView.ps1" `
    -Path "C:\YourFolder" -View LargeIcons
```

> Replace the script path with the actual install location; resolve it relative to the skill directory if needed.

> **WARNING — do NOT add `-SetGlobalDefault` unless the user explicitly asks to change the view for ALL folders.**
> That flag writes to `AllFolders\Shell` and patches `FolderTypes` in HKCU, which makes the chosen view the Explorer default for every folder that has no per-folder bag yet. To undo it, run `Restore-GlobalDefault.ps1` (see below).

> **Note on unvisited folders:** Explorer creates Shell Bag entries the first time a folder is opened. This script only updates existing entries. Use `-PrimeShellBags` to have Explorer visit every folder first — the script navigates Explorer through the entire tree via COM, waits for bags to be persisted, then updates them all.

---

## Parameters

| Parameter | Required | Default | Description |
|---|---|---|---|
| `-Path` | ✅ | — | Root folder to apply the view to |
| `-View` | | `LargeIcons` | View mode name (see table below) |
| `-Recurse` | | `$true` | Apply to all subfolders |
| `-PrimeShellBags` | | off | Navigate Explorer through every folder first so Explorer creates real Shell Bag entries. Recommended for folders that have never been opened. |
| `-DelayMs` | | `100` | Milliseconds between folder navigations during priming. Increase (e.g. `500`) on slow machines or network drives if Explorer misses folders. |
| `-Exclude` | | `@()` | Folder names to skip (and their entire subtree). Merged with `folderview-exclude.txt` in the root folder. Example: `-Exclude '.venv','node_modules'` |
| `-SetGlobalDefault` | | off | **Side-effect: changes the default view for ALL folders.** Only use when the user explicitly asks for a system-wide default change. |

> **Path constraint:** Only local filesystem paths (e.g. `C:\…`, `I:\…`) are supported. UNC paths are not handled.

> **View validation:** If `-View` is not one of the values in the View modes table, the script aborts before stopping Explorer and prints the list of valid values.

---

## Exclude config file

Place a `folderview-exclude.txt` file in the root `-Path` folder to persistently exclude folder names:

```
# folderview-exclude.txt
# One folder name per line. Folder and all its subfolders are skipped.
# Lines starting with # are comments.

.git
.venv
node_modules
Filer
```

Entries are merged with any `-Exclude` values passed on the command line. Matching is case-insensitive and applies to the folder name at any depth in the tree.

## View modes

| `-View` | Icon size | Explorer name |
|---|---|---|
| `ExtraLargeIcons` | 256 px | Extra large icons |
| `LargeIcons` | 96 px | Large icons |
| `MediumIcons` | 48 px | Medium icons |
| `SmallIcons` | 16 px | Small icons |
| `List` | — | List |
| `Details` | — | Details |
| `Tiles` | — | Tiles |
| `Content` | — | Content |

---

## Restoring the global default

If `-SetGlobalDefault` was used unintentionally and the view changed for all folders, run:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Tools\FolderView\Restore-GlobalDefault.ps1"
```

This removes the `AllFolders\Shell` override and the HKCU `FolderTypes` copy so Explorer
falls back to its built-in defaults. Per-folder bags written by `Set-FolderView.ps1` are
not touched — individual folders keep their assigned view.

---

## Validation

After running, confirm the registry was written correctly:

```powershell
# 1. Find the bag number for your folder from the script's Verbose output
#    e.g. "[bag  79]  C:\MyFolder"

# 2. Read the written values
$slot = 79   # replace with actual slot
$guid = '{5C4F28B5-F869-4E84-8E60-F11DB97C5CC7}'
reg query "HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\$slot\Shell\$guid"
```

Expected for `LargeIcons`:
```
Mode            REG_DWORD    0x1
LogicalViewMode REG_DWORD    0x3
IconSize        REG_DWORD    0x60   (= 96 decimal)
```

Then open the folder in Explorer and visually confirm. See [capture-window.ps1](./scripts/capture-window.ps1)
for a `PrintWindow`-based screenshot that works regardless of window z-order.

---

## How it works internally

Windows Explorer stores per-folder view settings in:
```
HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\<N>\Shell\{GUID}
```

The folder → bag mapping lives in the `BagMRU` tree next to `Bags`:
```
BagMRU\              ← root
  1\                 ← "This PC" node
    0\               ← C:\ drive node  (SHITEMID: 27 bytes, type=0x2F, drive letter at byte[3])
      8\             ← C:\MyFolder     (SHITEMID contains folder name as Unicode)
        NodeSlot=79  ← → Bags\79\Shell\{GUID}
```

The script walks that tree from root → drive → each path component, matching:
- **Drive nodes**: exact binary signature (`byte[2]=0x2F`, `byte[4]=0x3A`)
- **Folder nodes**: Unicode substring match in the SHITEMID blob

**Key gotchas fixed** (documented so the next agent doesn't repeat them):

| Gotcha | Fix |
|---|---|
| `??` null-coalescing not in PS5 | Use `if ($x) { ... }` |
| `Registry::HKCU:\...` is invalid | Use `HKCU:\...` directly |
| Drive SHITEMID length check `== 25` fails | Registry stores SHITEMID + 2-byte PIDL terminator = 27 bytes; check `>= 6` instead |
| ASCII-only search for "C:" matches unrelated giant blobs | Use exact byte-signature check for drive nodes |
| Synthetic ShellBag creation is impossible | Explorer NEVER looks up existing BagMRU entries before creating new ones — it always creates fresh entries on first navigation. Any manually written BagMRU entries are permanently ignored. Use `-PrimeShellBags` instead. |
| `Shell.Application.Navigate2` silently drops fast navigations | Introduce `-DelayMs` between calls; re-acquire the window handle if the window closes mid-run |

---

## Script structure

```
Set-FolderView.ps1
├── param block
├── $VIEW_MAP hashtable                      ← all view mode values
├── Stop-Explorer                            ← stop explorer.exe, return bool
├── Start-Explorer                           ← start explorer.exe
├── Set-BagView(path, lvm, mode, iconSize)   ← write Mode/LogicalViewMode/IconSize
├── Get-DriveNode(key, letter)               ← find drive SHITEMID in BagMRU key
├── Get-SubfolderNode(key, name)             ← find folder SHITEMID by Unicode name
├── Resolve-FolderSlot(path)                 ← walk BagMRU tree → NodeSlot (read-only, no creation)
├── Invoke-ExplorerVisitFolders(folders, ms) ← navigate Explorer via Shell.Application COM
├── Copy-FolderTypeToHkcu(lmPath, cuPath)    ← copy FolderTypes key HKLM→HKCU for -SetGlobalDefault
└── Main block
    ├── Resolve & validate -Path
    ├── Load folderview-exclude.txt, merge with -Exclude
    ├── Collect folders (filtered by exclusions)
    ├── [optional] Invoke-ExplorerVisitFolders  ← -PrimeShellBags
    ├── Stop-Explorer
    ├── [optional] Set AllFolders bag + TopViews ← -SetGlobalDefault
    ├── For each folder: Resolve-FolderSlot → Set-BagView
    └── Start-Explorer + report
```

> **Explorer does not create bags for excluded folders.** The exclusion filter runs before both the visit pass and the registry update pass — excluded folders are never opened and never updated.

> **`Resolve-FolderSlot` is strictly read-only.** It walks the BagMRU tree and returns a NodeSlot only if Explorer has already created the entry. It never fabricates entries. Folders with no bag are reported as "No bag" in the summary.

---

## Files

```
FolderView/
├── Set-FolderView.ps1        ← the script
├── README.md                 ← human quickstart
└── .github/
    └── skills/
        └── folder-view/
            ├── SKILL.md      ← this file
            └── scripts/
                └── capture-window.ps1   ← PrintWindow screenshot helper
```
