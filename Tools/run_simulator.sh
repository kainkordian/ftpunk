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
task_device_type="$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; r=next(r for r in json.load(sys.stdin)["runtimes"] if r["identifier"]==sys.argv[1]); d=[d for d in r.get("supportedDeviceTypes",[]) if d.get("productFamily")=="iPhone"]; preferred=next((d for d in d if d["identifier"]=="com.apple.CoreSimulator.SimDeviceType.iPhone-16"),None); print((preferred or d[0])["identifier"] if d else "com.apple.CoreSimulator.SimDeviceType.iPhone-16")' "$task_runtime")"
task_udid="$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=[d for d in json.load(sys.stdin)["devices"].get(sys.argv[1],[]) if d["name"]=="FTPunk iPhone"]; print(d[0]["udid"] if d else "")' "$task_runtime")"
if [ -z "$task_udid" ]; then
    task_udid="$(xcrun simctl create 'FTPunk iPhone' "$task_device_type" "$task_runtime")"
fi
task_derived="$task_root/.build/ios"
task_arch="$(uname -m)"
xcodebuild -project "$task_root/FTPunk.xcodeproj" -scheme FTPunk -sdk iphonesimulator \
    -destination "id=$task_udid" -derivedDataPath "$task_derived" \
    ARCHS="$task_arch" ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build
# bootstatus reports real failures; boot may return an error when already booted.
xcrun simctl boot "$task_udid" 2>/dev/null || true
xcrun simctl bootstatus "$task_udid" -b
xcrun simctl install "$task_udid" "$task_derived/Build/Products/Debug-iphonesimulator/FTPunk.app"
xcrun simctl launch "$task_udid" com.kainkordian.ftpunk --debug-preview
if [ -d "$task_developer_dir/../Applications/DeviceHub.app" ]; then
    # Xcode 27 hosts simulators in Device Hub instead of Simulator.app.
    open -a "$task_developer_dir/../Applications/DeviceHub.app" "devices://manage/select?id=$task_udid"
elif [ -d "$task_developer_dir/Applications/Simulator.app" ]; then
    open -a "$task_developer_dir/Applications/Simulator.app" --args -CurrentDeviceUDID "$task_udid"
else
    printf '%s\n' 'The app is installed, but no Simulator or Device Hub UI was found in this Xcode installation.'
    exit 1
fi
printf '%s\n' 'FTPunk is open in a dedicated iPhone Simulator with debug mode enabled. No cycling devices are needed.'
