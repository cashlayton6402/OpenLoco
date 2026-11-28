#!/usr/bin/env python3
"""Capture simulator-only rotation/UIWindow-frame probes without signing or image transforms."""

import argparse
import json
import math
from pathlib import Path
import runpy
import shutil
import struct
import subprocess
import time
import uuid

STEPS = (
    ("landscape-left", 3, 0, 0), ("landscape-right", 4, 0, 0),
    ("portrait-return", 1, 0, 0), ("resize-wide", 1, 640, 480),
    ("resize-compact", 1, 320, 300), ("restore-full", 1, 0, 0),
)
VERIFY = runpy.run_path(str(Path(__file__).with_name("verify-ios-evidence.py")))
require = VERIFY["require"]


def number(value):
    return type(value) in (int, float) and math.isfinite(value)


def verify_snapshot(result, screenshot, expected, session, previous_frames):
    name, orientation, width, height = expected
    require(result.get("layoutVersion") == 1 and result.get("session") == session, "Stale or invalid layout session")
    require(result.get("resultVersion") == 3 and result.get("orientationPolicy") == "adaptive-setup"
            and result.get("layoutSession") == session and result.get("stage") == "complete", "Missing setup/session evidence")
    require(result.get("layoutStep") == name, "Wrong layout step")
    require(result.get("passed") is True, f"Layout failed: {name}: {result.get('failureReason')}; {result.get('geometryError')}")
    require(result.get("geometryError") == "" and result.get("failureReason") == "", "Geometry request failed")
    require(result.get("requestedOrientation") == result.get("interfaceOrientation") == orientation, "Requested orientation was not reached")
    require((result.get("requestedWidth"), result.get("requestedHeight")) == (width, height), "Wrong resize request")
    request_frames, frames, delta = (result.get(key) for key in ("requestFrames", "frames", "framesAfterRequest"))
    require(all(type(x) is int for x in (request_frames, frames, delta)), "Invalid frame counters")
    require(request_frames >= previous_frames and delta >= 3 and frames == request_frames + delta, "Renderer did not present fresh frames after request")
    require(type(result.get("stableFrames")) is int and result["stableFrames"] >= 3, "Geometry did not settle")
    require(result.get("buttonVisible") is True and number(result.get("buttonWidth")) and result["buttonWidth"] > 0
            and number(result.get("buttonHeight")) and result["buttonHeight"] >= 48, "Setup button is clipped or inaccessible")
    require(result.get("metalRenderer") is True and result.get("gameplayStarted") is False, "Wrong renderer or unexpected gameplay")
    require((result.get("checks"), result.get("cancellations"), result.get("dialogsPresented"), result.get("dialogsDismissed")) == (3, 1, 2, 2)
            and result.get("presentationPending") is False and result.get("activeDialog") is False, "Layout changed setup action state")
    if not width:
        require(result.get("operation") == ("window-frame-restore" if name == "restore-full" else "scene-orientation"), "Wrong operation")
        VERIFY["verify_smoke"](result, screenshot)
    else:
        require(result.get("operation") == "window-frame-resize", "Resize was not a UIWindow-frame probe")
        require(result.get("screenX") == result.get("screenY") == 0, "Unexpected screen coordinate origin")
        require(all(number(result.get("scene" + axis)) and number(result.get("screen" + axis))
                    and abs(result["scene" + axis] - result["screen" + axis]) < 1 for axis in ("Width", "Height")), "Resize changed scene/display mapping")
        require(result.get("setupFillsWindow") is True and result.get("windowFitsScreen") is True
                and result.get("drawableMatchesWindow") is True, "Window layout/drawable mismatch")
        scale = result.get("screenScale")
        require(number(scale) and scale > 0, "Invalid scale")
        for prefix in ("window", "setup", "windowScreen"):
            require(all(number(result.get(prefix + axis)) and abs(result[prefix + axis] - size) < 1
                        for axis, size in (("Width", width), ("Height", height))), "Actual window did not resize to requested dimensions")
        require(result.get("windowScreenX") == 32 and result.get("windowScreenY") == 64, "Actual window did not move to probe position")
        require(all(number(result.get("screen" + axis)) and result["screen" + axis] >= size + margin
                    for axis, size, margin in (("Width", width, 32), ("Height", height, 64))), "Resized window exceeds screen")
        require(result.get("windowFillsScreen") is False, "Resize is still a fullscreen/no-op observation")
        require((result.get("pixelWidth"), result.get("pixelHeight")) == (width * scale, height * scale), "Drawable did not resize")
        with Path(screenshot).open("rb") as stream:
            header = stream.read(24)
        require(len(header) == 24 and header[:16] == b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR", "Invalid raw screenshot")
        pixels = struct.unpack(">II", header[16:24])
        require(pixels == (result["screenWidth"] * scale, result["screenHeight"] * scale), "Raw screenshot no longer matches whole display")
        require(number(result.get("scrollHeight")) and result["scrollHeight"] > 0 and number(result.get("contentHeight")), "Scroll measurements missing")
        if name == "resize-compact":
            require(result["contentHeight"] > result["scrollHeight"], "Compact probe did not exercise scrolling")
    return frames


def wait_json(path, timeout, clock=time.monotonic, pause=time.sleep):
    deadline = clock() + timeout
    while clock() < deadline:
        if path.is_file():
            return json.loads(path.read_text())
        pause(0.2)
    raise TimeoutError(f"Layout evidence did not arrive: {path.name}")


def write_ack(folder, session, step):
    temporary = folder / "ios-layout-ack.tmp"
    temporary.write_text(json.dumps(dict(session=session, step=step)))
    temporary.replace(folder / "ios-layout-ack.json")


def capture(device, path):
    try:
        tool = shutil.which("xcrun")
        require(tool is not None, "xcrun screenshot tool not found")
        subprocess.run([tool, "simctl", "io", device, "screenshot", str(path)], check=True, timeout=45, capture_output=True, text=True)
    except subprocess.CalledProcessError as error:
        raise RuntimeError(f"Raw screenshot failed: {error.stderr}") from error


def run_suite(device, folder, evidence, baseline, capture_screen=capture, wait=wait_json):
    session = baseline.get("layoutSession")
    target = evidence / "layout"
    target.mkdir(parents=True, exist_ok=True)
    summary = dict(passed=False, session=session, steps=[], resizeScope="actual-UIWindow-frame; not-iPadOS-window-manager-drag")
    try:
        require(type(session) is str and str(uuid.UUID(session)).upper() == session.upper(), "Simulator layout mode/session missing")
        write_ack(folder, session, "setup")
        previous_frames = baseline["frames"]
        for expected in STEPS:
            name = expected[0]
            result = wait(folder / f"ios-layout-{name}.json", 45)
            (target / f"{name}.json").write_text(json.dumps(result, indent=2))
            screenshot = target / f"{name}.png"
            capture_screen(device, screenshot)  # Capture failures too; never transform the image.
            previous_frames = verify_snapshot(result, screenshot, expected, session, previous_frames)
            summary["steps"].append(dict(name=name, passed=True, frames=previous_frames))
            write_ack(folder, session, name)
        completion = wait(folder / "ios-layout-complete.json", 45)
        (target / "completion.json").write_text(json.dumps(completion, indent=2))
        require(completion.get("passed") is True and completion.get("layoutVersion") == 1
                and completion.get("session") == session and completion.get("stepsCompleted") == len(STEPS), "Native suite did not acknowledge every capture and restore")
        summary["passed"] = True
    except Exception as error:
        summary["error"] = str(error)
        raise
    finally:
        (target / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    return summary


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("device")
    parser.add_argument("container", type=Path)
    parser.add_argument("evidence", type=Path)
    args = parser.parse_args()
    baseline = json.loads((args.evidence / "ios-smoke-result.json").read_text())
    VERIFY["verify_smoke"](baseline, args.evidence / "setup-screen.png")
    print(json.dumps(run_suite(args.device, args.container / "Library/Application Support/OpenLoco", args.evidence, baseline), indent=2))
