# Unsigned iPad feasibility target (M0–M3)

This target builds the native engine and an asset-free iOS setup shell. It does
not start gameplay, import Locomotion data, or provide finished touch controls.
No signing credentials, Apple membership, paid service or game data is needed
for compilation and simulator testing. Unsigned device bundles cannot launch
on a stock iPad.

## Build on an Apple Silicon Mac or standard macOS CI runner

Install/select Xcode with its iOS platform and an available simulator runtime,
CMake 3.22+, Ninja and Git. The unsigned workflow selects Xcode 26.2
on the standard `macos-26` runner and fails clearly if that image/toolchain is unavailable.

```sh
export DEVELOPER_DIR=/Applications/Xcode_26.2.app/Contents/Developer
bash scripts/build-ios-unsigned.sh device
bash scripts/build-ios-unsigned.sh simulator
bash scripts/smoke-ios-simulator.sh
```

The build script bootstraps the exact vcpkg revision in the project, builds
separate SDK-specific static dependencies, inspects the binary platform and
desktop-library exclusions, and writes app/symbol/notice archives plus logs to
`build/ios-{device,simulator}`. No IPA is labeled installable. No artifact is
uploaded by the scripts; the GitHub workflow uploads only the selected
unsigned build and diagnostic outputs with seven-day retention.

The workflow runs only for pushes to `ios/unsigned-feasibility` or manual
dispatch. GitHub requires a manual-only workflow on the default branch before
it can be dispatched, so the restricted branch trigger allows the initial
approved run without changing the default branch. Creating a commit, pushing
that branch and initiating cloud execution still require owner approval. No
workflow has been published or run as part of local preparation.

The shell uses SDL3 callbacks and a native UIKit setup view, so the system owns
the main run loop. The entire OpenLoco core archive is forced into the link,
with LTO and dead stripping disabled for this spike: a successful setup-shell
link must not conceal missing engine symbols. The initial iOS paint option is
serial; desktop builds retain their existing parallel path by default.

The smoke mode renders multiple frames and invokes the real setup button and
cancel/retry handlers on separate run-loop turns. It emits a JSON result and a
simulator screenshot. It is not a gesture/playability test, XCTest tap test,
asset-format validation or physical-device test. Import cancellation/invalid
game-data tests must be added with the actual importer in M6.

Language/OpenGraphics objects and license notices are bundled; original game
files are not. The resource directory is read-only; app-owned files use
Application Support/OpenLoco. Desktop synchronous folder picking deliberately
returns no selection on iOS rather than attempting to use an invalid path grant.

## Windows baseline

With free Visual Studio 2022 C++ tools, Windows SDK, ATL, CMake and the pinned
vcpkg checkout installed, run:

```powershell
.\scripts\build-windows-baseline.ps1 -VcpkgRoot C:\path\to\vcpkg
```

The script records configure/build/CTest results and the actual dependency
versions. A pristine `git archive` can be built separately by passing
`-SourcePath` and its exact `-BaselineCommit`; Git version text in an archive
falls back to the CMake project version because `.git` is absent.

Do not publish the workflow/source or trigger cloud runs without the owner's
approval. Signing, device installation and data import are later gates.
