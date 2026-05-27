# FolderView

Set Windows Explorer's view mode for a folder tree — directly via the registry, no GUI needed.

## Using with GitHub Copilot (AI agent)

This repo ships a [Copilot skill](.agents/skills/folder-view/SKILL.md) that teaches the agent exactly how to run the script, what parameters mean, and how to validate results.

### Setup

1. Clone this repo somewhere on your machine (e.g. `C:\Tools\FolderView`).
2. In VS Code, add the `.agents` folder to your agent skills path, or open this repo as a workspace — Copilot picks up `.agents/skills/` automatically.

### Ask Copilot

Once the skill is loaded, just describe what you want in plain English:

> *"Set C:\Photos to Large Icons view, including all subfolders"*

> *"Force C:\Projects to Details view and make it the global default"*

> *"Change C:\Downloads to Medium Icons"*

Copilot will generate the exact `Set-FolderView.ps1` command, explain what it does, and offer to run it in the terminal.

### What the skill provides

| Capability | Detail |
|---|---|
| Command generation | Fills in `-Path`, `-View`, `-Recurse`, `-SetGlobalDefault` correctly |
| View mode reference | All 8 modes with icon sizes |
| Registry validation | Shows which reg keys to inspect to confirm the write |
| Visual verification | Links to [capture-window.ps1](.agents/skills/folder-view/scripts/capture-window.ps1) for a `PrintWindow`-based screenshot |
| Known gotchas | PowerShell 5 / registry path quirks documented so the agent doesn't repeat mistakes |

---

## Usage

```powershell
powershell -ExecutionPolicy Bypass -File Set-FolderView.ps1 -Path "C:\MyFolder" -View LargeIcons -SetGlobalDefault
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
