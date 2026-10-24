#!/bin/bash
# Render the actual macOS views with live measurements, without capturing the desktop.
set -euo pipefail
cd "$(dirname "$0")/.."
repository="$PWD"
preview_dir="$(mktemp -d "${TMPDIR:-/tmp}/lumine-preview.XXXXXX")"
trap 'rm -rf "$preview_dir"' EXIT
preview_app="$preview_dir/LuminePreview.app"
mkdir -p "$preview_app/Contents/MacOS" "$preview_app/Contents/Resources" "$repository/docs/images"
cp -R Lumine/*.lproj "$preview_app/Contents/Resources/"
cat > "$preview_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>app.lumine.screenshots</string>
<key>CFBundleExecutable</key><string>LuminePreview</string>
<key>CFBundleName</key><string>LuminePreview</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
sources=()
for source in Lumine/*.swift; do
  if [[ "$source" != "Lumine/LumineApp.swift" ]]; then sources+=("$source"); fi
done
swiftc -parse-as-library -O -framework AppKit -framework SwiftUI -framework IOKit \
  -framework CoreWLAN -framework ServiceManagement "${sources[@]}" scripts/RenderScreenshots.swift \
  -o "$preview_app/Contents/MacOS/LuminePreview"
"$preview_app/Contents/MacOS/LuminePreview" "$repository/docs/images"
