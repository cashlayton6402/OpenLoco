#!/usr/bin/env python3
"""Run the real simulator shell script with synthetic tools, never an Apple SDK."""

import json
import os
from pathlib import Path
import plistlib
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
BASH = os.environ.get("OPENLOCO_TEST_BASH", "bash")
MOCK = r'''
import json, os, pathlib, struct, sys
args = sys.argv[1:]
root = pathlib.Path(os.environ["OPENLOCO_MOCK_ROOT"])
mode = os.environ["OPENLOCO_MOCK_MODE"]
with (root / "calls.jsonl").open("a") as log:
    log.write(json.dumps(args) + "\n")
if args[:2] == ["--sdk", "iphonesimulator"]:
    print("26.2")
elif args[:3] == ["simctl", "list", "runtimes"]:
    print(json.dumps({"runtimes":[{"isAvailable":True,"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-26-2","version":"26.2","supportedArchitectures":["x86_64"]}]}))
elif args[:3] == ["simctl", "list", "devicetypes"]:
    print(json.dumps({"devicetypes":[{"productFamily":"iPad","identifier":"com.apple.CoreSimulator.SimDeviceType.iPad-Pro-11-inch-M4"}]}))
elif args[:2] == ["simctl", "create"]:
    print("synthetic-device-only")
elif args[:2] == ["simctl", "launch"]:
    if mode == "launch-failure":
        sys.exit(23)
    data = root / "container/Library/Application Support/OpenLoco"
    data.mkdir(parents=True, exist_ok=True)
    result = dict(resultVersion=2,stage="complete",failureReason="",passed=True,
                  gameplayStarted=False,frames=50,checks=3,cancellations=1,
                  dialogsPresented=2,dialogsDismissed=2,presentationPending=False,
                  activeDialog=False,metalRenderer=True,landscapeFillsScene=True,
                  pixelWidth=2420,pixelHeight=1668,sceneWidth=1210,sceneHeight=834,
                  windowWidth=1210,windowHeight=834,setupWidth=1210,setupHeight=834)
    if mode in ("failed-result", "console-failure"):
        result.update(passed=False,stage="wait-for-cancel-dismissal",failureReason="transition-timeout")
    (data / "ios-smoke-progress.json").write_text(json.dumps(result))
    if mode != "missing-result":
        (data / "ios-smoke-result.json").write_text(json.dumps(result))
    print("io.openloco.ios.development: synthetic-pid")
elif args[:2] == ["simctl", "get_app_container"]:
    print((root / "container").as_posix())
elif args[:2] == ["simctl", "io"]:
    # PNG metadata fixture only, not a screenshot of a running application.
    if mode == "screenshot-failure":
        sys.exit(24)
    pathlib.Path(args[-1]).write_bytes(b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR" + struct.pack(">II",2420,1668))
elif args[:2] == ["simctl", "spawn"]:
    if mode == "console-failure":
        sys.exit(25)
    print("Synthetic simulator console")
elif len(args) > 1 and args[1] in ("terminate", "shutdown", "delete"):
    assert args[2] == "synthetic-device-only", "Attempt to clean up another device"
'''


