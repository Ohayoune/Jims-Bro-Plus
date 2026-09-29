#!/usr/bin/env python3
"""Add or remove files in the Xcode project — the one script that edits project.pbxproj.

The project lists every file explicitly (it predates Xcode's synchronized folder groups), so a
file on disk is invisible to `xcodebuild` until it appears in three places: the
PBXFileReference list, its group's children, and a target's build phase. This does all three,
and the reverse.

Usage:
  python3 tools/add_sources.py <group-path> <target> <file> [...]
  python3 tools/add_sources.py remove <group-path> <file> [...]
  python3 tools/add_sources.py remove-group <group-path>

  group-path  e.g. JimmsBro/Store, JimmsBro/Features/Home, JimmsBroTests
  target      app | tests | activity (sources) or resource (the app's resources)

Adding a file its group already holds adds it to one more target — how a Core file is compiled
into the extension too. Removing a group removes the files and groups inside it first. Files on
disk are never touched. Handles Xcode's canonical project.pbxproj format (the one Xcode itself
writes). Idempotent.
"""
import re
import sys
import uuid
from pathlib import Path

ROOT_GROUP = 'B28B7AF69320201D1CF206EB'

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'JimmsBro.xcodeproj' / 'project.pbxproj'

# A target as the command line names it: the native target, and which of its phases.
TARGETS = {
    'app': ('JimmsBro', 'Sources'),
    'tests': ('JimmsBroTests', 'Sources'),
    'activity': ('JimmsBroActivity', 'Sources'),
    'resource': ('JimmsBro', 'Resources'),
}

TYPES = {'.swift': 'sourcecode.swift', '.caf': 'file', '.wav': 'audio.wav',
         '.json': 'text.json', '.md': 'net.daringfireball.markdown',
         '.xcassets': 'folder.assetcatalog'}


def oid():
    """A 24-hex-character object id, the shape Xcode writes."""
    return uuid.uuid4().hex[:24].upper()


def block(text, ident):
    """The body of an object, whether Xcode wrote it on one line or many."""
    single = re.search(r'\n\t\t%s\b[^\n]*= \{([^\n]*?)\};' % ident, text)
    if single:
        return single
    multi = re.search(r'\n\t\t%s\b[^\n]*= \{\n(.*?)\n\t\t\};' % ident, text, re.S)
    if not multi:
        sys.exit('Object %s not found' % ident)
    return multi


def listed(body, key):
    """The object ids in one of an object's lists: `children`, `files`, `buildPhases`, …"""
    match = re.search(r'\b%s = \(\n(.*?)\t\t\t\);' % key, body, re.S)
    return re.findall(r'([0-9A-F]{24})', match.group(1)) if match else []


def children(body):
    return listed(body, 'children')


def is_named(body, name):
    return re.search(r'path = "?%s"?;' % re.escape(name), body) is not None


def group_for(text, path):
    """Resolve a slash-separated group path from the project root group."""
    current = ROOT_GROUP
    for part in path.split('/'):
        for child in children(block(text, current).group(1)):
            body = block(text, child).group(1)
            if 'isa = PBXGroup;' in body and is_named(body, part):
                current = child
                break
        else:
            sys.exit('No group %r on the way to %s' % (part, path))
    return current


def phase_for(text, target, kind):
    """The id of a native target's Sources or Resources phase, found by the target's name.

    The phases are told apart by which one the target lists, so this does not depend on the
    order Xcode happened to write them in.
    """
    for ident in re.findall(r'\n\t\t([0-9A-F]{24})\b[^\n]*= \{\n\t\t\tisa = PBXNativeTarget;', text):
        body = block(text, ident).group(1)
        if re.search(r'\n\t\t\tname = "?%s"?;' % re.escape(target), body):
            for phase in listed(body, 'buildPhases'):
                if 'isa = PBX%sBuildPhase;' % kind in block(text, phase).group(1):
                    return phase
            sys.exit('%s has no %s phase' % (target, kind))
    sys.exit('No native target named %s' % target)


