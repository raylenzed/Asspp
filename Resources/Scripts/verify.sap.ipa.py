#!/usr/bin/env python3
"""Verify the built IPA, including the exact pinned SAP assets."""
import hashlib
import pathlib
import plistlib
import runpy
import struct
import sys
import zipfile

root = pathlib.Path(__file__).resolve().parents[2]
ipa = pathlib.Path(sys.argv[1])
assets = runpy.run_path(str(root / "Resources/Scripts/prepare.sap.runtime.py"))["ASSETS"]
with zipfile.ZipFile(ipa) as archive:
    broken = archive.testzip()
    if broken:
        raise RuntimeError(f"Invalid IPA entry: {broken}")
    info = plistlib.loads(archive.read("Payload/Asspp.app/Info.plist"))
    executable = archive.read("Payload/Asspp.app/" + info["CFBundleExecutable"])
    if executable[:4] != b"\xcf\xfa\xed\xfe" or struct.unpack_from("<I", executable, 4)[0] != 0x0100000C:
        raise RuntimeError("IPA executable is not a 64-bit ARM iOS binary")
    for name in [*assets, "bridge.js", "index.html"]:
        entries = [entry for entry in archive.namelist()
                   if "AppleSAPRuntime" in entry and entry.endswith("/Runtime/" + name)]
        if len(entries) != 1:
            raise RuntimeError(f"Missing or duplicate SAP runtime asset: {name}")
        if name in assets:
            expected = assets[name][1]
        else:
            expected = hashlib.sha256((root / "Packages/ApplePackage/Sources/AppleSAPRuntime/Runtime" / name).read_bytes()).hexdigest()
        if hashlib.sha256(archive.read(entries[0])).hexdigest() != expected:
            raise RuntimeError(f"Packaged SAP asset does not match: {name}")
    print(f'Verified {info["CFBundleIdentifier"]}, version {info["CFBundleShortVersionString"]}, arm64')
    print("IPA integrity and all five local SAP runtime assets verified")
digest = hashlib.sha256(ipa.read_bytes()).hexdigest()
ipa.with_suffix(ipa.suffix + ".sha256").write_text(f"{digest}  {ipa.name}\n")
print(f"IPA SHA-256: {digest}")
