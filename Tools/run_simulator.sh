#!/bin/sh
set -eu

task_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
task_developer_dir="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if [ ! -x "$task_developer_dir/usr/bin/xcodebuild" ]; then
    printf '%s\n' 'Full Xcode is not installed. Install Xcode from the Mac App Store and open it once, selecting the iOS Simulator component.'
    exit 1
fi
export DEVELOPER_DIR="$task_developer_dir"
if ! xcodebuild -checkFirstLaunchStatus; then
    printf '%s\n' 'Open Xcode and complete its first-launch setup before starting the simulator.'
    exit 1
fi
task_runtime="$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; r=[r for r in json.load(sys.stdin)["runtimes"] if r.get("isAvailable") and ".iOS-" in r["identifier"]]; r.sort(key=lambda r:tuple(map(int,r["version"].split("."))),reverse=True); print(r[0]["identifier"] if r else "")')"
if [ -z "$task_runtime" ]; then
    printf '%s\n' 'Install an iOS Simulator runtime in Xcode Settings → Components, then run this script again.'
    exit 1
fi
task_udid="$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=[d for v in json.load(sys.stdin)["devices"].values() for d in v if d["name"]=="FTPunk iPhone"]; print(d[0]["udid"] if d else "")')"
if [ -z "$task_udid" ]; then
    task_udid="$(xcrun simctl create 'FTPunk iPhone' com.apple.CoreSimulator.SimDeviceType.iPhone-16 "$task_runtime")"
fi
task_derived="$task_root/.build/ios"
xcodebuild -project "$task_root/FTPunk.xcodeproj" -scheme FTPunk -sdk iphonesimulator \
    -destination "id=$task_udid" -derivedDataPath "$task_derived" CODE_SIGNING_ALLOWED=NO build
# bootstatus reports real failures; boot may return an error when already booted.
xcrun simctl boot "$task_udid" 2>/dev/null || true
xcrun simctl bootstatus "$task_udid" -b
open -a "$task_developer_dir/Applications/Simulator.app" --args -CurrentDeviceUDID "$task_udid"
xcrun simctl install "$task_udid" "$task_derived/Build/Products/Debug-iphonesimulator/FTPunk.app"
xcrun simctl launch "$task_udid" com.kainkordian.ftpunk --debug-preview
printf '%s\n' 'FTPunk is open in a dedicated iPhone Simulator with debug mode enabled. No cycling devices are needed.'
