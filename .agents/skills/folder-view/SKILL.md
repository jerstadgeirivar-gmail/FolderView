---
name: folder-view
description: >
  Set Windows Explorer view mode (Large Icons, Details, etc.) for a folder tree by writing
  directly to Shell Bags registry — no GUI, no elevation needed. Use when a user wants to
  force a specific folder and all its subfolders to a fixed view. Restarts Explorer automatically.
  WHEN: set folder to large icons, force explorer view, set view mode recursively, change folder
  view without GUI, set all subfolders to large icons, fix explorer view, shell bags, folder view
  registry, set C:\Something to large icons.
argument-hint: "-Path <folder> -View <LargeIcons|Details|...> [-SetGlobalDefault]"
---

# FolderView Skill

## What this repo does

`Set-FolderView.ps1` sets the Windows Explorer view mode for a folder and all its subfolders
by writing directly to the Shell Bags registry (`HKCU\...\Shell\Bags`).

No GUI. No elevation. One command.

---

## The command

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Utvikling\Github\FolderView\Set-FolderView.ps1" `
    -Path "C:\YourFolder" -View LargeIcons -SetGlobalDefault
```

Always include **`-SetGlobalDefault`** unless you only want to update folders already visited in Explorer.

---

## Parameters

| Parameter | Required | Default | Description |
|---|---|---|---|
| `-Path` | ✅ | — | Root folder to apply the view to |
| `-View` | | `LargeIcons` | View mode name (see table below) |
| `-Recurse` | | `$true` | Apply to all subfolders |
| `-SetGlobalDefault` | | off | Also set the AllFolders global default |

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

## Validation

After running, confirm the registry was written correctly:

```powershell
# 1. Find the bag number for your folder from the script's Verbose output
#    e.g. "[bag  79]  C:\Slett"

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
      8\             ← C:\Slett        (SHITEMID contains "Slett" as Unicode)
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

---

## Script structure (SOLID)

```
Set-FolderView.ps1
├── param block
├── $VIEW_MAP hashtable          ← all view mode values
├── Stop-Explorer                ← single job: stop, return bool
├── Start-Explorer               ← single job: start
├── Get-DriveNode(key, letter)   ← find C:\ SHITEMID in a BagMRU key
├── Get-SubfolderNode(key, name) ← find folder SHITEMID by Unicode name
├── Resolve-FolderSlot(path)     ← walk BagMRU tree → NodeSlot
├── Set-BagView(path, lvm, mode, iconSize) ← write 3 registry values
└── Main block                   ← linear: collect → stop → write → start
```

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
