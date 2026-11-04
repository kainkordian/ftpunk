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
task_device_type="com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro"
task_device_name="FTPunk iPhone 15 Pro"
task_runtime="$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; r=[r for r in json.load(sys.stdin)["runtimes"] if r.get("isAvailable") and any(d["identifier"]==sys.argv[1] for d in r.get("supportedDeviceTypes",[]))]; r.sort(key=lambda r:tuple(map(int,r["version"].split("."))),reverse=True); print(r[0]["identifier"] if r else "")' "$task_device_type")"
if [ -z "$task_runtime" ]; then
    printf '%s\n' 'Install an iOS Simulator runtime that supports iPhone 15 Pro in Xcode Settings → Components, then run this script again. This launcher never substitutes another iPhone model.'
    exit 1
fi
task_udid="$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=[d for d in json.load(sys.stdin)["devices"].get(sys.argv[1],[]) if d["name"]==sys.argv[2] and d["deviceTypeIdentifier"]==sys.argv[3]]; print(d[0]["udid"] if d else "")' "$task_runtime" "$task_device_name" "$task_device_type")"
if [ -z "$task_udid" ]; then
    task_udid="$(xcrun simctl create "$task_device_name" "$task_device_type" "$task_runtime")"
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
if [ "${1:-}" = "--matrix" ]; then
    # Screenshot matrix: every preview scenario x light/dark x default/accessibility text size.
    # Usage: sh Tools/run_simulator.sh --matrix [output-dir] [scenario ...]
    # Scenarios seed the in-memory preview store only; the persistent store is never touched.
    shift
    task_out="${1:-$task_root/.build/screenshots}"
    [ $# -gt 0 ] && shift
    task_scenarios="${*:-first-launch home-today home-not-connected home-no-ftp home-retest-due library preflight-blocked ride-warmup ride-ramp ride-ramp-low-cadence ride-cooldown result-new-ftp result-interrupted result-upload-prompt workout-running workout-paused free-ride resistance progress-two-riders visual-ramp-threshold visual-workout-vo2 visual-recovery visual-summit visual-paused visual-off visual-hero visual-sprint settings-devices settings-intervals settings-intervals-connected workout-detail builder-blocks builder-text}"
    mkdir -p "$task_out"
    # A capture taken right after an appearance or text-size change, or while the scenario is still being
    # seeded, can come out black. The first launch after a change therefore waits longer, and a PNG smaller
    # than FTPUNK_MIN_SCREENSHOT_BYTES (a blank frame compresses to a fraction of a real screen) is retaken
    # with a longer wait, up to three times, before the script warns about it.
    task_min_bytes="${FTPUNK_MIN_SCREENSHOT_BYTES:-150000}"
    task_suspicious=""
    for task_appearance in dark light; do
        for task_size in large accessibility-extra-large; do
            xcrun simctl ui "$task_udid" appearance "$task_appearance"
            xcrun simctl ui "$task_udid" content_size "$task_size"
            sleep 3
            task_settling=1
            for task_scenario in $task_scenarios; do
                task_file="$task_out/$task_scenario-$task_appearance-$task_size.png"
                task_wait=4
                if [ "$task_settling" = 1 ]; then task_wait=9; fi
                task_attempt=1
                while :; do
                    xcrun simctl terminate "$task_udid" com.kainkordian.ftpunk 2>/dev/null || true
                    sleep 1
                    xcrun simctl launch "$task_udid" com.kainkordian.ftpunk --debug-preview --scenario "$task_scenario"
                    sleep "$task_wait"
                    xcrun simctl io "$task_udid" screenshot "$task_file"
                    task_bytes="$(wc -c < "$task_file" | tr -d ' ')"
                    if [ "$task_bytes" -ge "$task_min_bytes" ]; then break; fi
                    if [ "$task_attempt" -ge 3 ]; then
                        printf '%s\n' "Warning: $task_file is only $task_bytes bytes after $task_attempt attempts; it may be blank." >&2
                        task_suspicious="$task_suspicious $task_file"
                        break
                    fi
                    printf '%s\n' "Retaking $task_file ($task_bytes bytes looks blank)." >&2
                    task_attempt=$((task_attempt + 1)); task_wait=$((task_wait + 5))
                done
                task_settling=0
            done
        done
    done
    xcrun simctl ui "$task_udid" appearance light
    xcrun simctl ui "$task_udid" content_size large
    printf '%s\n' "Screenshots saved in $task_out"
    if [ -n "$task_suspicious" ]; then printf '%s\n' "Check these captures:$task_suspicious" >&2; fi
    exit 0
fi
xcrun simctl launch "$task_udid" com.kainkordian.ftpunk --debug-preview "$@"
if [ -d "$task_developer_dir/../Applications/DeviceHub.app" ]; then
    # Xcode 27 hosts simulators in Device Hub instead of Simulator.app.
    open -a "$task_developer_dir/../Applications/DeviceHub.app" "devices://manage/select?id=$task_udid"
elif [ -d "$task_developer_dir/Applications/Simulator.app" ]; then
    open -a "$task_developer_dir/Applications/Simulator.app" --args -CurrentDeviceUDID "$task_udid"
else
    printf '%s\n' 'The app is installed, but no Simulator or Device Hub UI was found in this Xcode installation.'
    exit 1
fi
printf '%s\n' 'FTPunk is open in the dedicated iPhone 15 Pro simulator with debug mode enabled. No cycling devices are needed. Add --scenario <name> to open a seeded state, or --matrix for the screenshot matrix.'
