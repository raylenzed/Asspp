#!/usr/bin/env python3
"""Fetch immutable SAP runtime assets and verify SHA-256 before packaging."""
import hashlib
import pathlib
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]
TARGET = ROOT / "Packages/ApplePackage/Sources/AppleSAPRuntime/Runtime"
REVISION = "620649f818926a6c313c2cf3d4555ae4c318ffa1"
BASE = f"https://raw.githubusercontent.com/dompling/Jsbox-Ipa/{REVISION}/"
ASSETS = {
    "sap.wasm": ("sap-signer/sap.wasm", "65ac4163bc0ecc19dc7ed07c2a97238a36e207d6cac062f71f081e9ee844df0a"),
    "unicorn_x86.js": ("jsbox-asspp/assets/sap/unicorn_x86.js", "9b6725926ab449fea9ab36ccbb244db6930aa20c15d36fd46262667be29578ec"),
    "wasm_exec.js": ("jsbox-asspp/assets/sap/wasm_exec.js", "0c949f4996f9a89698e4b5c586de32249c3b69b7baadb64d220073cc04acba14"),
}


def prepare():
    TARGET.mkdir(parents=True, exist_ok=True)
    for name, (source, digest) in ASSETS.items():
        destination = TARGET / name
        if destination.exists() and hashlib.sha256(destination.read_bytes()).hexdigest() == digest:
            print(f"Verified {name}")
            continue
        with urllib.request.urlopen(BASE + source, timeout=120) as response:
            data = response.read(64 * 1024 * 1024 + 1)
        if hashlib.sha256(data).hexdigest() != digest:
            raise RuntimeError(f"SAP asset integrity check failed: {name}")
        temporary = destination.with_suffix(destination.suffix + ".download")
        temporary.write_bytes(data)
        temporary.replace(destination)
        print(f"Prepared {name} ({len(data)} bytes)")


def prepare_public_certificates():
    # These are upstream's publicly distributed localhost OTA test assets.
    # The private build source snapshot contains no PEM files.
    revision = "caed708182c61897bd539557a10618f9b0eba066"
    directory = ROOT / "Certificates/localhost.qaq.wiki"
    directory.mkdir(parents=True, exist_ok=True)
    hashes = {
        "localhost.qaq.wiki-key.pem": "bcdb0838aab25b4097c3d1164bf05ed87da6670396815dbf9cf2549c29249987",  # SHA-256 of upstream's public OTA test key; gitleaks:allow
        "localhost.qaq.wiki.pem": "d3baf6b059e5e8867e073112c4b8e300e8985979d877ed492cba76118a91e722",
        "rootCA.pem": "08e67178ce9004c7215dcba169fbf3e537ca6ced665fd538a2b1d602b44446cb",
    }
    for name, digest in hashes.items():
        destination = directory / name
        if destination.exists():
            if hashlib.sha256(destination.read_bytes()).hexdigest() != digest:
                raise RuntimeError(f"Refusing to replace an existing certificate: {name}")
            continue
        url = f"https://raw.githubusercontent.com/Lakr233/Asspp/{revision}/Certificates/localhost.qaq.wiki/{name}"
        with urllib.request.urlopen(url, timeout=30) as response:
            data = response.read(65537)
        if hashlib.sha256(data).hexdigest() != digest:
            raise RuntimeError(f"Upstream test certificate integrity check failed: {name}")
        destination.write_bytes(data)
        print(f"Prepared upstream public test asset: {name}")


if __name__ == "__main__":
    prepare()
    if "--public-certificates" in sys.argv:
        prepare_public_certificates()
