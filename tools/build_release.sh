#!/usr/bin/env bash
# Exports every platform and packages the release ZIPs into dist/.
# Usage: tools/build_release.sh [path-to-godot]
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${1:-godot}"
VERSION="$(grep -oP '^config/version="\K[^"]+' project.godot)"
NAME="ShiftWorlds-v${VERSION}"

rm -rf build dist
mkdir -p build/windows build/linux build/macos dist
"$GODOT" --headless --import >/dev/null 2>&1 || true
"$GODOT" --headless --export-release "Windows Desktop" build/windows/ShiftWorlds.exe
"$GODOT" --headless --export-release "Linux" build/linux/ShiftWorlds.x86_64
"$GODOT" --headless --export-release "macOS" build/macos/ShiftWorlds.zip

package() {  # $1 platform, $2.. files
  local plat="$1"; shift
  local dir="dist/${NAME}-${plat}"
  mkdir -p "$dir"
  cp "$@" "$dir/"
  cp docs/README.txt "$dir/README.txt"
  cp LICENSE "$dir/LICENSE.txt"
  cp CREDITS.md "$dir/CREDITS.txt"
  cp THIRD_PARTY_LICENSES.txt "$dir/THIRD_PARTY_LICENSES.txt"
  (cd "$dir" && zip -qr9 "../${NAME}-${plat}.zip" .)
  rm -rf "$dir"
}
package windows build/windows/ShiftWorlds.exe
chmod +x build/linux/ShiftWorlds.x86_64
package linux build/linux/ShiftWorlds.x86_64

# macOS: Godot already produced a zipped .app; add the documents next to it
mkdir -p dist/mac_tmp && (cd dist/mac_tmp && unzip -q ../../build/macos/ShiftWorlds.zip)
cp docs/README.txt dist/mac_tmp/README.txt
cp LICENSE dist/mac_tmp/LICENSE.txt
cp CREDITS.md dist/mac_tmp/CREDITS.txt
cp THIRD_PARTY_LICENSES.txt dist/mac_tmp/THIRD_PARTY_LICENSES.txt
(cd dist/mac_tmp && zip -qry9 "../${NAME}-macos.zip" .)
rm -rf dist/mac_tmp

# Source code (what goes on GitHub)
git_files=$(ls -A | grep -vE '^(\.godot|build|dist)$')
mkdir -p "dist/src/shift-worlds"
cp -r $git_files "dist/src/shift-worlds/"
(cd dist/src && zip -qr9 "../${NAME}-source.zip" shift-worlds)
rm -rf dist/src

ls -la dist
