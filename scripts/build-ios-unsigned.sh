#!/usr/bin/env bash
set -euo pipefail

target="${1:-simulator}"
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
source "$root/scripts/ios-build-common.sh"
openloco_select_ios_build "$target" "$(uname -s)" "$(uname -m)"
preset="$ios_preset"
sdk="$ios_sdk"
evidence="$root/build/$preset/evidence"
mkdir -p "$evidence"
exec > >(tee "$evidence/build.log") 2>&1

sw_vers
uname -m
xcodebuild -version
xcodebuild -showsdks
xcrun --sdk "$sdk" --show-sdk-path
xcrun --sdk "$sdk" --show-sdk-version
xcrun --sdk "$sdk" clang --version
xcrun simctl list runtimes
cmake --version
git rev-parse HEAD
git diff --stat
printf 'host-architecture=%s\ntarget=%s\npreset=%s\ntarget-architecture=%s\ntriplet=%s\nsdk=%s\nsigning=disabled\n' \
    "$(uname -m)" "$target" "$preset" "$ios_arch" "$ios_triplet" "$sdk" | tee "$evidence/build-target.txt"

revision="$(sed -n 's/^set(VCPKG_GIT_TAG \([0-9a-f]*\)).*/\1/p' CMakeLists.txt)"
[[ "$revision" =~ ^[0-9a-f]{40}$ ]] || { echo "Cannot read the pinned vcpkg revision" >&2; exit 1; }
manifest_revision="$(python3 -c 'import json; print(json.load(open("distribution/ios/vcpkg.json"))["builtin-baseline"])')"
[[ "$manifest_revision" == "$revision" ]] || { echo "The iOS manifest baseline must match VCPKG_GIT_TAG" >&2; exit 1; }
deps="${OPENLOCO_DEPS_DIR:-$root/build/dependencies}"
mkdir -p "$deps"
registry="${VCPKG_ROOT:-$deps/vcpkg}"
if [[ ! -d "$registry" ]]; then
    git init "$registry"
    git -C "$registry" fetch --depth=1 https://github.com/microsoft/vcpkg.git "$revision"
    git -C "$registry" checkout --detach FETCH_HEAD
fi
actual="$(git -C "$registry" rev-parse HEAD)"
[[ "$actual" == "$revision" ]] || { echo "vcpkg HEAD differs from project pin: $actual" >&2; exit 1; }
[[ -z "$(git -C "$registry" status --porcelain --untracked-files=no)" ]] || { echo "vcpkg checkout has modified tracked files" >&2; exit 1; }
if [[ ! -x "$registry/vcpkg" ]]; then
    "$registry/bootstrap-vcpkg.sh" -disableMetrics
fi
export VCPKG_DISABLE_METRICS=1
export VCPKG_FEATURE_FLAGS=-binarycaching,manifests,versions
# Opt into a cache only when a caller supplies its location/configuration.
if [[ -n "${VCPKG_DEFAULT_BINARY_CACHE:-}" ]]; then
    mkdir -p "$VCPKG_DEFAULT_BINARY_CACHE"
    export VCPKG_FEATURE_FLAGS=manifests,versions
fi
cmake --preset "$preset" "-DVCPKG_ROOT=$registry"
cmake --build --preset "$preset-release" --parallel "$(sysctl -n hw.ncpu)"

app="$(find "$root/build/$preset" -type d -name OpenLoco.app -not -path '*_deps*' -print -quit)"
[[ -n "$app" && -x "$app/OpenLoco" ]] || { echo "Built app bundle not found" >&2; exit 1; }
plutil -lint "$app/Info.plist"
file "$app/OpenLoco" | tee "$evidence/binary.txt"
xcrun lipo -verify_arch "$ios_arch" "$app/OpenLoco"
xcrun vtool -show-build "$app/OpenLoco" | tee "$evidence/platform.txt"
otool -L "$app/OpenLoco" | tee "$evidence/linked-libraries.txt"
if grep -Eq 'Cocoa|AppKit|/opt/homebrew|/usr/local/|libclang_rt.*osx' "$evidence/linked-libraries.txt"; then
    echo "Unexpected desktop library in iOS bundle" >&2
    exit 1
fi
expected="$ios_platform"
grep -Eq "platform[[:space:]]+$expected([[:space:]]|$)" "$evidence/platform.txt" || { echo "Wrong Mach-O platform" >&2; exit 1; }
[[ -d "$app/language" && -d "$app/objects" ]] || { echo "Bundled language/object resources missing" >&2; exit 1; }

artifacts="$root/build/$preset/artifacts"
mkdir -p "$artifacts/notices"
ditto -c -k --sequesterRsrc --keepParent "$app" "$artifacts/OpenLoco-$preset-unsigned.app.zip"
while IFS= read -r -d '' symbols; do
    ditto -c -k --sequesterRsrc --keepParent "$symbols" "$artifacts/$(basename "$symbols").zip"
done < <(find "$root/build/$preset" -type d -name '*.dSYM' -not -path '*_deps*' -print0)
while IFS= read -r -d '' notice; do
    component="$(basename "$(dirname "$notice")")"
    cp "$notice" "$artifacts/notices/$component.txt"
done < <(find "$root/build/$preset/vcpkg_installed" -path '*/share/*/copyright' -print0)
cp distribution/ios/vcpkg.json "$evidence/runtime-manifest.json"
printf '%s\n' "$revision" > "$evidence/vcpkg-revision.txt"
printf '%s\n' "$app" > "$evidence/app-path.txt"
shasum -a 256 "$artifacts"/*.zip > "$evidence/SHA256SUMS"
echo "Unsigned $target app built and inspected: $app"
