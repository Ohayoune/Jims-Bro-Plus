#!/usr/bin/env python3
"""Regenerate HANDOFF_BUNDLE.md and JimmsBro-design-package.zip from the folder.

The bundle is one file holding the whole design package, so it can be pasted into a chat with a
coding assistant. The fixtures are not inlined — `tools/generate_fixtures.py` recreates them —
but they are in the zip.

    python3 tools/build_bundle.py

Both outputs are derived: edit the real files, then run this. The zip's `examples/` must stay
byte-identical to what `generate_fixtures.py` produces, so this script refuses to write a zip
whose fixtures differ from the ones on disk.
"""
import hashlib
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# In the order a reader should meet them: the entry point first, the reference tools last.
BUNDLED = [
    "AGENTS.md",
    "README.md",
    "docs/SPEC.md",
    "docs/PLAN_FORMAT.md",
    "docs/PROMPT.md",
    "docs/PROGRESSION_FORMAT.md",
    "docs/TEST_CASES.md",
    "docs/BUILD_PLAN.md",
    "docs/ITERATION_2_PLAN.md",
    "docs/ITERATION_3_PLAN.md",
    "docs/ITERATION_4_PLAN.md",
    "docs/CODE_HEALTH_REVIEW.md",
    "docs/BUILD_STATUS.md",
    "docs/DECISIONS_LOG.md",
    "docs/DEVICE_CHECKLIST.md",
    "docs/COPY_PASTE_NOTES.md",
    "docs/UX_REVIEW.md",
    "schema/plan.schema.json",
    "tools/reference_import.py",
    "tools/generate_fixtures.py",
    "CLAUDE.md",
]

LANGUAGE = {".md": "markdown", ".json": "json", ".py": "python"}

HEADER = """# Jimm's Bro+ — complete handoff bundle

This single file contains the entire design package for a native iOS workout app, so it can be uploaded or pasted into a chat with a coding assistant. The folder version of this package (with 111 fixture files under `examples/`) is the same content; the fixtures are not inlined here because `tools/generate_fixtures.py` (included below) recreates all of them.

The app itself is built: v1 (M0–M7), v1.1 (R0–R6), v1.2 (V0–V7) and v1.3 (X0–X5) are implemented and green. `docs/BUILD_STATUS.md` says what was actually run, and `docs/DECISIONS_LOG.md` records every decision taken where the docs were silent. The Swift sources are not in this bundle — they are in the folder, under `JimmsBro/`, `JimmsBroActivity/` and `JimmsBroTests/`.

How to use this bundle:
1. Read `AGENTS.md` first (immediately below). It says what to read next and the hard rules.
2. Recreate the folder: save each `### FILE:` section below to its path, then run `python3 tools/generate_fixtures.py` and `python3 tools/reference_import.py` (expect "111/111 fixtures match the manifest").
3. Read `docs/BUILD_STATUS.md` to see where the build has got to, then `docs/ITERATION_2_PLAN.md`, `docs/ITERATION_3_PLAN.md` and `docs/ITERATION_4_PLAN.md` for what v1.1, v1.2 and v1.3 were.

Each file below starts with a line `### FILE: <path>` followed by its full content inside a five-backtick fence, so the three- and four-backtick fences inside the documents nest correctly.

---
"""


def build_markdown() -> str:
    parts = [HEADER]
    for name in BUNDLED:
        path = ROOT / name
        if not path.exists():
            raise SystemExit(f"missing {name}")
        language = LANGUAGE.get(path.suffix, "")
        parts.append(f"\n### FILE: {name}\n\n`````{language}\n{path.read_text()}`````\n\n---\n")
    return "".join(parts)


def build_zip(target: Path) -> None:
    """The folder package: the bundled documents plus every fixture, byte for byte."""
    fixtures = sorted(p for p in (ROOT / "examples").rglob("*") if p.is_file())
    existing = {}
    if target.exists():
        with zipfile.ZipFile(target) as old:
            existing = {n: hashlib.sha256(old.read(n)).hexdigest()
                        for n in old.namelist() if n.startswith("examples/")}

    changed = []
    for path in fixtures:
        name = str(path.relative_to(ROOT))
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if name in existing and existing[name] != digest:
            changed.append(name)
    if changed:
        raise SystemExit("refusing to write: these fixtures differ from the published package, "
                         "which is never allowed:\n  " + "\n  ".join(changed))

    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as out:
        for name in BUNDLED + ["HANDOFF_BUNDLE.md"]:
            out.write(ROOT / name, name)
        for path in fixtures:
            out.write(path, str(path.relative_to(ROOT)))


if __name__ == "__main__":
    bundle = ROOT / "HANDOFF_BUNDLE.md"
    bundle.write_text(build_markdown())
    print(f"wrote {bundle.name} ({bundle.stat().st_size:,} bytes, {len(BUNDLED)} files)")
    package = ROOT / "JimmsBro-design-package.zip"
    build_zip(package)
    with zipfile.ZipFile(package) as z:
        print(f"wrote {package.name} ({package.stat().st_size:,} bytes, {len(z.namelist())} entries)")
