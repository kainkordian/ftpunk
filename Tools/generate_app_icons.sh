#!/bin/sh
set -eu

task_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
task_source="$task_root/design/app-icon/FTPunk-source.png"
task_assets="$task_root/App/Assets.xcassets/AppIcon.appiconset"
task_iconset="$task_root/.build/FTPunk.iconset"
mkdir -p "$task_assets" "$task_iconset"

# Mechanical app-icon exports; the approved artwork is kept at original resolution.
for task_size in 16 32 64 128 256 512 1024; do
    sips -z "$task_size" "$task_size" "$task_source" --out "$task_assets/icon-$task_size.png" >/dev/null
done
for task_size in 16 32 128 256 512; do
    task_retina=$((task_size * 2))
    cp "$task_assets/icon-$task_size.png" "$task_iconset/icon_${task_size}x${task_size}.png"
    cp "$task_assets/icon-$task_retina.png" "$task_iconset/icon_${task_size}x${task_size}@2x.png"
done
iconutil -c icns "$task_iconset" -o "$task_root/design/app-icon/FTPunk.icns"
printf '%s\n' 'Exported iOS and Mac app icons.'
