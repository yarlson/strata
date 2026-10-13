# Agent Instructions

## Explicit owner consent

All rules in this file are defaults that the repository owner may override with
explicit instructions or consent for the current task. This applies even where
rules say "must", "never", or "only", including validation, Git workflow, and
pull request requirements. No rule in this file is exempt from this override.

A direct request to take a normally disallowed action is sufficient consent;
for example, "push straight to main" authorizes a direct push. Carry out the
requested action rather than refusing because of this file or repeatedly asking
for permission already given. Ask only if the requested scope is genuinely
unclear. Silence, urgency, and unrelated prior consent are not overrides; keep
the other defaults in effect.

Record the override and any skipped checks or unverified behavior in the handoff
and, when relevant, the PR description. Never report skipped checks as passed.
Consent changes repository instructions, not actual tool permissions or external
branch protections, and does not override higher-priority system or developer
instructions.

## Agent skills

Restore project skills from the committed `skills-lock.json` after cloning:

```bash
npx skills experimental_install
```

That installs them into `.agents/skills/`, which is gitignored. Keep
`skills-lock.json` in version control. Add or update skills with `npx skills add`
and `npx skills update`, then commit the lockfile. Do not vendor skill files
under `.agents/`.

## Git workflow

- **One conversation, one PR by default.** Treat follow-up requests in the same conversation as changes to the existing task and PR unless the owner explicitly requests a separate PR. Keep implementing, committing, and pushing to that PR's branch; do not create stacked PRs or split follow-ups onto separate task branches.
- Never commit or push directly to `main`. Work from a GitHub issue and submit changes through a pull request.
- Name branches `<type>/<issue-number>-<short-kebab-description>`, for example `feat/6-sandbox-previews`. Use Conventional Commit types such as `feat`, `fix`, `docs`, `refactor`, `test`, `perf`, `build`, `ci`, and `chore`.
- Write commits and pull request titles in Conventional Commits format: `<type>(optional-scope): <imperative description>`.
- Keep commits focused. Use `!` and a `BREAKING CHANGE:` footer for breaking changes, and reference the issue in the pull request body.

## Pre-push checks

Strata is a Swift package in `macos/`. Before pushing, run:

```bash
mise run check        # swift format lint --strict, swift test, typos
mise run build        # when the change touches the bundle, resources, or scripts
```

- Format with `swift format --in-place --recursive macos/Sources macos/Tests`.
  Run lint and formatting at the pre-push checkpoint, not after every edit.
- For a bounded change, run the affected tests with
  `swift test --package-path macos --filter <Suite or test>` while working, and
  confirm the filter selects at least one test. Run the full `mise run check`
  before pushing.
- When one test fails, reproduce that test alone first. Fix it, rerun it and its
  callers, then rerun the full check once.
- Documentation-only changes need no build or tests: review the complete diff,
  check links, and run `typos` and `git diff --check`.
- Unless explicitly overridden, fix failures before pushing.

## Running the app

- Never take the owner's keyboard focus, and do not launch `Strata.app` on the
  owner's desktop without asking; even `open -g` can end up frontmost. A focused
  file manager can receive the owner's keystrokes, including Trash and delete
  shortcuts.
- For visual checks, open a `BrowserWindowController` offscreen in a temporary
  test (move the window far off screen, call `orderFrontRegardless()`), capture
  it with `screencapture -x -o -l<windowNumber>`, and delete the test afterward.
- Prefer offscreen app tests to manual checks for behavior.

## Issues and pull requests

- Automated agents must follow the same issue-first workflow and pull request template as human contributors; do not remove or bypass template sections.
- Use the bug report form for defects, the feature request form for enhancements, and a blank issue only when neither form fits.
- Bug reports must include the Strata version, installation method, macOS version, reproduction steps, expected behavior, and any available sanitized logs. Never ask reporters to upload a memory dump because it may contain secrets or private document contents.
- Keep pull request descriptions concise: explain what changed and why, provide manual steps to exercise the feature or reproduce the fixed bug, state the expected result, and link the issue.
- Include before/after screenshots or a short video on every PR with user-visible changes. Upload sanitized captures through GitHub's PR description/comment editor and embed the resulting GitHub-hosted attachment URLs in the PR's Visual evidence section. Write `N/A` with a brief reason only for non-visual changes.
- Never commit PR evidence, screenshots, recordings, one-off capture scripts, logs, review reports, or PR-specific test plans to the source tree. Keep captures in session-owned scratch or ignored `target/` paths. Maintained README media is the exception, not a place to stash review captures.
- `gh pr create` and `gh pr edit` can embed existing attachment URLs but do not upload local image/video attachments. If no supported authenticated upload route is available, retain the local captures, provide their exact paths and captions, and ask the owner to upload them through the GitHub editor. Explicitly mark visual evidence as pending; do not claim it is attached, substitute local file links, or commit files as a workaround.
- Keep lasting behavior and test guidance in maintained documentation; put task checklists, test results, and review history in the issue or PR instead.
- Pull request titles must pass `.github/workflows/pr-policy.yml`; do not bypass or weaken the Conventional Commit title check.

