#!/usr/bin/env python3
"""Check the facts about the build that App Store Connect will check (v1.4, D49).

    python3 tools/check_release.py

Static checks only, on the host, with no Xcode: the icon has no alpha channel, the three
targets agree on a version and the submission page says the same, the export-compliance
answer is in the app target, the extension does not hard-code a version of its own, the
privacy policy and the submission page exist, and every built-in plan the catalogue names is
in the bundle and in the project. A Release build (`xcodebuild build -configuration Release`)
is the other half, and needs Xcode; BUILD_STATUS records when it was last run.
"""
import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "JimmsBro.xcodeproj" / "project.pbxproj"
ICON = ROOT / "JimmsBro/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
ICON_CONTENTS = ICON.parent / "Contents.json"
EXTENSION_PLIST = ROOT / "JimmsBroActivity/Info.plist"
CATALOGUE = ROOT / "JimmsBro/Core/BuiltInPlans.swift"
RESOURCES = ROOT / "JimmsBro/Resources"
PRIVACY = ROOT / "docs/PRIVACY.md"
SUBMISSION = ROOT / "docs/APP_STORE.md"


def check_icon(problems):
    if not ICON.exists():
        problems.append(f"{ICON.relative_to(ROOT)} is missing")
        return
    data = ICON.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        problems.append("the icon is not a PNG")
        return
    width, height = struct.unpack(">II", data[16:24])
    colour_type = data[25]
    if (width, height) != (1024, 1024):
        problems.append(f"the icon is {width} x {height}, not 1024 x 1024")
    # 2 = RGB, 6 = RGBA, 4 = greyscale with alpha. The store refuses anything with alpha.
    if colour_type in (4, 6):
        problems.append(f"the icon carries an alpha channel (PNG colour type {colour_type}); "
                        "regenerate it with tools/icon")
    if ICON_CONTENTS.exists() and ICON.name not in ICON_CONTENTS.read_text():
        problems.append(f"{ICON_CONTENTS.relative_to(ROOT)} does not name {ICON.name}")


def check_versions(problems):
    text = PROJECT.read_text()
    marketing = set(re.findall(r"MARKETING_VERSION = ([^;]+);", text))
    build = set(re.findall(r"CURRENT_PROJECT_VERSION = ([^;]+);", text))
    if len(marketing) != 1:
        problems.append(f"MARKETING_VERSION differs between targets: {sorted(marketing)}")
    if len(build) != 1:
        problems.append(f"CURRENT_PROJECT_VERSION differs between targets: {sorted(build)}")
    if len(marketing) == 1 and len(build) == 1 and SUBMISSION.exists():
        version, number = next(iter(marketing)), next(iter(build))
        page = SUBMISSION.read_text()
        if f"**{version}**" not in page or f"build **{number}**" not in page:
            problems.append(f"docs/APP_STORE.md does not say version {version} build {number}")
    # The compliance answer belongs on every configuration of the app target — the two that
    # carry the Live Activities key — and nowhere it would be a lie.
    app_configs = text.count("INFOPLIST_KEY_NSSupportsLiveActivities = YES;")
    answered = text.count("INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO;")
    if app_configs == 0:
        problems.append("could not find the app target's configurations")
    elif answered != app_configs:
        problems.append(f"ITSAppUsesNonExemptEncryption = NO is on {answered} of the app's "
                        f"{app_configs} configurations")


def check_extension(problems):
    if not EXTENSION_PLIST.exists():
        problems.append("the extension's Info.plist is missing")
        return
    plist = EXTENSION_PLIST.read_text()
    for key in ("CFBundleShortVersionString", "CFBundleVersion"):
        if key in plist:
            problems.append(f"the extension's Info.plist hard-codes {key}; it must follow "
                            "MARKETING_VERSION / CURRENT_PROJECT_VERSION like the app")


def check_documents(problems):
    if not PRIVACY.exists():
        problems.append("docs/PRIVACY.md is missing — the store requires a privacy policy URL")
    elif not re.search(r"^Effective \d{1,2} \w+ \d{4}", PRIVACY.read_text(), re.M):
        problems.append("docs/PRIVACY.md has no effective date")
    if not SUBMISSION.exists():
        problems.append("docs/APP_STORE.md is missing")


def check_built_in_plans(problems):
    if not CATALOGUE.exists():
        problems.append("Core/BuiltInPlans.swift is missing")
        return
    ids = re.findall(r'id: "([A-Za-z0-9]+)"', CATALOGUE.read_text())
    if not ids:
        problems.append("the catalogue names no plans")
    project = PROJECT.read_text()
    for plan_id in ids:
        file = RESOURCES / f"{plan_id}.json"
        if not file.exists():
            problems.append(f"the catalogue names {plan_id} but {file.relative_to(ROOT)} is missing")
        if f"{plan_id}.json in Resources" not in project:
            problems.append(f"{plan_id}.json is not in the app's Resources build phase "
                            "(tools/add_sources.py JimmsBro/Resources resource)")


def main():
    problems = []
    for check in (check_icon, check_versions, check_extension, check_documents, check_built_in_plans):
        check(problems)
    if problems:
        print("Not ready for the store:")
        for problem in problems:
            print(f"  - {problem}")
        return 1
    text = PROJECT.read_text()
    version = re.search(r"MARKETING_VERSION = ([^;]+);", text).group(1)
    build = re.search(r"CURRENT_PROJECT_VERSION = ([^;]+);", text).group(1)
    print(f"Ready for the store, as far as a script can tell: version {version} ({build}), "
          "an opaque icon, the compliance answer in the binary, the policy and the submission "
          "page in docs/, every built-in plan in the bundle.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
