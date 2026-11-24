#!/usr/bin/env python3
"""Build the Windows feed after signed release assets have been uploaded.
Створює маніфест Windows після завантаження підписаних файлів випуску.
"""

import argparse
import base64
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile


def prepare(version, installer, signature, public_key, previous):
    stable = re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", version)
    if not stable:
        raise ValueError("Expected a stable semantic version")
    with installer.open("rb") as package:
        if installer.name != f"DeepL-oFM_{version}_x64-setup.exe" or package.read(2) != b"MZ":
            raise ValueError("Expected the matching x64 NSIS installer")
        package.seek(0)
        digest = hashlib.file_digest(package, "sha256").hexdigest()

    sig = signature.read_text(encoding="utf-8").strip()
    comment = base64.b64decode(sig, validate=True).decode("utf-8").splitlines()
    if len(comment) != 4 or not comment[2].startswith("trusted comment: ") or (
        f"version:{version}" not in comment[2].split("\t")
        or f"file:{installer.name}" not in comment[2].split("\t")
    ):
        raise ValueError("The signature must identify the actual installer and version")

    key = base64.b64decode(public_key.read_text(encoding="utf-8").strip(), validate=True)
    with tempfile.TemporaryDirectory(prefix="deepl-release-") as temp:
        root = Path(temp)
        (root / "update.pub").write_bytes(key)
        (root / "installer.minisig").write_bytes(base64.b64decode(sig, validate=True))
        subprocess.run(
            ["minisign", "-V", "-q", "-p", str(root / "update.pub"), "-x",
             str(root / "installer.minisig"), "-m", str(installer.resolve())],
            check=True,
        )
    fingerprint = hashlib.sha256(key).hexdigest()
    if previous:
        if fingerprint != previous["public_key_sha256"]:
            raise ValueError("The production updater key changed")
        old_version = tuple(map(int, previous["version"].split(".")))
        if tuple(map(int, stable.groups())) <= old_version:
            raise ValueError("The update must be newer than the published release")

    return {
        "version": version,
        "public_key_sha256": fingerprint,
        "installer_sha256": digest,
        "platforms": {
            "windows-x86_64": {
                "signature": sig,
                "url": "https://github.com/Lexus2016/deepl-on-free-models/releases/download/"
                f"windows-v{version}/{installer.name}",
            }
        },
    }


def main():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("version")
    cli.add_argument("installer", type=Path)
    cli.add_argument("signature", type=Path)
    cli.add_argument("public_key", type=Path)
    cli.add_argument("output", type=Path)
    cli.add_argument("--previous", type=Path)
    args = cli.parse_args()
    previous = json.loads(args.previous.read_text(encoding="utf-8")) if args.previous else None
    try:
        manifest = prepare(args.version, args.installer, args.signature, args.public_key, previous)
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        cli.error(str(error))
    args.output.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
