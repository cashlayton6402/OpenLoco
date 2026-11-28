#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/scripts/ios-build-common.sh"
openloco_select_ios_build simulator "$(uname -s)" "$(uname -m)"
build="$root/build/$ios_preset"
evidence="$build/evidence"
mkdir -p "$evidence"
# Discard only this script's prior run evidence, never unrelated build evidence.
rm -f -- "$evidence/ios-smoke-result.json" "$evidence/ios-smoke-progress.json" \
    "$evidence/setup-screen.png" "$evidence/simulator-console.txt" \
    "$evidence/screen-validation.json" "$evidence/screen-validation.txt" \
    "$evidence/simulator-environment.txt" "$evidence/simulator-launch.txt" "$evidence/simulator-phases.txt" \
    "$evidence/ui-rotation-build.log" "$evidence/ui-rotation.log" "$evidence/ui-rotation-exit-code.txt"
# Only named probe outputs are owned by this script; preserve other build evidence.
mkdir -p "$evidence/layout"
for name in landscape-left landscape-right portrait-return resize-wide resize-compact restore-full; do
    rm -f -- "$evidence/layout/$name.json" "$evidence/layout/$name.png"
done
rm -f -- "$evidence/layout/summary.json" "$evidence/layout/completion.json" \
    "$evidence/ios-layout-progress.json" "$evidence/ios-layout-complete.json"
app="$(cat "$evidence/app-path.txt")"
xcrun lipo "$app/OpenLoco" -verify_arch "$ios_arch"
bundle_id="$(python3 -c 'import plistlib,sys; print(plistlib.load(open(sys.argv[1],"rb"))["CFBundleIdentifier"])' "$app/Info.plist")"
[[ "$bundle_id" == io.openloco.ios.development ]] || { echo "UI rotation runner expects the development app bundle identifier" >&2; exit 1; }

# Choose an available runtime/device type explicitly; do not depend on a booted
# simulator left behind by another job or the runner's default device model.
sdk_version="$(xcrun --sdk iphonesimulator --show-sdk-version)"
runtime="$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; version=lambda s:tuple(map(int,s.split(".")[:2])); sdk=version(sys.argv[1]); arch=sys.argv[2]; r=[x for x in json.load(sys.stdin)["runtimes"] if x.get("isAvailable") and x["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-") and (17,0)<=version(x["version"])<=sdk and arch in x.get("supportedArchitectures",[arch])]; r.sort(key=lambda x:tuple(map(int,x["version"].split(".")))); print(r[-1]["identifier"] if r else "")' "$sdk_version" "$ios_arch")"
device_type="$(xcrun simctl list devicetypes -j | python3 -c 'import json,sys; d=[x for x in json.load(sys.stdin)["devicetypes"] if x.get("productFamily")=="iPad"]; print(next((x["identifier"] for x in d if "iPad-Pro-11-inch-M4" in x["identifier"]),d[-1]["identifier"] if d else ""))')"
[[ -n "$runtime" && -n "$device_type" ]] || { echo "No compatible iPad/iOS runtime for $ios_arch and SDK $sdk_version. Intel Macs require a universal simulator runtime." >&2; exit 1; }
# Build only the standalone simulator UI test. It never links into the app and
# cannot provision a physical device or use signing identities.
rotation_project="$root/scripts/tests/ios-rotation/Rotation.xcodeproj"
rotation_derived="$build/rotation-driver"
xcodebuild -project "$rotation_project" -scheme Rotation -configuration Debug \
    -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$rotation_derived" ARCHS="$ios_arch" ONLY_ACTIVE_ARCH=YES \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
    build-for-testing > "$evidence/ui-rotation-build.log" 2>&1
