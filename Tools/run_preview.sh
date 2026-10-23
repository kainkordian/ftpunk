#!/bin/sh
set -eu

task_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$task_root"
swift build --product FTPunkPreview
task_binary_dir="$(swift build --show-bin-path)"
python3 Tools/package_preview.py "$task_binary_dir/FTPunkPreview" --output "$task_root/.build/FTPunkPreview.app"
open -n "$task_root/.build/FTPunkPreview.app" --args --debug-preview "$@"