## Code organization

- Put rules that need only Foundation in `macos/Sources/StrataCore` and keep
  AppKit in `macos/Sources/Strata`.
- Route every filesystem change through `FileMutations` (safety rules) and
  `FileOperationCenter` (progress, conflicts, undo). Never overwrite a user's
  item silently; a replaced item goes to the Trash.
- Compare file URLs through `URL.canonical`; listings return folder URLs with a
  trailing slash.
- Keep directory loading, search, and preview reading off the main thread.

## Tests

- Put rule tests in `macos/Tests/StrataCoreTests` and app behavior tests in
  `macos/Tests/StrataTests`.
- App tests drive offscreen windows with synthesized `NSEvent`s. They must never
  order a window front, take keyboard focus, show a modal alert, use
  `NSPasteboard.general`, or move files to the user's Trash. Use a private
  pasteboard, temporary folders, and an injected stand-in Trash.
- Test observable behavior, not implementation echoes. Do not add tests that
  repeat constants or setter assignments, or that assert layout, geometry,
  spacing, or pixel placement. Verify layout changes with screenshots instead.
- Keep behavioral tests for actions, keyboard routing, focus, filesystem safety,
  error handling, and live preferences. Extend an existing suite or table before
  adding a near-duplicate test.
- Every parameter in a parameterized test must affect the exercised behavior or
  an assertion.

## Preferences

- Add settings to `Preferences` in `macos/Sources/Strata/Preferences.swift`.
  Every change posts `Preferences.didChange`; open windows must update live
  from that notification, without reopening.
- Settings pages only edit preferences; they never drive browser behavior
  directly.

## Internationalization

- Every new or changed user-facing string goes through `tr("…")` (or
  `trCount` for counts) and must be added to all eleven catalogs in
  `macos/Resources/locales` in the same change: English, French, German,
  Spanish, Japanese, Brazilian Portuguese, Korean, Vietnamese, Italian, Russian,
  and Simplified Chinese. Do not copy English into other languages as a
  placeholder.
- Pass `tr` a string literal so the catalog coverage test can see it.
- Translate complete messages with named `%{placeholders}`; do not assemble
  sentences from fragments. Preserve placeholder names, paths, commands, and key
  labels.
- Never translate filesystem paths, filenames, or user-authored content.
- Run `swift test --package-path macos --filter LocalizerTests` after changing
  catalogs.

## Keyboard shortcuts

- Define every shortcut in the `Bindings` catalog in
  `macos/Sources/Strata/KeyBindings.swift` and match it with
  `binding.matches(event)`. Never compare raw key codes or typed characters to
  recognize a command.
- Never type a key label by hand. Menus use `menuKeyEquivalent`; hints, the
  footer, and the F1 reference use `binding.label`.
- Plain-letter shortcuts are handled in the browser views, not as menu key
  equivalents, so they never fire while a text field has focus.

## UI controls

- Reuse existing views and builders (`PaneView`, `ScaledLabel`,
  `FileTableView`, `TextCellView`, `ClosureButton`, `ClosureMenuItem`) before
  creating new ones. Prefer native AppKit controls.

## Tooltips

- Only icon-only buttons may have tooltips. Do not add them to text buttons,
  menu items, labels, fields, file rows, status indicators, or other views,
  even when their text is truncated.
- Give icon-only buttons an accessibility label. Keep important help, errors,
  and status visible; never use tooltip text as internal data.

## Comments

- Prefer self-explanatory names and structure. Do not add comments that narrate obvious code or restate a test's setup, actions, or assertions.
- Use concise comments for non-obvious intent, invariants, safety requirements, external constraints, workarounds, or surprising behavior.

## Icons and appearance

- Strata looks like a standard macOS app. Do not add color themes, bundled
  fonts, or custom selection drawing.
- Use SF Symbols for interface icons (`IconProvider.symbol`) and system file
  icons and Quick Look thumbnails for files (`IconProvider`).
- Use semantic system colors (`labelColor`, `secondaryLabelColor`,
  `separatorColor`, `controlAccentColor`, `controlBackgroundColor`) so views
  follow light and dark appearance and the user's accent color. Never hardcode
  colors. Cells on a selected row switch text to
  `alternateSelectedControlTextColor` through `backgroundStyle`.
- Take fonts from `Appearance.shared` so they follow the text size preference.
- Observe notifications in views with selector-based `addObserver(self, …)`,
  which the system removes automatically, or remove block observers in an
  `isolated deinit`.
