<div align="center">

<img src="docs/assets/logos/strata-tokyo-night.svg" alt="Strata logo" width="160">

# Strata

**Navigate every layer.** A fast, keyboard-first file manager for macOS.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)](#requirements)

</div>

Strata combines spatial Miller-column navigation with Icons and List views,
instant fuzzy search, and rich previews. It is a native AppKit app that looks
like the rest of macOS: it follows the system light or dark appearance and
accent color, and uses Quick Look for previews and thumbnails, the system Trash,
Finder-compatible drag and drop and clipboard, window tabs, and mounted drives.

## Contents

- [Features](#features)
- [Requirements](#requirements)
- [Build and install](#build-and-install)
- [Keyboard shortcuts](#keyboard-shortcuts)
- [Settings](#settings)
- [Permissions](#permissions)
- [Development](#development)
- [License](#license)

## Features

- **Three browser modes:** Miller Columns with a live preview column, an Icons
  grid with Quick Look thumbnails, and a sortable List.
- **Keyboard-first control:** arrow and `h` `j` `k` `l` movement, history, a
  typed location bar with folder completion, and an F1 shortcut reference. A
  footer shows the main shortcuts and the clipboard status.
- **Pane filter (⌘F):** case-insensitive matching that tolerates one typo in a
  word of four or more letters, and `*` patterns such as `IMG*.MOV`. It can
  include subfolders.
- **Global search (⌘K):** fuzzy search by name or path across your home folder
  and mounted local drives, with results while the index builds. ⇧⌘K searches
  folders only.
- **Previews:** highlighted source code with line numbers, rendered Markdown,
  folder summaries, and Quick Look for images, PDFs, audio, video, and documents.
- **File operations:** new folder or file, inline rename, copy, cut, paste,
  duplicate, compress to `.zip`, Move to Trash, and permanent delete. Everything
  except permanent delete can be undone. When a name is taken, Strata offers
  Keep Both, Replace, or Skip; Replace moves the old item to the Trash.
- **Sidebar:** places, pinned folders, and mounted drives with eject. Drag
  folders onto Pinned to pin them, and drop files onto any folder.
- **Window tabs** that reopen at launch, Open With, Properties, Open in Terminal,
  and Show in Finder.
- **Network shares:** type `smb://server/share` in the location bar (⌘L).
- **Eleven languages:** English, French, German, Spanish, Japanese, Brazilian
  Portuguese, Korean, Vietnamese, Italian, Russian, and Simplified Chinese.

## Requirements

- macOS 14 Sonoma or newer.
- Xcode 16 or newer to build.

## Build and install

```bash
git clone https://github.com/yarlson/strata.git
cd strata
mise run build                # or: ./macos/scripts/build-app.sh
open target/macos/Strata.app
```

Copy `target/macos/Strata.app` to `/Applications` to install it. The app is
signed ad hoc, not notarized: on another Mac, open it the first time from the
Finder context menu with **Open**.

To open a folder from a terminal, run `open -a Strata ~/Downloads`. Finder also
lists Strata under **Open With** for folders.

## Keyboard shortcuts

| Action | Keys |
| --- | --- |
| Move / extend the selection | ↑ ↓ or `j` `k` / ⇧↑ ⇧↓ |
| Parent column / open folder | ← → or `h` `l` |
| Open | ↩ or ⌘↓ |
| Quick preview | Space or ⌘Y |
| Enclosing folder | ⌫, ⌘↑, or ⌥↑ |
| Back / forward | ⌘[ / ⌘], or ⌥← / ⌥→ |
| Go to a path | ⌘L |
| Search / jump to a folder | ⌘K / ⇧⌘K |
| Filter this pane | ⌘F or `/` |
| New folder / file / folder with selection | ⇧⌘N / ⌥⌘N / ⌃⌘N |
| Rename | F2 or ⌘R |
| Copy / cut / paste | ⌘C / ⌘X / ⌘V |
| Duplicate | ⌘D |
| Copy path | ⌥⌘C or `y` |
| Pin | ⌃⌘T or `p` |
| Move to Trash / delete permanently | ⌘⌫ / ⌥⌘⌫ |
| Properties | ⌘I or ⌥↩ |
| Open in Terminal | ⌥⌘T |
| Columns / Icons / List | ⌘1 / ⌘2 / ⌘3 |
| Hidden files / preview / sidebar | ⇧⌘. / ⇧⌘P / ⌘B |
| Text size | ⌘= / ⌘- / ⌘0 |
| New tab / close tab | ⌘T / ⌘W |
| All shortcuts | F1 |

Letter shortcuts follow the key's Latin label on non-Latin layouts, and digit
shortcuts follow the key's position on the top row.

## Settings

Open **Strata → Settings…** (⌘,):

- **General:** restore open tabs, default view, hidden files, the shortcut
  footer, the preview pane, filter scope, and language.
- **Appearance:** compact or airy density, and text size.
- **Search:** folders that global search skips. A folder name matches at any
  depth; an absolute path skips only that folder. Global search always skips
  `~/Library`.

## Permissions

macOS asks once before Strata opens Desktop, Documents, Downloads, removable
drives, or network volumes. Listing the Trash folder can need Full Disk Access
(**System Settings → Privacy & Security → Full Disk Access**). Without it,
Strata explains how to allow access in place of the listing.

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for the code layout, checks, tests, and
translation rules.

```bash
mise run check                # format lint, tests, and spelling
```

## License

Strata is available under the [MIT License](LICENSE).
