# OpenRCT2 reference review for the OpenLoco iPad port

Reviewed 2026-11-26. Reference checkouts are outside the OpenLoco checkout and
are not application dependencies.

| Reference | Pinned commit | Relevant implementation |
| --- | --- | --- |
| [OpenRCT2](https://github.com/OpenRCT2/OpenRCT2/tree/b50a1970d9cc3e8a7df30ff23dbafacf6217efe4) | `b50a1970d9cc3e8a7df30ff23dbafacf6217efe4` | `src/openrct2-ui/UiContext.cpp`, `src/openrct2/platform/Platform.Android.cpp`, `src/openrct2-android/` |
| [OpenRCT2Touch](https://github.com/chrissotraidis/OpenRCT2Touch/tree/3fe2c917c35d529bf81d3a1863ceee318d27515a) | `3fe2c917c35d529bf81d3a1863ceee318d27515a` | `ios/`, `scripts/verify-ios-bundle.sh`, `scripts/run-ios-sim.sh`, `docs/TOUCH-CONTROLS.md`, `docs/DEVELOPMENT-STATUS.md` |

Upstream provides Android support. The iPad work inspected here belongs to the
separate, unofficial OpenRCT2Touch fork. Its status document reports physical
iPad Files import, persistence and scenario loading, with further acceptance
and performance checks outstanding. Those results have not been reproduced
for OpenLoco.

## Licence and implementation boundary

OpenLoco source is MIT licensed. OpenRCT2 and OpenRCT2Touch are GPLv3-or-later.
MIT compatibility does not mean GPL source can be incorporated into a combined
program and distributed solely under MIT; see the GNU project's
[licence compatibility guidance](https://www.gnu.org/licenses/license-compatibility.html).

No GPL code, scripts, patches, translated implementations or game assets were
added. The changes here are newly written OpenLoco implementations of general
platform and verification requirements. Direct source reuse would require
permission from the relevant copyright holders or an explicitly reviewed
GPL-compliant distribution arrangement. OpenLoco's licence was not changed;
the separate OpenAL distribution obligations are not resolved by this review.

## Applied to the current setup build

### Resource inventory and bundled notices

OpenRCT2Touch audits its output bundle, not just its source tree. OpenLoco's new
`scripts/audit-ios-bundle.cmake` implements an independent resource inventory:

- Languages and OpenGraphics objects must match their source bytes. An arbitrary
  `.dat` extension is not enough to admit a file.
- Missing/modified resources, conflicting flattened object names, extra files,
  unexpected directories, raw asset catalogs, links and signing payloads fail.
- Project, OpenGraphics and installed target-dependency notices are staged inside
  `Licences/` and verified against their sources, so they travel with an extracted
  app rather than only in a companion ZIP.
- Executable, plist, compiled catalog and generated icon names have explicit
  inventory exceptions. Optional `PkgInfo` must identify an eight-byte application
  package. Actual Mach-O, platform and desktop-library checks remain in the
  existing macOS build script.
- The report begins incomplete, preventing stale success after a failed rerun.

Both release presets request `IosBundleAudit`, which depends on `App` and audits
on every invocation, including otherwise unchanged builds. The build script
packages only after that target succeeds. Building `App` alone is not the audited
packaging path. Notice staging is restricted to unsigned bundles.

The copied OpenGraphics MIT notice is unchanged from `v0.1.13`, the object release
already pinned in root CMake. That tag resolves to
[8419b5addff8d0d9b9f74055f4813d4f2d6e8674](https://github.com/OpenLoco/OpenGraphics/blob/8419b5addff8d0d9b9f74055f4813d4f2d6e8674/LICENSE).

Ten synthetic test scenarios exercise valid staging and the rejection paths.
The changed-object scenario also tests a passing run followed by a failing
incremental run. No game data, real signing payload or Apple executable is used.
A standard Ubuntu workflow job runs these checks before the Mac jobs.

### Explicit Metal presentation

The iPad reference retains its software game renderer and presents using SDL/Metal.
OpenLoco already has a software drawing engine and SDL streaming textures, so
replacing its renderer with OpenRCT2's is unnecessary.

The current setup shell now requests SDL's Metal renderer explicitly. Its smoke
result records Metal selection and drawable pixel dimensions, and the simulator
check requires both. This proves the setup presentation path only when actually
executed; gameplay rendering remains a separate milestone.

## Transfer plan for later OpenLoco milestones

| Area | Reference | Application and acceptance check |
| --- | --- | --- |
| Files import | Touch `ios/platform/RCT2Importer.iOS.mm` | Native folder selection, scoped access and coordinated reads; copy to private staging, validate Locomotion data, replace with rollback. Test cancellation, cloud read errors, insufficient storage and interrupted replacement. |
| Sandbox roots | Touch `Platform.iOS.mm`; upstream Android platform layer | Keep shipped resources read-only. Separate imported data, saves, config and cache. Persist a private install location, not an expiring picker URL; test relaunch and app replacement. |
| Touch/pointer input | Touch `TOUCH-CONTROLS.md` and UI dispatch; upstream `UiContext.cpp` | Preserve OpenLoco mouse/keyboard dispatch. Distinguish real pointers from synthetic touch mouse events. Cancel tentative placement when multi-touch navigation wins. Validate tracks, stations, signals, vehicle tools and window dragging. |
| Text entry | Touch `UiContext.iOS.mm` | Native input with hardware-keyboard support. Test composition, backspace, shortcuts and focus loss against OpenLoco's text path. |
| Retina/layout | Touch UI scaling and lifecycle diagnostics | Separate logical coordinates from drawable pixels; respect safe areas. Check orientations, iPad sizes and scaled hit testing. |
| Lifecycle | Touch `AppLifecycle.iOS.mm` and simulator harness | Extend the current background render pause to engine timing, audio, input cancellation and safe saves. Test resume and memory pressure when gameplay exists. |
| Verification | Touch dependency, build and simulator scripts | Separate dependency compile, full link, visible launch, import recovery and gameplay gates. Capture logs/screenshots and retain physical-device feel/performance checks. |

OpenLoco's current installation discovery in `src/OpenLoco/src/Environment.cpp`
checks `Data/g1.DAT`; existence alone is not a complete importer validator.
Locomotion's readable data/object requirements must be checked independently.
RCT2 data layouts, scenarios and validation rules cannot be substituted.
No importer or gameplay gesture implementation was added in this pass.

The upstream Android gesture mapping is not an iPad specification. Touch's
gesture arbitration is a useful design reference, but its timings and ride-tool
actions are experiments for a different game. Pointer-first OpenLoco gameplay
is the smallest useful step before train-construction gestures.

## What cannot be transplanted directly

- These OpenRCT2 references use SDL2; OpenLoco uses SDL3. Entry points, events,
  window properties and error/return conventions differ. Touch's SDL2 UIKit
  lifecycle patch must not be applied to OpenLoco's SDL3 dependency.
- Ride simulation, game commands, save formats, scripting and proprietary RCT
  assets are game-specific. Related ancestry does not make them interchangeable.
- Signing identities, team/device settings and their bundle identifier are not
  part of this port.
- Their workflows also need hosted Macs. This reference does not remove Apple's
  SDK requirement or GitHub's runner-capacity constraint.

## Verification limits

Windows can run the synthetic resource checks, workflow validation, preset JSON
parsing, formatting and shell syntax checks. The changed UIKit/Metal code and
Xcode audit target still require an actual SDK build and simulator execution.
Fixture success does not prove gameplay, device performance, an installable
unsigned device app or complete distribution compliance.

This review adds no commit, push, cloud run, signing operation or paid service.
The subsequent Intel runner fallback is prepared locally as a separate step:
the iPad target remains ARM64 and the Intel simulator uses x86-64. It does not
claim ARM64 simulator execution or physical-device validation.
