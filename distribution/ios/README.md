# Unsigned iPad feasibility target (M0–M3)

This target builds the native engine and an asset-free iOS setup shell. It does
not start gameplay, import Locomotion data, or provide finished touch controls.
No signing credentials, Apple membership, paid service or game data is needed
for compilation and simulator testing. Unsigned device bundles cannot launch
on a stock iPad.

## Build on an Intel or Apple Silicon Mac

Install/select Xcode with its iOS platform and an available simulator runtime,
CMake 3.22+, Ninja and Git. The unsigned workflow selects Xcode 26.2
on the standard `macos-26-intel` runner and fails clearly if that image/toolchain
is unavailable. These standard runners are free for public repositories; no
larger/custom runner is configured. The Intel fallback is prepared locally and
requires review/approval before publication and execution.

```sh
export DEVELOPER_DIR=/Applications/Xcode_26.2.app/Contents/Developer
bash scripts/build-ios-unsigned.sh device
bash scripts/build-ios-unsigned.sh simulator
bash scripts/smoke-ios-simulator.sh
```

The build script bootstraps the exact vcpkg revision in the project, builds
separate SDK-specific static dependencies, inspects the binary platform and
desktop-library exclusions, and writes app/symbol/notice archives plus logs to
the build directories below. No IPA is labeled installable. No artifact is
uploaded by the scripts; the GitHub workflow uploads only the selected
unsigned build and diagnostic outputs with seven-day retention.

| Mac host | Build | App architecture | Preset / build directory |
| --- | --- | --- | --- |
| Intel or Apple Silicon | Real iPad, unsigned | ARM64 | `ios-device` / `build/ios-device` |
| Intel | iPad simulator | x86-64 | `ios-simulator-intel` / `build/ios-simulator-intel` |
| Apple Silicon | iPad simulator | ARM64 | `ios-simulator` / `build/ios-simulator` |

Both scripts select the simulator preset from the actual Mac host architecture.
The device target always selects ARM64. Dependency installations, output bundles
and evidence for the two simulator architectures stay in separate directories.
The prepared CI jobs use Intel hosts for both the ARM64 device cross-build and
the x86-64 simulator test. A passing Intel simulator test does not establish
ARM64 simulator execution or physical-device behavior.
The Metal presentation check remains enabled. If the hosted simulator cannot
provide a working Metal device, the smoke check must fail and preserve its
diagnostics; it must not silently substitute a renderer and claim Metal passed.

Select an installed iOS simulator runtime compatible with Xcode 26.2. Intel Macs
need the universal runtime variant; an Apple-Silicon-only runtime cannot boot on
Intel. The launch script filters declared runtime architectures, checks the app's
architecture and rejects absent compatible runtimes. It does not automatically
download a large replacement or select a runtime newer than the chosen SDK.
See [Apple's component installation documentation](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components).

The release presets build `IosBundleAudit` (which depends on `App`) before
packaging. This stages notices inside the app and checks the resource inventory
against the source checkout and installed dependency notices. The setup smoke
check also requires Metal presentation and nonzero drawable pixel dimensions.

The portable audit checks use synthetic resources and can run on Windows/Linux:

```sh
cmake -DTEST_ROOT=/absolute/disposable/test-directory -P scripts/tests/test-ios-bundle-audit.cmake
bash scripts/tests/test-ios-build-selection.sh
```

See [the OpenRCT2 comparison](OPENRCT2-COMPARISON.md) for the pinned references,
licensing boundary, changes applied here and the import/input transfer plan.

The workflow runs only for pushes to `ios/unsigned-feasibility` or manual
dispatch. GitHub requires a manual-only workflow on the default branch before
it can be dispatched, so the restricted branch trigger allows the initial
approved run without changing the default branch. Creating a commit, pushing
that branch and initiating cloud execution still require owner approval. No
new workflow run is initiated by local preparation. Earlier approved runs and
their capacity failures are recorded separately in the local build evidence.

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
