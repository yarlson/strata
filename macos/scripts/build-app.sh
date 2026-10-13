#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Builds Strata.app from the Swift package in macos/.
# Usage: macos/scripts/build-app.sh [--debug] [--universal] [--output DIR]
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
package="$repo/macos"
configuration=release
arch_flags=()
output="$repo/target/macos"

while (($#)); do
  case "$1" in
    --debug) configuration=debug ;;
    --universal) arch_flags=(--arch arm64 --arch x86_64) ;;
    --output)
      output="${2:?--output needs a directory}"
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
  shift
done

version="$(sed -n 's/^version = "\(.*\)"$/\1/p' "$repo/Cargo.toml" | head -n 1)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

swift build --package-path "$package" -c "$configuration" ${arch_flags[@]+"${arch_flags[@]}"}
bin_dir="$(swift build --package-path "$package" -c "$configuration" ${arch_flags[@]+"${arch_flags[@]}"} --show-bin-path)"

app="$output/Strata.app"
contents="$app/Contents"
resources="$contents/Resources"
rm -rf "$app"
mkdir -p "$contents/MacOS" "$resources/locales/messages" "$resources/locales/macos" \
  "$resources/themes" "$resources/fonts" "$resources/licenses"

cp "$bin_dir/Strata" "$contents/MacOS/Strata"
sed "s/@VERSION@/$version/g" "$package/Info.plist" >"$contents/Info.plist"
cp "$repo"/data/locales/*.json "$resources/locales/"
cp "$repo"/data/locales/messages/*.json "$resources/locales/messages/"
cp "$package"/Resources/locales/*.json "$resources/locales/macos/"
cp "$repo/data/themes/catalog.toml" "$resources/themes/"
cp "$repo/data/fonts/JetBrainsMono[wght].ttf" "$resources/fonts/"
cp "$repo/LICENSE" "$repo/THIRD_PARTY_LICENSES.md" "$resources/licenses/"
cp "$repo/data/licenses/JetBrainsMono-OFL-1.1.txt" "$repo/data/licenses/Tinted-Theming-MIT.txt" \
  "$resources/licenses/"

swift "$package/scripts/render-icon.swift" \
  "$repo/data/icons/scalable/apps/io.github.lgse.Strata.svg" "$scratch/AppIcon.iconset"
iconutil -c icns -o "$resources/AppIcon.icns" "$scratch/AppIcon.iconset"

# Localized folder-access prompts, one .lproj per supported language.
python3 -I - "$package/Resources/locales" "$resources" <<'PY'
import json, pathlib, sys

overlay, resources = map(pathlib.Path, sys.argv[1:])
message = "Strata shows and manages the files you browse."
keys = [
    "NSDesktopFolderUsageDescription", "NSDocumentsFolderUsageDescription",
    "NSDownloadsFolderUsageDescription", "NSRemovableVolumesUsageDescription",
    "NSNetworkVolumesUsageDescription",
]
for catalog in sorted(overlay.glob("*.json")):
    locale = catalog.stem
    text = json.loads(catalog.read_text(encoding="utf-8")).get(message, message)
    escaped = text.replace("\\", "\\\\").replace('"', '\\"')
    lproj = resources / f"{'zh-Hans' if locale == 'zh-CN' else locale}.lproj"
    lproj.mkdir(exist_ok=True)
    lines = [f'"{key}" = "{escaped}";' for key in keys]
    (lproj / "InfoPlist.strings").write_text("\n".join(lines) + "\n", encoding="utf-8")
PY

codesign --force --sign - "$app"
echo "$app"
