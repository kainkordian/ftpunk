#!/usr/bin/env python3
"""Wrap the compiled shared UI in a local Mac app for device-free debugging."""
import argparse
import plistlib
import shutil
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("binary", type=Path)
parser.add_argument("--output", type=Path, default=Path("/tmp/FTPunkPreview.app"))
args = parser.parse_args()
contents = args.output / "Contents"
(contents / "MacOS").mkdir(parents=True, exist_ok=True)
# Replace atomically so rebuilding does not overwrite a running executable's inode.
staged_binary = contents / "MacOS" / "FTPunkPreview.next"
shutil.copy2(args.binary, staged_binary)
staged_binary.replace(contents / "MacOS" / "FTPunkPreview")
with (contents / "Info.plist").open("wb") as file:
    plistlib.dump({
        "CFBundleIdentifier": "com.kainkordian.ftpunk.preview",
        "CFBundleExecutable": "FTPunkPreview", "CFBundleName": "FTPunk Debug Preview",
        "CFBundleDisplayName": "FTPunk Debug Preview", "CFBundlePackageType": "APPL",
        "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0",
        "NSPrincipalClass": "NSApplication", "LSMinimumSystemVersion": "14.0",
        "NSBluetoothAlwaysUsageDescription": "Connect to cycling devices when real-device mode is explicitly selected.",
        "CFBundleURLTypes": [{"CFBundleURLName": "com.kainkordian.ftpunk.oauth",
                              "CFBundleURLSchemes": ["ftpunk"]}]
    }, file)
subprocess.run(["codesign", "--force", "--sign", "-", str(args.output)], check=True)
print(args.output)
