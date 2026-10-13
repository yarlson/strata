# Third-party notices

Strata includes or derives assets from the following projects.

## JetBrains Mono

- Project: <https://github.com/JetBrains/JetBrainsMono>
- Version: 2.304
- Copyright: JetBrains s.r.o.
- License: SIL Open Font License 1.1
- Included asset: `macos/Resources/fonts/JetBrainsMono[wght].ttf`
- Full license: [`macos/Resources/licenses/JetBrainsMono-OFL-1.1.txt`](macos/Resources/licenses/JetBrainsMono-OFL-1.1.txt)

The font is distributed unmodified. Strata registers it for its own process at
launch, so it does not change the user's installed fonts.

## Tinted Theming schemes

- Project: <https://github.com/tinted-theming/schemes>
- Revision: `fdca32a0d14ec80ad83a78a9ccb85592ca6cb9e1`
- Copyright: Tinted Theming and the scheme authors identified by the upstream files
- License: MIT
- Derived asset: `macos/Resources/themes/catalog.toml`
- Full license: [`macos/Resources/licenses/Tinted-Theming-MIT.txt`](macos/Resources/licenses/Tinted-Theming-MIT.txt)

The bundled catalog contains curated Base16 palettes derived from this project, with a few foreground values adjusted for readability (noted in the catalog), alongside Strata's original themes. The Base16 mapping to Strata's semantic UI tokens is documented in the catalog.
