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
check also requires Metal presentation, a window and setup view filling the
screen in its current portrait or landscape orientation, and an unmodified
screenshot whose pixel dimensions match both the drawable and screen point
dimensions multiplied by display scale. Merely filling a scene does not prove
display coverage: iPadOS may scale a restricted scene into a letterboxed area.
The setup test waits for an active, fully covered display and UIKit's actual
presentation/dismissal completions before each action. Each stage has a 15-second
deadline, with a 90-second overall bound after setup initialization.
The scene manifest uses SDL3's built-in scene delegate. Setup supports all four
iPad orientations in both the plist and SDL hint, and uses a resizable SDL window.
It follows the device without requesting a forced scene orientation. Setup view
edges follow the root; content scrolls within the safe area when space is small.
This adaptive setup policy is separate from future gameplay orientation.
See [Apple's resizing guidance](https://developer.apple.com/documentation/technotes/tn3192-migrating-your-app-from-the-deprecated-uirequiresfullscreen-key).
Normal setup can resize in a smaller window; the canonical simulator smoke
capture deliberately requires a full-display window to detect letterboxing.

Release iOS compilation includes debug information for the app and engine.
Packaging requires the adjacent `OpenLoco.app.dSYM`, an exact architecture/UUID
match with the executable, successful DWARF verification, and compile-unit
information for both `Main.Ios.mm` and the engine's `World/TownManager.cpp`.
Only that dSYM is exported; compiler-probe bundles are ignored. Unexpected ZIPs
already in the artifact staging directory stop packaging and require a clean
build directory. Symbol UUID reports and DWARF verification are kept as evidence.
See [Apple's symbol guidance](https://developer.apple.com/documentation/xcode/building-your-app-to-include-debugging-information)
and [SDL's orientation hint](https://wiki.libsdl.org/SDL3/SDL_HINT_ORIENTATIONS).

The portable audit checks use synthetic resources and can run on Windows/Linux:

```sh
cmake -DTEST_ROOT=/absolute/disposable/test-directory -P scripts/tests/test-ios-bundle-audit.cmake
bash scripts/tests/test-ios-build-selection.sh
python3 scripts/tests/test-ios-evidence.py
cmake -S scripts/tests/ios-smoke -B /absolute/disposable/sequence-build
cmake --build /absolute/disposable/sequence-build --config Release
ctest --test-dir /absolute/disposable/sequence-build -C Release --output-on-failure
python3 scripts/tests/test-ios-simulator-script.py
python3 scripts/tests/test-ios-layout.py
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

The transition sequence is shared with portable C++ regression tests. A button
is dispatched once, then the test waits for its alert's presentation completion;
the next button waits for dismissal completion and an active scene. It requires
two completed presentations, two dismissals, three checks and one cancellation.
Version 3 result JSON records stage, reason, counts, pending transition, interface
orientation, scene geometry, screen bounds/scale and the window frame converted
to screen coordinates. Native geometry checks share a portable C++ helper with
regression tests. The external validator independently checks numerical geometry
and raw PNG dimensions; it accepts either orientation only when coverage matches.
The old portrait screenshot with a landscape drawable still fails. Controlled
failures keep the app visible for evidence and still
fail the external validator; ordinary application exit attempts a failed result
before teardown. Initialization failures before app-state ownership and OS kills
may provide only console evidence. Progress JSON is written at stage boundaries.

The external script allows 300 seconds for UI-test-runner startup, cold Metal
and the bounded app test. It records startup phases and simulator identity, collects progress,
result, screenshot and console before cleanup on success or failure, and preserves
the original command/validation exit status. Cleanup affects only the simulator
created by this invocation. Portable script tests use synthetic tools/PNG headers,
including launch/screenshot failures and a missing result; they do not boot iOS.
The simulator script also enables `--layout-test` and, after validating the
initial setup screenshot, runs `scripts/check-ios-layout.py`. This mode is
simulator-only and absent from normal app startup. Its six mandatory stages are:

| Stage | Required observation |
| --- | --- |
| Landscape left | Interface orientation 3, full display coverage, matching raw PNG/drawable |
| Landscape right | Interface orientation 4, full display coverage, matching raw PNG/drawable |
| Return to portrait | Interface orientation 1 and full display coverage |
| Wide window frame | Actual UIWindow becomes 640 x 480 points at 32,64; drawable resizes |
| Compact window frame | Actual UIWindow becomes 320 x 300 points; content scrolls and the check button is visible |
| Restore full window | Full portrait display coverage and drawable restored |

Rotation is driven by a standalone Objective-C XCUITest bundle in
`scripts/tests/ios-rotation/Rotation.xcodeproj`. It builds only for the simulator,
with signing disabled, on the existing free standard runner. The host installs
the unsigned app; XCUITest establishes portrait, launches that app with the test
flags and waits for session-tagged accessibility values on `setup.check` before
setting `XCUIDevice.orientation`. The app no longer requests scene rotation:
iPadOS rejected that API in the simulator's current windowing mode. The helper
uses device landscape-right for interface landscape-left and vice versa, as
required by UIKit's opposite landscape constants. Native version 2 layout
evidence requires the observed device **and** interface orientations, settled
geometry and fresh rendering. Old scene-request results cannot satisfy it.
Before acknowledging the initial screenshot, the host requires the UI runner's
log marker for the same launch UUID (bounded at 180 seconds); a fast screenshot
cannot advance the app before the UI runner has read the setup session.

Resize probes set the actual UIKit app window's
frame and observe SDL/Metal output; they do not mock geometry or resize only a
child view. They **do not** exercise an iPadOS window-manager drag, Stage Manager
or a physical hardware device. These require separate coverage.

The app requires three ready rendered observations, holds each geometry until
the external driver captures an unmodified whole-display PNG and validates its
JSON, and advances only on an acknowledgement tagged with the current launch's
UUID. Errors, no-op requests, stale sessions, clipped buttons and missing captures
fail. Geometry has a 60-second settle deadline to include UI automation; capture
acknowledgement is bounded at 180 seconds. The driver bounds file waits at 90
seconds and screenshot commands at 120 seconds (the last real baseline capture
took approximately 88 seconds on a cold runner). XCUITest bounds stage-marker
waits at 240 seconds and its final restore wait at 600 seconds, with an overall
test execution limit of 1800 seconds. No wait is evidence of successful rotation.
Resized-window checks compare drawable size with the **window** and raw PNG size
with the **screen**; the initial, rotation and restore checks retain full-display
requirements. Partial-window screenshots intentionally contain area outside the
app window; they cannot replace the final restored full-display evidence.

Evidence is kept under `evidence/layout/` (six raw PNGs, per-stage JSON, native
completion and suite summary), with `ios-layout-progress.json` copied on cleanup.
The native/host layout summary covers geometry and captures. Overall success
also requires the UI test runner to exit zero after native final completion;
runner failure cannot be hidden by a passing layout summary. Evidence includes
`ui-rotation-build.log`, `ui-rotation.log`, `ui-rotation-exit-code.txt` and a unique
`rotation-*.xcresult` bundle. A runner build failure stops before creating a
simulator; early runner exit, geometry rejection and missing captures fail the
job. Cleanup stops only this invocation's child runner and owned simulator and
preserves the original exit status.
The test mode keeps rendering after the initial dialog result instead of freezing
the renderer. No signing, new dependency, paid runner or private API is needed.
Local synthetic fixtures validate the protocol and checks, not UIKit behavior.
See [Apple's device rotation test API](https://developer.apple.com/documentation/xcuiautomation/xcuidevice/orientation),
[opposite landscape constants](https://developer.apple.com/documentation/uikit/uiinterfaceorientation)
and [UIView frame](https://developer.apple.com/documentation/uikit/uiview/frame).

See Apple's [presentation completion](https://developer.apple.com/documentation/uikit/uiviewcontroller/present(_:animated:completion:))
and [dismissal completion](https://developer.apple.com/documentation/uikit/uiviewcontroller/dismiss(animated:completion:))
documentation for the readiness signals.

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