class SimulatorScriptTests(unittest.TestCase):
    def run_script(self, mode):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        project = root / "project"
        scripts = project / "scripts"
        scripts.mkdir(parents=True)
        for name in ("smoke-ios-simulator.sh", "ios-build-common.sh", "verify-ios-evidence.py"):
            shutil.copyfile(ROOT / "scripts" / name, scripts / name)
        build = project / "build/ios-simulator-intel/evidence"
        build.mkdir(parents=True)
        app = root / "OpenLoco.app"
        app.mkdir()
        (app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "io.openloco.ios.development"}))
        (build / "app-path.txt").write_text(app.as_posix())
        (build / "setup-screen.png").write_bytes(b"stale screenshot")
        (build / "ios-smoke-result.json").write_text('{"passed":true}')
        tools = root / "tools"
        tools.mkdir()
        python = shlex.quote(Path(sys.executable).as_posix())
        (tools / "mock.py").write_text(MOCK)
        wrappers = {
            "python3": f'#!/usr/bin/env bash\nexec {python} "$@"\n',
            "uname": '#!/usr/bin/env bash\ncase "$1" in -s) echo Darwin;; -m) echo x86_64;; *) exit 2;; esac\n',
            "xcrun": f'#!/usr/bin/env bash\nexec {python} {shlex.quote((tools / "mock.py").as_posix())} "$@"\n',
        }
        for name, text in wrappers.items():
            path = tools / name
            path.write_text(text, newline="\n")
            path.chmod(0o755)
        env = os.environ.copy()
        env.update(OPENLOCO_MOCK_ROOT=str(root), OPENLOCO_MOCK_MODE=mode,
                   PATH=str(tools) + os.pathsep + env["PATH"])
        # Advance the parent shell's elapsed clock instead of waiting 180 real
        # seconds for the missing-result scenario. All calls are synthetic.
        command = 'export PATH="$(cd "$1" && pwd):$PATH"; sleep() { SECONDS=$((SECONDS + 180)); }; export -f sleep; source "$0"'
        run = subprocess.run([BASH, "-c", command, (scripts / "smoke-ios-simulator.sh").as_posix(), tools.as_posix()],
                             env=env, capture_output=True, text=True, timeout=30)
        self.assertTrue((build / "simulator-environment.txt").is_file(), run.stdout + run.stderr)
        self.assertTrue((build / "simulator-phases.txt").is_file())
        calls = [json.loads(line) for line in (root / "calls.jsonl").read_text().splitlines()]
        cleanup = [call for call in calls if len(call) > 1 and call[1] in ("terminate", "shutdown", "delete")]
        self.assertEqual([call[1] for call in cleanup], ["terminate", "shutdown", "delete"])
        screen = next(i for i, call in enumerate(calls) if call[:2] == ["simctl", "io"])
        terminate = next(i for i, call in enumerate(calls) if call[:2] == ["simctl", "terminate"])
        self.assertLess(screen, terminate)
        return run, build

    def test_success(self):
        run, evidence = self.run_script("success")
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertTrue(json.loads((evidence / "ios-smoke-result.json").read_text())["passed"])
        self.assertTrue((evidence / "ios-smoke-progress.json").is_file())
        self.assertNotEqual((evidence / "setup-screen.png").read_bytes(), b"stale screenshot")

    def test_failed_result_retains_reason(self):
        run, evidence = self.run_script("failed-result")
        self.assertNotEqual(run.returncode, 0)
        self.assertIn("wait-for-cancel-dismissal", (evidence / "screen-validation.txt").read_text())
        self.assertFalse(json.loads((evidence / "ios-smoke-result.json").read_text())["passed"])

    def test_launch_failure_preserves_exit_code(self):
        run, evidence = self.run_script("launch-failure")
        self.assertEqual(run.returncode, 23, run.stdout + run.stderr)
        self.assertFalse((evidence / "ios-smoke-result.json").exists())
        self.assertTrue((evidence / "simulator-console.txt").is_file())

    def test_screenshot_failure_preserves_exit_code(self):
        run, evidence = self.run_script("screenshot-failure")
        self.assertEqual(run.returncode, 24, run.stdout + run.stderr)
        self.assertTrue((evidence / "ios-smoke-result.json").is_file())

    def test_diagnostic_failure_cannot_mask_test_failure(self):
        run, _ = self.run_script("console-failure")
        self.assertNotEqual(run.returncode, 0)

    def test_missing_result_retains_progress(self):
        run, evidence = self.run_script("missing-result")
        self.assertEqual(run.returncode, 1, run.stdout + run.stderr)
        self.assertFalse((evidence / "ios-smoke-result.json").exists())
        self.assertTrue((evidence / "ios-smoke-progress.json").is_file())
        self.assertIn("180 seconds", run.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
