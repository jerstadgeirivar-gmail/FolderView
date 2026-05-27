# FolderView

Set Windows Explorer's view mode for a folder tree — directly via the registry, no GUI needed.

## Usage

```powershell
powershell -ExecutionPolicy Bypass -File Set-FolderView.ps1 -Path "C:\Slett" -View LargeIcons -SetGlobalDefault
```

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `-Path` | *(required)* | Root folder to apply the view to |
| `-View` | `LargeIcons` | View mode (see below) |
| `-Recurse` | `$true` | Apply to all subfolders |
| `-SetGlobalDefault` | off | Also set the Windows-wide AllFolders default |

**`-SetGlobalDefault` is recommended** — it covers folders you've never opened in Explorer before, so they also show the right view on first visit.

## View modes

| Name | Icons |
|---|---|
| `ExtraLargeIcons` | 256 px |
| `LargeIcons` | 96 px |
| `MediumIcons` | 48 px |
| `SmallIcons` | 16 px |
| `List` | — |
| `Details` | — |
| `Tiles` | — |
| `Content` | — |

## How it works

Windows Explorer stores per-folder view settings in the Shell Bags registry:

```
HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\<N>\Shell\{GUID}
```

The script:

1. Stops Explorer
2. Optionally writes the `AllFolders` global default
3. Walks the `BagMRU` tree to find the bag number for each folder
4. Writes `Mode`, `LogicalViewMode`, `IconSize` to each bag
5. Restarts Explorer

No elevation required (all writes are under `HKCU`).
