#!/usr/bin/env python3
"""Fail when HANDOFF_BUNDLE.md or the zip has drifted from the files it is built from.

    python3 tools/check_bundle.py

Both are derived artifacts that are nonetheless committed, because the owner hands them to a
chatbot that cannot read a folder. Committing a derived file is only safe with a check that
says when it has gone stale, which is this one. `tools/build_bundle.py` regenerates them.
"""
import hashlib
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_bundle import BUNDLED, ROOT, build_markdown  # noqa: E402


def main() -> int:
    problems = []

    bundle = ROOT / "HANDOFF_BUNDLE.md"
    if not bundle.exists():
        problems.append("HANDOFF_BUNDLE.md is missing")
    elif bundle.read_text() != build_markdown():
        problems.append("HANDOFF_BUNDLE.md is stale — run tools/build_bundle.py")

    package = ROOT / "JimmsBro-design-package.zip"
    if not package.exists():
        problems.append("JimmsBro-design-package.zip is missing")
    else:
        with zipfile.ZipFile(package) as archive:
            names = set(archive.namelist())
            for name in BUNDLED:
                if name not in names:
                    problems.append(f"zip is missing {name}")
                elif hashlib.sha256(archive.read(name)).hexdigest() != \
                        hashlib.sha256((ROOT / name).read_bytes()).hexdigest():
                    problems.append(f"zip holds a stale {name}")
            for path in sorted(p for p in (ROOT / "examples").rglob("*") if p.is_file()):
                name = str(path.relative_to(ROOT))
                if name not in names:
                    problems.append(f"zip is missing fixture {name}")
                elif hashlib.sha256(archive.read(name)).hexdigest() != \
                        hashlib.sha256(path.read_bytes()).hexdigest():
                    problems.append(f"zip holds a stale fixture {name}")

    if problems:
        print("bundle check failed:")
        for problem in problems:
            print(f"  {problem}")
        return 1
    print(f"bundle is current ({len(BUNDLED)} documents + fixtures)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
