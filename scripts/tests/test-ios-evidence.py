#!/usr/bin/env python3
"""Portable synthetic regressions; these do not execute UIKit or Apple tools."""

import copy
from pathlib import Path
import plistlib
import runpy
import struct
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
CHECKS = runpy.run_path(str(ROOT / "scripts/verify-ios-evidence.py"))
UUID = "01234567-89AB-CDEF-0123-456789ABCDEF"


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.screenshot = self.root / "screen.png"
        # Only a PNG header: fixture for metadata validation, not a rendered image.
        self.png_size(2420, 1668)
        self.result = dict(resultVersion=2, stage="complete", failureReason="",
                           dialogsDismissed=2, presentationPending=False, activeDialog=False,
                           passed=True, gameplayStarted=False, frames=151, checks=3,
                           cancellations=1, dialogsPresented=2, metalRenderer=True,
                           landscapeFillsScene=True, pixelWidth=2420, pixelHeight=1668,
                           sceneWidth=1210, sceneHeight=834, windowWidth=1210,
                           windowHeight=834, setupWidth=1210, setupHeight=834)
        self.app = self.root / "OpenLoco.app"
        self.app.mkdir()
        (self.app / "OpenLoco").write_bytes(b"synthetic app")
        self.dsym = self.root / "OpenLoco.app.dSYM"
        self.dwarf = self.dsym / "Contents/Resources/DWARF/OpenLoco"
        self.dwarf.parent.mkdir(parents=True)
        self.dwarf.write_bytes(b"synthetic DWARF")

    def png_size(self, width, height):
        self.screenshot.write_bytes(b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR" + struct.pack(">II", width, height))

    def smoke(self):
        return CHECKS["verify_smoke"](self.result, self.screenshot)

    def symbols(self, app_arch="arm64", dwarf_arch="arm64", dwarf_uuid=UUID, symbols=None):
        return CHECKS["verify_symbols"](self.app, symbols or self.dsym, "arm64",
                                       f"UUID: {UUID} ({app_arch}) app\n",
                                       f"UUID: {dwarf_uuid} ({dwarf_arch}) symbols\n")

    def test_landscape_full_scene(self):
        self.assertEqual(self.smoke()["screenshotWidth"], 2420)

    def test_previous_portrait_screenshot(self):
        self.png_size(1668, 2420)
        with self.assertRaisesRegex(ValueError, "not landscape"):
            self.smoke()

    def test_geometry_failures(self):
        for key, value in (("windowWidth", 1024), ("setupHeight", 600),
                           ("sceneWidth", 600), ("windowWidth", float("nan")),
                           ("landscapeFillsScene", False), ("pixelWidth", 2048),
                           ("checks", 2), ("metalRenderer", False), ("passed", False)):
            with self.subTest(key=key, value=value):
                original = copy.deepcopy(self.result)
                self.result[key] = value
                with self.assertRaises(ValueError):
                    self.smoke()
                self.result = original

    def test_missing_geometry(self):
        del self.result["landscapeFillsScene"]
        with self.assertRaises(ValueError):
            self.smoke()

    def test_incomplete_transitions(self):
        for key, value in (("stage", "wait-for-cancel-dismissal"), ("failureReason", "transition-timeout"),
                           ("dialogsDismissed", 1), ("presentationPending", True),
                           ("activeDialog", True), ("resultVersion", 1)):
            with self.subTest(key=key):
                original = self.result.copy()
                self.result[key] = value
                with self.assertRaises(ValueError):
                    self.smoke()
                self.result = original

    def test_failure_reports_stage_and_reason(self):
        self.result.update(passed=False, stage="wait-for-second-dialog", failureReason="transition-timeout")
        with self.assertRaisesRegex(ValueError, "wait-for-second-dialog.*transition-timeout"):
            self.smoke()

    def test_stretched_drawable(self):
        self.result["pixelWidth"] = 2400
        self.png_size(2400, 1668)
        with self.assertRaisesRegex(ValueError, "stretched"):
            self.smoke()

    def test_bad_png(self):
        self.screenshot.write_bytes(b"not a PNG")
        with self.assertRaises(ValueError):
            self.smoke()

    def test_matching_symbols(self):
        self.assertTrue(self.symbols()["matched"])

    def test_uuid_and_architecture_mismatches(self):
        for args in ({"dwarf_uuid": "11234567-89AB-CDEF-0123-456789ABCDEF"},
                     {"dwarf_arch": "x86_64"}, {"app_arch": "x86_64"}):
            with self.subTest(args=args), self.assertRaises(ValueError):
                self.symbols(**args)

    def test_missing_or_empty_dwarf(self):
        self.dwarf.write_bytes(b"")
        with self.assertRaises(ValueError):
            self.symbols()
        self.dwarf.unlink()
        with self.assertRaises(ValueError):
            self.symbols()

    def test_compiler_probe_rejected(self):
        with self.assertRaisesRegex(ValueError, "adjacent"):
            self.symbols(symbols=self.root / "boo.app.dSYM")

    def test_invalid_uuid_records(self):
        line = f"UUID: {UUID} (arm64) app\n"
        for text in ("", "unexpected output", line + line, "UUID: bad (arm64) app"):
            with self.subTest(text=text), self.assertRaises(ValueError):
                CHECKS["parse_uuids"](text)

    def test_scene_manifest_and_orientation(self):
        # Plist substitutions are all textual; validate the actual template's XML.
        info = plistlib.loads((ROOT / "distribution/ios/Info.plist.in").read_bytes())
        expected = ["UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"]
        self.assertEqual(info["UISupportedInterfaceOrientations"], expected)
        self.assertEqual(info["UISupportedInterfaceOrientations~ipad"], expected)
        manifest = info["UIApplicationSceneManifest"]
        self.assertFalse(manifest["UIApplicationSupportsMultipleScenes"])
        scene = manifest["UISceneConfigurations"]["UIWindowSceneSessionRoleApplication"][0]
        self.assertEqual(scene["UISceneDelegateClassName"], "SDLUIKitSceneDelegate")


if __name__ == "__main__":
    unittest.main(verbosity=2)
