#!/usr/bin/env python3
"""Export the local compiler ABI, or fail if the checked-in export differs."""

import argparse
import json
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    artifact = "src/LaunchToken.sol:LaunchToken"
    result = subprocess.run(
        ["forge", "inspect", artifact, "abi", "--json"],
        cwd=root,
        check=True,
        capture_output=True,
        text=True,
    )
    abi = json.loads(result.stdout)
    target = root / "docs" / "abi" / "LaunchToken.json"
    if args.check:
        if not target.exists() or json.loads(target.read_text()) != abi:
            raise SystemExit("ABI export is missing or stale; run python3 scripts/export_abi.py")
        print("LaunchToken ABI matches the compiler output.")
    else:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(abi, indent=2) + "\n")
        print("Exported docs/abi/LaunchToken.json")


if __name__ == "__main__":
    main()
