# Strata for macOS

`macos/` holds a native macOS version of Strata. It is a separate AppKit app
written in Swift. It does not use GTK, GStreamer, or the Rust code. It keeps
Strata's browsing model, keyboard-first control, themes, font, and translations,
and uses macOS services for the platform work: Quick Look for previews and
thumbnails, the system Trash, Finder-compatible drag and drop and clipboard,
native window tabs, and mounted volumes.

## Requirements

- macOS 14 Sonoma or newer.
- Xcode 16 or newer (Swift 6 toolchain).

## Build and run

```bash
mise run macos-app            # or: ./macos/scripts/build-app.sh
open target/macos/Strata.app
```

The script builds a release binary and writes a signed `Strata.app` to
`target/macos/`. Options:

- `--universal` builds for Apple silicon and Intel in one binary.
- `--debug` builds without optimizations.
- `--output DIR` writes the app to another folder.

To install, copy `Strata.app` to `/Applications`. The bundle is signed ad hoc,
not notarized. A copy downloaded from another Mac needs **Open** from the Finder
context menu the first time.

To open a folder from a terminal, run `open -a Strata ~/Downloads`. Finder also
offers Strata under **Open With** for folders.

## Tests

```bash
mise run macos-test           # or: swift test --package-path macos
```

- `StrataCoreTests` cover the platform-independent rules: filter and typo
  matching, `*` patterns, fuzzy search ranking, numbered names, safe rename,
  copy, move and replace, theme parsing, plural rules, and catalog coverage.
- `StrataTests` drive real browser windows offscreen with synthesized key
  events. They never take keyboard focus, use the system Trash, or touch the
  general clipboard.

Format Swift code with `swift format --in-place --recursive macos/Sources macos/Tests`.
The settings live in `macos/.swift-format`.

## Layout

| Path | Contents |
| --- | --- |
| `macos/Sources/StrataCore` | Foundation-only rules: listing, sorting, filtering, search index, names, file mutations, themes, localization. |
| `macos/Sources/Strata` | The AppKit app: windows, the Columns, Icons, and List modes, sidebar, preview, search, settings, and menus. |
| `macos/Resources/locales` | Translations for macOS-only messages, in all supported languages. |
| `macos/scripts` | Bundle build script and app icon renderer. |

The app reads the shared catalogs in `data/locales`, the theme catalog in
`data/themes/catalog.toml`, and the JetBrains Mono font from `data/fonts`. It
looks up a message in the shared catalogs first, then in the macOS overlay. Add
a macOS-only message to every file in `macos/Resources/locales`. The catalog
coverage test fails when a `tr("…")` message is missing from both catalogs.

## Keyboard

Shortcuts follow the Linux app, with Command in place of Control. A few keys
change to fit macOS:

| Command | Linux | macOS |
| --- | --- | --- |
| Show hidden files | Ctrl+H, Ctrl+. | ⇧⌘. |
| Move to Trash | Delete | ⌘⌫ or ⌦ |
| Delete permanently | Shift+Delete | ⌥⌘⌫ or ⇧⌦ |
| Enclosing folder | Alt+Up, Backspace | ⌘↑, ⌥↑, ⌫ |
| Back / forward | Alt+Left / Alt+Right | ⌘[ / ⌘], or ⌥← / ⌥→ |
| Quick preview | Space | Space or ⌘Y (Quick Look) |
| Properties | Alt+Enter | ⌘I or ⌥↩ |
| Rename | F2, Ctrl+R | F2 or ⌘R |
| Pin | P | P or ⌃⌘T |
| Copy path | Y | Y or ⌥⌘C |

Press F1 or choose **Help → Keyboard shortcuts** for the full list.

## Permissions

macOS asks once before Strata opens Desktop, Documents, Downloads, removable
drives, or network volumes. Listing the Trash folder can need Full Disk Access
(**System Settings → Privacy & Security → Full Disk Access**). Without it,
Strata shows how to allow access in place of the listing.

## Not yet available on macOS

These Linux features have no macOS counterpart yet: 10xer mode, custom actions,
browsing inside archives (Compress creates `.zip` files), custom theme files and
Omarchy theme following, in-app updates, per-folder sort memory, and Strata's
own audio and video player (Quick Look plays media in the preview pane). Linux desktop integration (the file chooser
portal, `FileManager1`, and udiskie unlock) does not apply. Global search
indexes the home folder and mounted local drives, but skips `~/Library`.
Network shares open through macOS: type `smb://server/share` in the location bar
(⌘L) and the mounted share appears under **Devices**.
