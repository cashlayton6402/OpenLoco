#!/usr/bin/env python3
"""Fail closed on mismatched app symbols or letterboxed simulator evidence."""

import argparse
import json
import math
from pathlib import Path
import re
import struct


def require(condition, message):
    if not condition:
        raise ValueError(message)


def verify_smoke(result, screenshot):
    require(result.get("passed") is True, f"App smoke failed: stage={result.get('stage', 'missing')}; reason={result.get('failureReason', 'missing')}")
    require(result.get("resultVersion") == 2 and result.get("stage") == "complete" and result.get("failureReason") == "", "Missing completed transition evidence")
    require(result.get("dialogsDismissed") == 2 and result.get("presentationPending") is False and result.get("activeDialog") is False, "Dialog transitions did not finish")
    require(result.get("gameplayStarted") is False, "Unexpected gameplay startup")
    require(result.get("frames", 0) > 1, "No sustained presentation")
    require((result.get("checks"), result.get("cancellations"), result.get("dialogsPresented")) == (3, 1, 2), "Setup actions failed")
    require(result.get("metalRenderer") is True, "Metal renderer missing")
    require(result.get("landscapeFillsScene") is True, "Landscape scene coverage missing")
    sizes = []
    for prefix in ("scene", "window", "setup"):
        size = tuple(result.get(prefix + axis, 0) for axis in ("Width", "Height"))
        require(all(isinstance(x, (int, float)) and math.isfinite(x) and x > 0 for x in size), "Invalid UIKit geometry")
        require(size[0] > size[1], "UIKit surface is not landscape")
        sizes.append(size)
    require(all(abs(size[i] - sizes[0][i]) < 1 for size in sizes for i in (0, 1)), "UIKit surfaces do not fill the scene")
    with Path(screenshot).open("rb") as stream:
        header = stream.read(24)
    require(len(header) == 24 and header[:16] == b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR", "Invalid PNG screenshot header")
    pixels = struct.unpack(">II", header[16:24])
    require(pixels[0] > pixels[1] > 0, "Simulator screenshot is not landscape")
    require(pixels == (result.get("pixelWidth"), result.get("pixelHeight")), "Screenshot and drawable sizes differ")
    require(abs(pixels[0] / sizes[0][0] - pixels[1] / sizes[0][1]) < 0.01, "Drawable is stretched relative to the scene")
    return {"screenshotWidth": pixels[0], "screenshotHeight": pixels[1], "landscapeFillsScene": True}


def parse_uuids(text):
    records = {}
    for line in text.splitlines():
        match = re.fullmatch(r"UUID: ([0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}) \(([^)]+)\) .+", line.strip())
        require(match is not None, "Malformed dwarfdump UUID output")
        uuid, arch = match.groups()
        require(arch not in records, "Duplicate architecture in UUID output")
        records[arch] = uuid.upper()
    require(bool(records), "No Mach-O UUIDs found")
    return records


def verify_symbols(app, symbols, architecture, binary_uuids, symbol_uuids):
    app, symbols = Path(app).resolve(), Path(symbols).resolve()
    require(app.name == "OpenLoco.app", "Unexpected app bundle")
    require(symbols == app.with_name("OpenLoco.app.dSYM"), "Symbols must be the app's adjacent dSYM")
    for payload in (app / "OpenLoco", symbols / "Contents/Resources/DWARF/OpenLoco"):
        require(payload.is_file() and payload.stat().st_size > 0, "Missing or empty app/DWARF payload")
    binary, dwarf = parse_uuids(binary_uuids), parse_uuids(symbol_uuids)
    require(set(binary) == {architecture}, "Unexpected app architectures")
    require(binary == dwarf, "App and dSYM UUIDs/architectures differ")
    return {"app": str(app), "symbols": str(symbols), "uuids": binary, "matched": True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    smoke = commands.add_parser("smoke")
    smoke.add_argument("result", type=Path)
    smoke.add_argument("screenshot", type=Path)
    symbols = commands.add_parser("symbols")
    for argument in ("app", "dsym", "architecture", "binary_uuids", "symbol_uuids"):
        symbols.add_argument(argument)
    args = parser.parse_args()
    if args.command == "smoke":
        report = verify_smoke(json.loads(args.result.read_text()), args.screenshot)
    else:
        report = verify_symbols(args.app, args.dsym, args.architecture, Path(args.binary_uuids).read_text(), Path(args.symbol_uuids).read_text())
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
