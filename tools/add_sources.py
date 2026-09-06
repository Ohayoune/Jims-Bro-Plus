#!/usr/bin/env python3
"""Add Swift files or resources to the Xcode project.

Usage: python3 tools/add_sources.py <group-path> <target> <file> [...]
  group-path  e.g. JimmsBro/Store, JimmsBro/Features/Home, JimmsBroTests
  target      app | tests | resource

Handles Xcode's canonical project.pbxproj format (the one Xcode itself writes).
Idempotent: a file already referenced in its group is left alone.
"""
import re
import sys
import uuid
from pathlib import Path

APP_SOURCES = '2D764CD838DB39F040AA7EC4'
TEST_SOURCES = '9F3002A5D69B22D357A58AA9'
APP_RESOURCES = '06F5DC629BD46AAFD46564D1'
ROOT_GROUP = 'B28B7AF69320201D1CF206EB'

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'JimmsBro.xcodeproj' / 'project.pbxproj'

TYPES = {'.swift': 'sourcecode.swift', '.caf': 'file', '.wav': 'audio.wav',
         '.json': 'text.json', '.md': 'net.daringfireball.markdown',
         '.xcassets': 'folder.assetcatalog'}


def oid():
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


def children(body):
    match = re.search(r'children = \(\n(.*?)\t\t\t\);', body, re.S)
    return re.findall(r'([0-9A-F]{24})', match.group(1)) if match else []


def group_for(text, path):
    """Resolve a slash-separated group path from the project root group."""
    current = ROOT_GROUP
    for part in path.split('/'):
        for child in children(block(text, current).group(1)):
            body = block(text, child).group(1)
            if 'isa = PBXGroup;' in body and re.search(r'path = "?%s"?;' % re.escape(part), body):
                current = child
                break
        else:
            sys.exit('No group %r on the way to %s' % (part, path))
    return current


def insert_into_list(text, ident, key, line):
    """Add a line to a `children = (` or `files = (` list inside an object."""
    match = block(text, ident)
    body = match.group(1)
    updated = re.sub(r'(%s = \(\n)' % key, r'\1\t\t\t\t%s\n' % line, body, count=1)
    return text[:match.start(1)] + updated + text[match.end(1):]


def insert_into_section(text, section, line):
    marker = '/* Begin %s section */\n' % section
    index = text.index(marker) + len(marker)
    return text[:index] + '\t\t%s\n' % line + text[index:]


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    group_path, target, names = sys.argv[1], sys.argv[2], sys.argv[3:]
    phase, kind = {
        'app': (APP_SOURCES, 'Sources'),
        'tests': (TEST_SOURCES, 'Sources'),
        'resource': (APP_RESOURCES, 'Resources'),
    }[target]

    text = PROJECT.read_text()
    group = group_for(text, group_path)

    for name in names:
        if not (ROOT / group_path / name).exists():
            sys.exit('Missing file: %s/%s' % (group_path, name))
        existing = children(block(text, group).group(1))
        if any(re.search(r'path = "?%s"?;' % re.escape(name), block(text, ref).group(1))
               for ref in existing):
            print('already referenced:', name)
            continue

        file_ref, build_file = oid(), oid()
        file_type = TYPES.get(Path(name).suffix, 'file')
        text = insert_into_section(
            text, 'PBXFileReference',
            '%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = %s; path = %s; sourceTree = "<group>"; };'
            % (file_ref, name, file_type, name))
        text = insert_into_section(
            text, 'PBXBuildFile',
            '%s /* %s in %s */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };'
            % (build_file, name, kind, file_ref, name))
        text = insert_into_list(text, group, 'children', '%s /* %s */,' % (file_ref, name))
        text = insert_into_list(text, phase, 'files', '%s /* %s in %s */,' % (build_file, name, kind))
        print('added:', group_path + '/' + name)

    PROJECT.write_text(text)


main()
