#!/usr/bin/env python3
"""Add or remove Swift source files in JimmsBro.xcodeproj/project.pbxproj.

The project lists every file explicitly (it predates Xcode's synchronized folder groups), so a
new file added on disk is invisible to `xcodebuild` until it appears in three places: the
PBXFileReference list, its PBXGroup's children, and a target's PBXSourcesBuildPhase. This
script does all three, and the reverse for removal.

    python3 tools/pbxproj_edit.py add Core WorkoutScreen.swift [--target JimmsBroTests]
    python3 tools/pbxproj_edit.py remove RestOverlay.swift
    python3 tools/pbxproj_edit.py remove-group Rest

Group is matched by its `path = <name>;` line, so "Core", "Workout", "JimmsBroTests" all work.
"""
import re
import sys
import uuid
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent / "JimmsBro.xcodeproj" / "project.pbxproj"
APP_TARGET = "JimmsBro"


def oid():
    """A 24-hex-character object id, the shape Xcode writes."""
    return uuid.uuid4().hex[:24].upper()


def sources_phase_span(text, target):
    """The (start, end) offsets of the PBXSourcesBuildPhase files list for a target.

    The phases are told apart by which one is referenced from that target's buildPhases, so
    this does not depend on the order Xcode happened to write them in.
    """
    target_block = re.search(
        r"/\* %s \*/ = \{\s*isa = PBXNativeTarget;.*?buildPhases = \((.*?)\);" % re.escape(target),
        text, re.S)
    if not target_block:
        raise SystemExit(f"no native target named {target}")
    phase_ids = re.findall(r"([0-9A-F]{24}) /\*", target_block.group(1))
    for pid in phase_ids:
        block = re.search(
            r"\t\t%s /\* Sources \*/ = \{\s*isa = PBXSourcesBuildPhase;.*?files = \((.*?)\);" % pid,
            text, re.S)
        if block:
            return block.start(1), block.end(1)
    raise SystemExit(f"{target} has no Sources build phase")


def add(group, filename, target):
    text = PROJECT.read_text()
    if f"/* {filename} */" in text:
        print(f"{filename} already in the project")
        return
    file_id, build_id = oid(), oid()

    ref = (f"\t\t{file_id} /* {filename} */ = {{isa = PBXFileReference; "
           f"lastKnownFileType = sourcecode.swift; path = {filename}; sourceTree = \"<group>\"; }};\n")
    anchor = "/* End PBXFileReference section */"
    text = text.replace(anchor, ref + anchor, 1)

    build = (f"\t\t{build_id} /* {filename} in Sources */ = {{isa = PBXBuildFile; "
             f"fileRef = {file_id} /* {filename} */; }};\n")
    anchor = "/* End PBXBuildFile section */"
    text = text.replace(anchor, build + anchor, 1)

    match = re.search(
        r"(/\* %s \*/ = \{\s*isa = PBXGroup;\s*children = \()" % re.escape(group), text, re.S)
    if not match:
        raise SystemExit(f"no group named {group}")
    text = text[:match.end(1)] + f"\n\t\t\t\t{file_id} /* {filename} */," + text[match.end(1):]

    start, _ = sources_phase_span(text, target)
    text = text[:start] + f"\n\t\t\t\t{build_id} /* {filename} in Sources */," + text[start:]

    PROJECT.write_text(text)
    print(f"added {filename} to {group} ({target})")


def remove(filename):
    text = PROJECT.read_text()
    if f"/* {filename} */" not in text:
        print(f"{filename} is not in the project")
        return
    kept = [line for line in text.splitlines(keepends=True)
            if f"/* {filename} */" not in line and f"/* {filename} in Sources */" not in line]
    PROJECT.write_text("".join(kept))
    print(f"removed {filename}")


def remove_group(group):
    text = PROJECT.read_text()
    block = re.search(
        r"\t\t([0-9A-F]{24}) /\* %s \*/ = \{\s*isa = PBXGroup;.*?\n\t\t\};\n" % re.escape(group),
        text, re.S)
    if not block:
        print(f"no group named {group}")
        return
    text = text[:block.start()] + text[block.end():]
    text = "".join(line for line in text.splitlines(keepends=True)
                   if f"{block.group(1)} /* {group} */" not in line)
    PROJECT.write_text(text)
    print(f"removed group {group}")


if __name__ == "__main__":
    args = sys.argv[1:]
    target = APP_TARGET
    if "--target" in args:
        i = args.index("--target")
        target = args[i + 1]
        args = args[:i] + args[i + 2:]
    if not args:
        raise SystemExit(__doc__)
    if args[0] == "add":
        add(args[1], args[2], target)
    elif args[0] == "remove":
        for name in args[1:]:
            remove(name)
    elif args[0] == "remove-group":
        remove_group(args[1])
    else:
        raise SystemExit(__doc__)
