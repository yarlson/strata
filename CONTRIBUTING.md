# Contributing to Strata

Thanks for helping build Strata. The project is early, so discuss large changes in an issue before investing in an implementation.

## Development setup

You need macOS 14 or newer and Xcode 16 or newer (the Swift 6 toolchain).
Install [mise](https://mise.jdx.dev), then install the pinned spelling checker:

```bash
mise install
```

Build a debug app and open it:

```bash
mise run dev
```

`mise run build` writes the release app to `target/macos/Strata.app`. The
underlying script, `macos/scripts/build-app.sh`, also accepts `--universal`
(Apple silicon and Intel) and `--output DIR`.

Project coding-agent skills are listed in `skills-lock.json`. After cloning,
restore them into the gitignored `.agents/` directory (requires Node.js for
`npx`):

```bash
npx skills experimental_install
```

Commit `skills-lock.json` when adding or updating skills with `npx skills add`
or `npx skills update`. Do not commit `.agents/`.

## Code layout

| Path | Contents |
| --- | --- |
| `macos/Sources/StrataCore` | Foundation-only rules: listing, sorting, filtering, the search index, names, file mutations, and localization. |
| `macos/Sources/Strata` | The AppKit app: windows, the Columns, Icons, and List modes, sidebar, preview, search, settings, and menus. |
| `macos/Tests` | `StrataCoreTests` for the rules and `StrataTests` for app behavior. |
| `macos/Resources` | Translations and the app icon source. |
| `macos/scripts` | The bundle build script and the app icon renderer. |

## Branching and pull requests

All changes to `main` go through a pull request. The normal process is:

1. Create or select a GitHub issue and assign it before starting work.
2. Update local `main`, then create a branch from it.
3. Name the branch `<type>/<issue-number>-<short-kebab-description>`, such as `feat/6-sandbox-previews` or `fix/42-preview-timeout`.
4. Make focused Conventional Commits and push the branch.
5. Open a pull request that references the issue.
6. The maintainer tests the pull request before it is merged. Do not push directly to `main`.

Use the Conventional Commit form for commit messages and pull request titles:

```text
<type>(optional-scope): <imperative description>
```

Common types are `feat`, `fix`, `docs`, `refactor`, `test`, `perf`, `build`, `ci`, and `chore`. Examples:

```text
feat(preview): render HTML files
fix(navigation): preserve selection after reload
```

Use `!` after the type or scope and add a `BREAKING CHANGE:` footer when a change is incompatible. Keep unrelated changes in separate commits.

Commits must be authored by the contributor submitting them. Do not submit
commits authored or co-authored by an AI coding agent. If an agent created
commits, remove them and recreate the changes and commits as your own work under
your own identity before opening or updating the pull request.

## Required checks

Before opening a pull request:

```bash
mise run check
```

This runs:

- `swift format lint --strict` with the settings in `macos/.swift-format`
- `swift test --package-path macos`
- `typos` for spelling

Format Swift code with
`swift format --in-place --recursive macos/Sources macos/Tests`.

## Tests

`StrataCoreTests` cover filtering and typo matching, `*` patterns, fuzzy search
ranking, numbered names, safe rename, copy, move and replace,
plural rules, and catalog coverage.

`StrataTests` open real browser windows offscreen and send them synthesized key
events. Keep app tests in that style: never order a window front, take keyboard
focus, use the general pasteboard, or move files to the user's Trash. Use a
private `NSPasteboard` and the stand-in Trash that `FileMutationsTests` shows.

## Translations

Strata ships in English, French, German, Spanish, Japanese, Brazilian
Portuguese, Korean, Vietnamese, Italian, Russian, and Simplified Chinese.
Messages are English-keyed JSON catalogs in `macos/Resources/locales`, one file
per language, plus `counts.json` for plural forms. Add every new message to all
eleven files in the same change, with the same `%{placeholders}`. The catalog
coverage test fails when a `tr("…")` message has no entry.

## Engineering expectations

- Keep filesystem, search, and preview work off the main thread.
- Make asynchronous work cancellable or reject stale results.
- Never overwrite a user's file silently. Route file changes through
  `FileMutations` and `FileOperationCenter`.
- Put rules that do not need AppKit in `StrataCore`, where they are testable.
- Add an abstraction only for real variation, isolation, or testability.
- Add focused tests for state transitions and filesystem edge cases.
- Preserve licensing and attribution for every new asset and dependency.

Track planned work in GitHub issues rather than committed task checklists.

For user-visible PRs, upload sanitized before/after screenshots or a short video
through GitHub's description/comment editor and include the generated attachment
links in the Visual evidence section. Keep review captures and reports out of Git;
use local scratch or ignored `target/` paths while preparing them. The GitHub CLI
can embed existing URLs, but `gh pr create`/`gh pr edit` do not upload local media.
If an owner must complete the upload, explicitly mark the evidence as pending.
Maintained README media remains versioned.

## Look and feel

Strata looks like a standard macOS app. Use native AppKit controls, system fonts,
SF Symbols, and semantic system colors such as `labelColor`,
`secondaryLabelColor`, `separatorColor`, and `controlAccentColor`, so the app
follows the user's light or dark appearance and accent color. Do not add custom
color themes, bundled fonts, or hardcoded colors.

## Asset policy

Only package assets Strata uses. Before bundling a third-party asset, record its
origin and license in the repository. Do not add generated placeholders or assets
of unclear provenance.
