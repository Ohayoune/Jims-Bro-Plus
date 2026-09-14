#!/usr/bin/env python3
"""Regenerate HANDOFF_BUNDLE.md and JimmsBro-design-package.zip from the folder.

The bundle is one file holding the whole design package, so it can be pasted into a chat with a
coding assistant. The fixtures are not inlined — `tools/generate_fixtures.py` recreates them —
but they are in the zip.

    python3 tools/build_bundle.py

Both outputs are derived: edit the real files, then run this. The zip's `examples/` must stay
byte-identical to what `generate_fixtures.py` produces, so this script refuses to write a zip
whose fixtures differ from the published ones — unless `--regenerated` is passed, which lifts
the guard only after proving the fixtures on disk are exactly what the generator makes (v1.5:
a feature that adds fixtures does so through the generator, never by hand).
"""
import hashlib
import subprocess
import sys
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
    "docs/ITERATION_5_PLAN.md",
    "docs/ITERATION_6_PLAN.md",
    "docs/ITERATION_7_PLAN.md",
    "docs/ITERATION_8_PLAN.md",
    "docs/ITERATION_9_PLAN.md",
    "docs/ITERATION_10_PLAN.md",
    "docs/PRIVACY.md",
    "docs/APP_STORE.md",
    "docs/CODE_HEALTH_REVIEW.md",
    "docs/BUILD_STATUS.md",
    "docs/DECISIONS_LOG.md",
    "docs/DEVICE_CHECKLIST.md",
    "docs/COPY_PASTE_NOTES.md",
    "docs/UX_REVIEW.md",
    "docs/UX_REVIEW_2026-09-09.md",
    "schema/plan.schema.json",
    "tools/reference_import.py",
    "tools/generate_fixtures.py",
    "CLAUDE.md",
]

LANGUAGE = {".md": "markdown", ".json": "json", ".py": "python"}

HEADER = """# Jimm's Bro+ — complete handoff bundle

This single file contains the entire design package for a native iOS workout app, so it can be uploaded or pasted into a chat with a coding assistant. The folder version of this package (with 115 fixture files under `examples/`) is the same content; the fixtures are not inlined here because `tools/generate_fixtures.py` (included below) recreates all of them.

The app itself is built: v1 (M0–M7), v1.1 (R0–R6), v1.2 (V0–V8), v1.3 (X0–X6), v1.4 (Y0–Y5), v1.5 (Z0–Z6) and v1.6 (U0–U3, U5, U6; U4 waits on the owner) are implemented and green. `docs/BUILD_STATUS.md` says what was actually run, and `docs/DECISIONS_LOG.md` records every decision taken where the docs were silent. The Swift sources are not in this bundle — they are in the folder, under `JimmsBro/`, `JimmsBroActivity/` and `JimmsBroTests/`.

How to use this bundle:
1. Read `AGENTS.md` first (immediately below). It says what to read next and the hard rules.
2. Recreate the folder: save each `### FILE:` section below to its path, then run `python3 tools/generate_fixtures.py` and `python3 tools/reference_import.py` (expect "115/115 fixtures match the manifest").
3. Read `docs/BUILD_STATUS.md` to see where the build has got to, then `docs/ITERATION_2_PLAN.md` through `docs/ITERATION_6_PLAN.md` for what v1.1 to v1.5 were.

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


def fixture_digests() -> dict:
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted((ROOT / "examples").rglob("*")) if p.is_file()}


def build_zip(target: Path, regenerated: bool = False) -> None:
    """The folder package: the bundled documents plus every fixture, byte for byte."""
    fixtures = sorted(p for p in (ROOT / "examples").rglob("*") if p.is_file())
    existing = {}
    if target.exists():
        with zipfile.ZipFile(target) as old:
            existing = {n: hashlib.sha256(old.read(n)).hexdigest()
                        for n in old.namelist() if n.startswith("examples/")}

    on_disk = fixture_digests()
    changed = [name for name, digest in on_disk.items() if name in existing and existing[name] != digest]
    if changed and not regenerated:
        raise SystemExit("refusing to write: these fixtures differ from the published package, "
                         "which is never allowed by hand. If a feature added or changed them through "
                         "tools/generate_fixtures.py, run this with --regenerated.\n  " + "\n  ".join(changed))
    if changed:
        # The proof: regenerating changes nothing, so what is on disk is the generator's output.
        subprocess.run([sys.executable, str(ROOT / "tools" / "generate_fixtures.py")], check=True,
                       capture_output=True)
        if fixture_digests() != on_disk:
            raise SystemExit("refusing to write: the fixtures on disk are not what "
                             "tools/generate_fixtures.py produces. Regenerate them and run again.")
        print("fixtures changed through the generator: " + ", ".join(changed))

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
    build_zip(package, regenerated="--regenerated" in sys.argv)
    with zipfile.ZipFile(package) as z:
        print(f"wrote {package.name} ({package.stat().st_size:,} bytes, {len(z.namelist())} entries)")
