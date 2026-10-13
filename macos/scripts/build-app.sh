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

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

swift build --package-path "$package" -c "$configuration" ${arch_flags[@]+"${arch_flags[@]}"}
bin_dir="$(swift build --package-path "$package" -c "$configuration" ${arch_flags[@]+"${arch_flags[@]}"} --show-bin-path)"

app="$output/Strata.app"
contents="$app/Contents"
resources="$contents/Resources"
rm -rf "$app"
mkdir -p "$contents/MacOS" "$resources"

cp "$bin_dir/Strata" "$contents/MacOS/Strata"
cp "$package/Info.plist" "$contents/Info.plist"
cp -R "$package/Resources/locales" "$resources/"
cp "$repo/LICENSE" "$resources/LICENSE"

swift "$package/scripts/render-icon.swift" "$package/Resources/AppIcon.svg" "$scratch/AppIcon.iconset"
iconutil -c icns -o "$resources/AppIcon.icns" "$scratch/AppIcon.iconset"

# Localized folder-access prompts, one .lproj per supported language.
python3 -I - "$package/Resources/locales" "$resources" <<'PY'
import json, pathlib, sys

catalogs, resources = map(pathlib.Path, sys.argv[1:])
message = "Strata shows and manages the files you browse."
keys = [
    "NSDesktopFolderUsageDescription", "NSDocumentsFolderUsageDescription",
    "NSDownloadsFolderUsageDescription", "NSRemovableVolumesUsageDescription",
    "NSNetworkVolumesUsageDescription",
]
for catalog in sorted(catalogs.glob("*.json")):
    locale = catalog.stem
    if locale == "counts":
        continue
    text = json.loads(catalog.read_text(encoding="utf-8")).get(message, message)
    escaped = text.replace("\\", "\\\\").replace('"', '\\"')
    lproj = resources / f"{'zh-Hans' if locale == 'zh-CN' else locale}.lproj"
    lproj.mkdir(exist_ok=True)
    lines = [f'"{key}" = "{escaped}";' for key in keys]
    (lproj / "InfoPlist.strings").write_text("\n".join(lines) + "\n", encoding="utf-8")
PY

codesign --force --sign - "$app"
echo "$app"