def insert_into_list(text, ident, key, line, last=False):
    """Add a line to a `children = (`, `files = (` or other list inside an object."""
    match = block(text, ident)
    body = match.group(1)
    if last:
        updated = re.sub(r'(\b%s = \(\n(?:.*?\n)*?)(\t\t\t\);)' % key,
                         lambda m: m.group(1) + '\t\t\t\t%s\n' % line + m.group(2), body, count=1)
    else:
        updated = re.sub(r'(\b%s = \(\n)' % key, lambda m: m.group(1) + '\t\t\t\t%s\n' % line,
                         body, count=1)
    return text[:match.start(1)] + updated + text[match.end(1):]


def insert_into_section(text, section, line):
    marker = '/* Begin %s section */\n' % section
    index = text.index(marker) + len(marker)
    return text[:index] + '\t\t%s\n' % line + text[index:]


def add_file(text, group, name, phase, kind):
    """Reference `name` at the end of `group` (unless it already is) and build it in `phase`.

    Returns the new text and what happened: 'added', 'also built' or 'already'.
    """
    file_ref = next((ref for ref in children(block(text, group).group(1))
                     if is_named(block(text, ref).group(1), name)), None)
    if file_ref and any('fileRef = %s ' % file_ref in block(text, build).group(1)
                        for build in listed(block(text, phase).group(1), 'files')):
        return text, 'already'
    outcome = 'also built'
    if not file_ref:
        file_ref, outcome = oid(), 'added'
        text = insert_into_section(
            text, 'PBXFileReference',
            '%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = %s; path = %s; sourceTree = "<group>"; };'
            % (file_ref, name, TYPES.get(Path(name).suffix, 'file'), name))
        text = insert_into_list(text, group, 'children', '%s /* %s */,' % (file_ref, name), last=True)
    build_file = oid()
    text = insert_into_section(
        text, 'PBXBuildFile',
        '%s /* %s in %s */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };'
        % (build_file, name, kind, file_ref, name))
    text = insert_into_list(text, phase, 'files', '%s /* %s in %s */,' % (build_file, name, kind), last=True)
    return text, outcome


def without_objects(text, idents):
    """Drop every line that defines or lists one of these objects (each is one line)."""
    return ''.join(line for line in text.splitlines(keepends=True)
                   if not any(ident in line for ident in idents))


def remove_file(text, group, name):
    """Drop a file from its group, from every target that builds it, and from the project."""
    file_ref = next((ref for ref in children(block(text, group).group(1))
                     if is_named(block(text, ref).group(1), name)), None)
    if not file_ref:
        return text, False
    builds = re.findall(r'\n\t\t([0-9A-F]{24})\b[^\n]*= \{isa = PBXBuildFile; fileRef = %s ' % file_ref,
                        text)
    return without_objects(text, [file_ref] + builds), True


def remove_group(text, group, path):
    """Drop a group with everything inside it, reporting each file."""
    for child in children(block(text, group).group(1)):
        body = block(text, child).group(1)
        name = re.search(r'path = "?([^";]+)"?;', body).group(1)
        if 'isa = PBXGroup;' in body:
            text = remove_group(text, child, path + '/' + name)
        else:
            text, _ = remove_file(text, group, name)
            print('removed:', path + '/' + name)
    match = block(text, group)
    return without_objects(text[:match.start()] + text[match.end():], [group])


def main(args):
    if len(args) >= 2 and args[0] == 'remove-group':
        text = PROJECT.read_text()
        text = remove_group(text, group_for(text, args[1]), args[1])
        print('removed group:', args[1])
    elif len(args) >= 3 and args[0] == 'remove':
        text = PROJECT.read_text()
        group = group_for(text, args[1])
        for name in args[2:]:
            text, removed = remove_file(text, group, name)
            print(('removed:' if removed else 'not in the project:'), args[1] + '/' + name)
    elif len(args) >= 3 and args[1] in TARGETS:
        group_path, (target, kind), names = args[0], TARGETS[args[1]], args[2:]
        text = PROJECT.read_text()
        group, phase = group_for(text, group_path), phase_for(text, target, kind)
        for name in names:
            if not (ROOT / group_path / name).exists():
                sys.exit('Missing file: %s/%s' % (group_path, name))
            text, outcome = add_file(text, group, name, phase, kind)
            print({'added': 'added:', 'also built': 'added to %s:' % target,
                   'already': 'already in %s:' % target}[outcome], group_path + '/' + name)
    else:
        sys.exit(__doc__)
    PROJECT.write_text(text)


if __name__ == '__main__':
    main(sys.argv[1:])