device="$(xcrun simctl create OpenLoco-Unsigned-Smoke "$device_type" "$runtime")"
container=""
rotation_pid=""
rotation_status=""
printf 'runtime=%s\ndevice-type=%s\ndevice=%s\narchitecture=%s\npreset=%s\n' "$runtime" "$device_type" "$device" "$ios_arch" "$ios_preset" > "$evidence/simulator-environment.txt"
phase() {
    printf '%s phase=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" | tee -a "$evidence/simulator-phases.txt"
}
cleanup() {
    status=$?
    trap - EXIT
    set +e
    phase "cleanup-exit-$status"
    # Collect before terminating, including on launch/poll/validation failures.
    if [[ -n "$container" ]]; then
        for name in ios-smoke-result.json ios-smoke-progress.json ios-layout-progress.json ios-layout-complete.json; do
            smoke_source="$container/Library/Application Support/OpenLoco/$name"
            [[ ! -f "$smoke_source" ]] || cp "$smoke_source" "$evidence/$name"
        done
    fi
    [[ -f "$evidence/setup-screen.png" ]] || xcrun simctl io "$device" screenshot "$evidence/setup-screen.png"
    xcrun simctl spawn "$device" log show --last 10m --style compact --predicate 'process == "OpenLoco"' > "$evidence/simulator-console.txt"
    if [[ -n "$rotation_pid" && -z "$rotation_status" ]]; then
        # Stop only this invocation's child; preserve the original test failure.
        kill "$rotation_pid" >/dev/null 2>&1 || true
        wait "$rotation_pid"
        rotation_status=$?
        printf '%s\n' "$rotation_status" > "$evidence/ui-rotation-exit-code.txt"
    fi
    xcrun simctl terminate "$device" "$bundle_id" >/dev/null 2>&1 || true
    xcrun simctl shutdown "$device" >/dev/null 2>&1 || true
    xcrun simctl delete "$device" >/dev/null 2>&1 || true
    exit "$status"
}
trap cleanup EXIT
phase boot
xcrun simctl boot "$device"
xcrun simctl bootstatus "$device" -b
phase appearance
xcrun simctl ui "$device" appearance dark
phase install
xcrun simctl install "$device" "$app"
phase locate-container
container="$(xcrun simctl get_app_container "$device" "$bundle_id" data)"
phase launch-ui-rotation-test
# One UI test launches the already installed app with the smoke/layout flags,
# establishes portrait, then uses XCUIDevice.orientation at session-tagged stages.
# No app scene-orientation request and no Simulator menu automation is used.
xcodebuild -project "$rotation_project" -scheme Rotation -configuration Debug \
    -sdk iphonesimulator -destination "platform=iOS Simulator,id=$device" \
    -derivedDataPath "$rotation_derived" -parallel-testing-enabled NO \
    -test-timeouts-enabled YES -default-test-execution-time-allowance 1800 \
    -maximum-test-execution-time-allowance 1800 \
    -resultBundlePath "$evidence/rotation-$(date -u +%Y%m%dT%H%M%SZ)-$$.xcresult" \
    ARCHS="$ios_arch" ONLY_ACTIVE_ARCH=YES \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
    test-without-building > "$evidence/ui-rotation.log" 2>&1 &
rotation_pid=$!
result="$container/Library/Application Support/OpenLoco/ios-smoke-result.json"
phase wait-for-result
# Includes UI-test-runner startup, cold Metal, then the app's transition sequence.
deadline=$((SECONDS + 300))
while [[ ! -f "$result" ]] && ((SECONDS < deadline)); do
    if ! kill -0 "$rotation_pid" >/dev/null 2>&1; then
        if wait "$rotation_pid"; then rotation_status=0; else rotation_status=$?; fi
        printf '%s\n' "$rotation_status" > "$evidence/ui-rotation-exit-code.txt"
        echo "UI rotation runner exited before setup evidence; inspect ui-rotation.log" >&2
        if [[ "$rotation_status" -ne 0 ]]; then exit "$rotation_status"; fi
        exit 1
    fi
    sleep 1
done
if [[ ! -f "$result" ]]; then
    # Preserve a runner failure that arrived at the polling deadline too.
    if ! kill -0 "$rotation_pid" >/dev/null 2>&1; then
        if wait "$rotation_pid"; then rotation_status=0; else rotation_status=$?; fi
        printf '%s\n' "$rotation_status" > "$evidence/ui-rotation-exit-code.txt"
        if [[ "$rotation_status" -ne 0 ]]; then exit "$rotation_status"; fi
    fi
    echo "Setup smoke result did not arrive within 300 seconds; inspect UI runner, progress, phases and console evidence" >&2
    exit 1
fi
cp "$result" "$evidence/ios-smoke-result.json"
# Capture diagnostics before validation so failures retain the unmodified image.
phase capture-screen
xcrun simctl io "$device" screenshot "$evidence/setup-screen.png"
phase validate
python3 "$root/scripts/verify-ios-evidence.py" smoke "$evidence/ios-smoke-result.json" \
    "$evidence/setup-screen.png" 2>&1 | tee "$evidence/screen-validation.txt"
phase rotation-and-window-frame-checks
python3 "$root/scripts/check-ios-layout.py" "$device" "$container" "$evidence"
phase wait-for-ui-rotation-test
deadline=$((SECONDS + 120))
while kill -0 "$rotation_pid" >/dev/null 2>&1 && ((SECONDS < deadline)); do
    sleep 1
done
if kill -0 "$rotation_pid" >/dev/null 2>&1; then
    echo "UI rotation runner did not finish after native completion" >&2
    exit 1
fi
if wait "$rotation_pid"; then rotation_status=0; else rotation_status=$?; fi
printf '%s\n' "$rotation_status" > "$evidence/ui-rotation-exit-code.txt"
[[ "$rotation_status" -eq 0 ]] || { echo "UI rotation runner failed; inspect ui-rotation.log and xcresult" >&2; exit "$rotation_status"; }
