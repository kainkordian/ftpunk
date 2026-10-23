#!/bin/sh
set -eu
task_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$task_root"
swift build --product FTPunk --configuration release
task_binary_dir="$(swift build --configuration release --show-bin-path)"
python3 Tools/package_preview.py "$task_binary_dir/FTPunk" --production --output "$task_root/dist/FTPunk.app"
ditto -c -k --sequesterRsrc --keepParent "$task_root/dist/FTPunk.app" "$task_root/dist/FTPunk-Mac.zip"
printf '%s\n' "Mac app: $task_root/dist/FTPunk.app" "Archive: $task_root/dist/FTPunk-Mac.zip"
