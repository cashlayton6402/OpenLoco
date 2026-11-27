#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
source "$root/scripts/ios-build-common.sh"

check() {
    local target="$1" host="$2" expected="$3"
    openloco_select_ios_build "$target" Darwin "$host"
    local actual="$ios_preset:$ios_sdk:$ios_arch:$ios_triplet:$ios_platform"
    [[ "$actual" == "$expected" ]] || { echo "Unexpected $target selection on $host: $actual" >&2; exit 1; }
    echo "PASS $host -> $target ($ios_arch)"
}

# In particular, an Intel host must cross-compile the real iPad app for ARM64.
check device x86_64 'ios-device:iphoneos:arm64:arm64-ios-openloco:IOS'
check device arm64 'ios-device:iphoneos:arm64:arm64-ios-openloco:IOS'
check simulator x86_64 'ios-simulator-intel:iphonesimulator:x86_64:x64-ios-simulator-openloco:IOSSIMULATOR'
check simulator arm64 'ios-simulator:iphonesimulator:arm64:arm64-ios-simulator-openloco:IOSSIMULATOR'

for rejected in 'device Linux x86_64' 'simulator MINGW64_NT x86_64' 'simulator Darwin i386' 'unknown Darwin arm64'; do
    read -r target system host <<< "$rejected"
    if (openloco_select_ios_build "$target" "$system" "$host") 2>/dev/null; then
        echo "Unsupported build was accepted: $rejected" >&2
        exit 1
    else
        status=$?
        [[ "$status" == 2 ]] || { echo "Unexpected rejection status: $status" >&2; exit 1; }
    fi
    echo "PASS reject $rejected"
done
echo "Host/target selection passed. No Apple SDK or runtime was executed."
