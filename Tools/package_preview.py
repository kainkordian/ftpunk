#!/usr/bin/env python3
"""Wrap the compiled shared UI in a local Mac app for device-free debugging."""
import argparse
import plistlib
import shutil
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("binary", type=Path)
parser.add_argument("--output", type=Path)
parser.add_argument("--production", action="store_true", help="Package a persistent, full local Mac app")
args = parser.parse_args()
if args.output is None:
    args.output = Path("dist/FTPunk.app") if args.production else Path("/tmp/FTPunkPreview.app")
executable = "FTPunk" if args.production else "FTPunkPreview"
contents = args.output / "Contents"
(contents / "MacOS").mkdir(parents=True, exist_ok=True)
(contents / "Resources").mkdir(parents=True, exist_ok=True)
icon = Path(__file__).resolve().parents[1] / "design" / "app-icon" / "FTPunk.icns"
shutil.copy2(icon, contents / "Resources" / "FTPunk.icns")
# Replace atomically so rebuilding does not overwrite a running executable's inode.
staged_binary = contents / "MacOS" / (executable + ".next")
shutil.copy2(args.binary, staged_binary)
staged_binary.replace(contents / "MacOS" / executable)
with (contents / "Info.plist").open("wb") as file:
    plistlib.dump({
        "CFBundleIdentifier": "com.kainkordian.ftpunk.mac" if args.production else "com.kainkordian.ftpunk.preview",
        "CFBundleExecutable": executable, "CFBundleName": "FTPunk" if args.production else "FTPunk Debug Preview",
        "CFBundleDisplayName": "FTPunk" if args.production else "FTPunk Debug Preview", "CFBundlePackageType": "APPL",
        "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0",
        "CFBundleIconFile": "FTPunk.icns",
        "NSPrincipalClass": "NSApplication", "LSMinimumSystemVersion": "14.0",
        "NSBluetoothAlwaysUsageDescription": "Connect to cycling devices when real-device mode is explicitly selected.",
        "CFBundleURLTypes": [{"CFBundleURLName": "com.kainkordian.ftpunk.oauth",
                              "CFBundleURLSchemes": ["ftpunk"]}]
    }, file)
subprocess.run(["codesign", "--force", "--sign", "-", str(args.output)], check=True)
print(args.output)
