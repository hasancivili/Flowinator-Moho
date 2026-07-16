# Flowinator

Flowinator is a local-first production management tool for Moho Pro. It runs inside Moho as a Lua menu script and provides a simple project, asset, shot, workfile, version, and publish workflow without a database or cloud dependency.

The project is open source and licensed under the GNU General Public License v3.0.

## Purpose

Flowinator is designed to keep small and medium Moho productions organized with a predictable folder structure, JSON metadata, local users, versioned workfiles, and Live Publish files that can be imported or referenced in scenes.

It is intentionally lightweight. The goal is a practical production MVP that can be extended later without locking project data into a proprietary service.

## Features

- Runs from Moho's `Scripts` menu.
- English-only native Moho UI.
- Local project creation and project reopening.
- JSON metadata stored separately from `.moho` workfiles.
- Local user login, logout, add, and delete.
- Asset and shot browsing.
- Custom asset types, sequences, variants, work types, and work items.
- Numbered workfile versions that are never overwritten.
- Numbered publish versions.
- Stable Live Publish file for the latest publish.
- Import Live and Reference Live actions.
- Relative project paths for shared/network project locations.

## Installation

1. Download or clone this repository.
2. Open Moho Pro.
3. Go to Moho's script installation command.
4. Select this repository's root `Flowinator` folder.
5. Restart Moho if needed.
6. Launch Flowinator from:

```text
Scripts > Flowinator > Flowinator
```

The folder selected in Moho must be the repository root:

```text
your-cloned-Flowinator-folder/
```

It contains the required Moho script structure:

```text
menu/
  Flowinator.lua
ScriptResources/
  Flowinator/
    flowinator/
    preview_cache/
```

## Compatibility

Flowinator is currently developed for **Moho Pro 14.x on Windows and macOS**.

- **Windows:** Supported. Project, asset, shot, version, publish, Live Publish, preview, and file-management workflows are intended for Windows installations of Moho Pro 14.x.
- **macOS:** Supported by the same Lua workflow. File and folder operations use macOS shell commands, and preview resizing uses the built-in `sips` utility instead of Windows PowerShell. A physical macOS/Moho test is still recommended before using it on an active production.
- **Moho versions:** Moho Pro **14.x** is the supported target. Earlier releases have not been validated and may differ in Lua UI or document APIs. Later releases should be checked with a test project before production use.

Use the same shared project root on every workstation. Flowinator stores project-relative metadata paths so Windows drive letters and macOS mount paths can resolve to the same project structure.

## Project Structure

When a new production project is created, Flowinator creates a local project structure similar to:

```text
00_Pipeline/
  Metadata/
  Users/
  Config/
01_Assets/
  Characters/
  Props/
  Environments/
02_Scenes/
03_Renders/
04_Resources/
```

`00_Pipeline` is the project metadata folder and is kept separate from Moho workfiles.

## Basic Workflow

1. Create or select a project.
2. Log in with a local project user.
3. Create asset or shot data.
4. Create a workfile.
5. Save new numbered versions during production.
6. Publish when a version is ready for downstream use.
7. Use `Import Live` or `Reference Live` to bring the latest published version into another scene.

## Development

Flowinator is written in Lua for Moho's scripting environment. The code is kept modular:

- `ui.lua` - Moho UI and user actions
- `project.lua` - project creation and recent project state
- `users.lua` - local user metadata
- `assets.lua` - asset metadata and hierarchy
- `shots.lua` - shot metadata and hierarchy
- `versions.lua` - workfile, publish, Live Publish, preview, load/import logic
- `metadata.lua` - JSON file read/write helpers
- `paths.lua` - path and file helpers
- `json.lua` - local JSON encoder/decoder

No database or cloud service is required.

## License

Flowinator is free software licensed under the GNU General Public License v3.0.

See [LICENSE](LICENSE) for the full license text.
