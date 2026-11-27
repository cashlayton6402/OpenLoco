#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/scripts/ios-build-common.sh"
openloco_select_ios_build simulator "$(uname -s)" "$(uname -m)"
build="$root/build/$ios_preset"
evidence="$build/evidence"
mkdir -p "$evidence"
app="$(cat "$evidence/app-path.txt")"
xcrun lipo "$app/OpenLoco" -verify_arch "$ios_arch"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")"

# Choose an available runtime/device type explicitly; do not depend on a booted
# simulator left behind by another job or the runner's default device model.
sdk_version="$(xcrun --sdk iphonesimulator --show-sdk-version)"
runtime="$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; version=lambda s:tuple(map(int,s.split(".")[:2])); sdk=version(sys.argv[1]); arch=sys.argv[2]; r=[x for x in json.load(sys.stdin)["runtimes"] if x.get("isAvailable") and x["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-") and (17,0)<=version(x["version"])<=sdk and arch in x.get("supportedArchitectures",[arch])]; r.sort(key=lambda x:tuple(map(int,x["version"].split(".")))); print(r[-1]["identifier"] if r else "")' "$sdk_version" "$ios_arch")"
device_type="$(xcrun simctl list devicetypes -j | python3 -c 'import json,sys; d=[x for x in json.load(sys.stdin)["devicetypes"] if x.get("productFamily")=="iPad"]; print(next((x["identifier"] for x in d if "iPad-Pro-11-inch-M4" in x["identifier"]),d[-1]["identifier"] if d else ""))')"
[[ -n "$runtime" && -n "$device_type" ]] || { echo "No compatible iPad/iOS runtime for $ios_arch and SDK $sdk_version. Intel Macs require a universal simulator runtime." >&2; exit 1; }
device="$(xcrun simctl create OpenLoco-Unsigned-Smoke "$device_type" "$runtime")"
cleanup() {
    xcrun simctl terminate "$device" "$bundle_id" >/dev/null 2>&1 || true
    xcrun simctl shutdown "$device" >/dev/null 2>&1 || true
    xcrun simctl delete "$device" >/dev/null 2>&1 || true
}
trap cleanup EXIT
xcrun simctl boot "$device"
xcrun simctl bootstatus "$device" -b
xcrun simctl ui "$device" appearance dark
xcrun simctl install "$device" "$app"
xcrun simctl launch "$device" "$bundle_id" --smoke-test | tee "$evidence/simulator-launch.txt"
container="$(xcrun simctl get_app_container "$device" "$bundle_id" data)"
result="$container/Library/Application Support/OpenLoco/ios-smoke-result.json"
for attempt in {1..30}; do
    [[ -f "$result" ]] && break
    sleep 1
done
if [[ ! -f "$result" ]]; then
    xcrun simctl spawn "$device" log show --last 2m --style compact --predicate 'process == "OpenLoco"' > "$evidence/simulator-console.txt" || true
    echo "Setup smoke result did not arrive; inspect simulator console/crash logs" >&2
    exit 1
fi
cp "$result" "$evidence/ios-smoke-result.json"
python3 - "$evidence/ios-smoke-result.json" <<'PY'
import json, sys
with open(sys.argv[1]) as stream:
    result = json.load(stream)
assert result["passed"] is True and result["gameplayStarted"] is False, result
assert result["frames"] > 1 and result["checks"] == 3 and result["cancellations"] == 1, result
assert result["dialogsPresented"] == 2, result
assert result["metalRenderer"] is True and result["pixelWidth"] > 0 and result["pixelHeight"] > 0, result
print("Setup screen rendered through Metal; cancel/retry handlers passed. Gameplay was not started.")
PY
xcrun simctl io "$device" screenshot "$evidence/setup-screen.png"
xcrun simctl spawn "$device" log show --last 2m --style compact --predicate 'process == "OpenLoco"' > "$evidence/simulator-console.txt" || true
printf 'runtime=%s\ndevice-type=%s\ndevice=%s\narchitecture=%s\npreset=%s\n' "$runtime" "$device_type" "$device" "$ios_arch" "$ios_preset" > "$evidence/simulator-environment.txt"
