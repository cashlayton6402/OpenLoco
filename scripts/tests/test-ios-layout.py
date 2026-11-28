#!/usr/bin/env python3
"""Portable protocol/validator checks with synthetic metadata and PNG headers."""

import json
from pathlib import Path
import runpy
import struct
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
DRIVER = runpy.run_path(str(ROOT / "scripts/check-ios-layout.py"))
FIXTURES = runpy.run_path(str(Path(__file__).with_name("ios-layout-fixtures.py")))


class LayoutTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.baseline = FIXTURES["baseline"]()
        self.results = FIXTURES["snapshots"](self.baseline)
        self.png = self.root / "capture.png"

    def image_for(self, result, path=None):
        path = path or self.png
        path.write_bytes(b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR" + struct.pack(">II", result["screenWidth"]*2, result["screenHeight"]*2))

    def verify(self, result, index=0):
        return DRIVER["verify_snapshot"](result, self.png, DRIVER["STEPS"][index], self.baseline["layoutSession"], self.baseline["frames"])

    def test_all_rotation_resize_restore_snapshots(self):
        self.assertEqual(DRIVER["STEPS"], FIXTURES["PLAN"])
        for index, result in enumerate(self.results):
            with self.subTest(step=result["layoutStep"]):
                self.image_for(result)
                self.assertGreater(self.verify(result, index), self.baseline["frames"])

    def test_failures_cannot_be_reported_as_coverage(self):
        changes = ({"session": "stale"}, {"layoutStep": "wrong"}, {"interfaceOrientation": 1},
                   {"framesAfterRequest": 0}, {"stableFrames": 2}, {"buttonVisible": False},
                   {"buttonHeight": 10}, {"passed": False}, {"geometryError": "timeout"},
                   {"requestFrames": 0}, {"frames": 50}, {"checks": 4})
        for change in changes:
            with self.subTest(change=change):
                result = {**self.results[0], **change}
                self.image_for(self.results[0])
                with self.assertRaises(ValueError): self.verify(result)

    def test_resize_must_change_window_and_drawable(self):
        for change in ({"windowWidth": 834}, {"pixelWidth": 1668}, {"windowScreenY": 0},
                       {"windowFillsScreen": True}, {"contentHeight": 100}, {"operation": "scene-orientation"},
                       {"sceneWidth": 320}, {"screenWidth": float("nan")}, {"layoutSession": "stale"}):
            with self.subTest(change=change):
                result = {**self.results[4], **change}
                self.image_for(self.results[4])
                with self.assertRaises(ValueError): self.verify(result, 4)

    def test_portrait_raw_image_cannot_prove_landscape(self):
        self.image_for(self.results[2])
        with self.assertRaises(ValueError): self.verify(self.results[0])

    def test_initial_portrait_result_is_not_rotation_coverage(self):
        self.image_for(self.baseline)
        with self.assertRaises(ValueError): self.verify(self.baseline)

    def test_suite_requires_every_ack_and_restoration(self):
        folder, evidence = self.root / "container", self.root / "evidence"
        folder.mkdir()
        evidence.mkdir()
        for result in self.results:
            (folder / f"ios-layout-{result['layoutStep']}.json").write_text(json.dumps(result))
        completion = dict(layoutVersion=1, passed=True, session=self.baseline["layoutSession"], stepsCompleted=6)
        (folder / "ios-layout-complete.json").write_text(json.dumps(completion))
        captured = []
        def capture(device, path):
            captured.append(path.stem)
            result = next(result for result in self.results if result["layoutStep"] == path.stem)
            self.image_for(result, path)
        summary = DRIVER["run_suite"]("synthetic-only", folder, evidence, self.baseline, capture_screen=capture)
        self.assertTrue(summary["passed"])
        self.assertEqual(captured, [step[0] for step in DRIVER["STEPS"]])
        ack = json.loads((folder / "ios-layout-ack.json").read_text())
        self.assertEqual(ack, dict(session=self.baseline["layoutSession"], step="restore-full"))
        completion["stepsCompleted"] = 5
        (folder / "ios-layout-complete.json").write_text(json.dumps(completion))
        with self.assertRaises(ValueError): DRIVER["run_suite"]("synthetic-only", folder, evidence, self.baseline, capture_screen=capture)
        self.assertFalse(json.loads((evidence / "layout/summary.json").read_text())["passed"])

    def test_timeout_is_bounded(self):
        ticks = iter((0, 0.5, 2))
        with self.assertRaises(TimeoutError): DRIVER["wait_json"](self.root / "absent.json", 1, clock=lambda: next(ticks), pause=lambda _: None)

    def test_failed_capture_never_acknowledges_stage(self):
        folder, evidence = self.root / "container", self.root / "evidence"
        folder.mkdir()
        evidence.mkdir()
        (folder / "ios-layout-landscape-left.json").write_text(json.dumps(self.results[0]))
        def failed_capture(device, path):
            raise RuntimeError("synthetic screenshot failure")
        with self.assertRaises(RuntimeError):
            DRIVER["run_suite"]("synthetic-only", folder, evidence, self.baseline, capture_screen=failed_capture)
        self.assertEqual(json.loads((folder / "ios-layout-ack.json").read_text())["step"], "setup")
        summary = json.loads((evidence / "layout/summary.json").read_text())
        self.assertFalse(summary["passed"])
        self.assertIn("screenshot failure", summary["error"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
