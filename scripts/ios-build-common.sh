#!/usr/bin/env bash

# Shared by the build and launch scripts so they cannot select different app
# directories or confuse the Mac's CPU with the iPad application's CPU.
# Sets ios_preset, ios_sdk, ios_arch, ios_triplet and ios_platform on success.
openloco_select_ios_build() {
    local target="$1" system="$2" host_arch="$3"
    if [[ "$system" != Darwin || ( "$host_arch" != arm64 && "$host_arch" != x86_64 ) ]]; then
        echo "An Intel or Apple Silicon Mac with Xcode and the iOS platform is required." >&2
        return 2
    fi
    case "$target" in
        device)
            ios_preset=ios-device
            ios_sdk=iphoneos
            ios_arch=arm64
            ios_triplet=arm64-ios-openloco
            ios_platform=IOS
            ;;
        simulator)
            ios_sdk=iphonesimulator
            ios_platform=IOSSIMULATOR
            if [[ "$host_arch" == x86_64 ]]; then
                ios_preset=ios-simulator-intel
                ios_arch=x86_64
                ios_triplet=x64-ios-simulator-openloco
            else
                ios_preset=ios-simulator
                ios_arch=arm64
                ios_triplet=arm64-ios-simulator-openloco
            fi
            ;;
        *)
            echo "Expected build target: device or simulator" >&2
            return 2
            ;;
    esac
}
