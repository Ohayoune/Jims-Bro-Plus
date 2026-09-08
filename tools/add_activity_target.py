#!/usr/bin/env python3
"""Add the JimmsBroActivity widget extension target to JimmsBro.xcodeproj (D40, v1.2).

The project lists everything explicitly (it predates synchronized folder groups), so a new
target has to be written out in full: file references, a group, the target with its three build
phases, two build configurations and their list, the target itself in the project's `targets`,
and — so the extension actually ships inside the app — an "Embed Foundation Extensions" copy
phase and a dependency on the app target.

Idempotent: running it twice is a no-op. Run once; the result is committed.

    python3 tools/add_activity_target.py
"""
import re
import sys
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "JimmsBro.xcodeproj" / "project.pbxproj"

APP_TARGET = "4F6027D858B72CC70E5CC8E9"          # JimmsBro
PROJECT_OBJECT = "98F54143AB4E86B28C3AFEE0"
PRODUCT_GROUP = "FBDC4F23F93125BBEEAE800C"
MAIN_GROUP = "B28B7AF69320201D1CF206EB"
BUNDLE_ID = "com.ohayoune.jimmsbro.activity"

# The extension's own sources, plus the two Core files it needs to speak the app's language.
EXTENSION_SOURCES = [
    ("JimmsBroActivity", "JimmsBroActivityBundle.swift"),
    ("JimmsBroActivity", "WorkoutActivityAttributes.swift"),
    ("JimmsBroActivity", "WorkoutLiveActivity.swift"),
]
# Compiled into the extension as well as the app: one definition of the state, and the tiny
# helpers it leans on.
SHARED_SOURCES = [
    ("JimmsBro/Core", "WorkoutActivityState.swift"),
]


def oid():
    return uuid.uuid4().hex[:24].upper()


def main() -> int:
    text = PROJECT.read_text()
    if "JimmsBroActivity.appex" in text:
        print("the activity target is already in the project")
        return 0

    ids = {name: oid() for name in [
        "target", "product", "group", "sources", "frameworks", "resources", "embed",
        "configList", "debug", "release", "dependency", "proxy",
    ]}

    # --- file references and build files ------------------------------------------------
    refs, builds, group_children = [], [], []
    for folder, name in EXTENSION_SOURCES:
        file_id, build_id = oid(), oid()
        refs.append(f'\t\t{file_id} /* {name} */ = {{isa = PBXFileReference; '
                    f'lastKnownFileType = sourcecode.swift; path = {name}; '
                    f'sourceTree = "<group>"; }};')
        builds.append(f'\t\t{build_id} /* {name} in Sources */ = {{isa = PBXBuildFile; '
                      f'fileRef = {file_id} /* {name} */; }};')
        group_children.append(f'\t\t\t\t{file_id} /* {name} */,')
    source_build_ids = [line.split()[0] for line in builds]

    # Shared Core files already have a reference; reuse it and add a second build file.
    for _, name in SHARED_SOURCES:
        match = re.search(r'([0-9A-F]{24}) /\* %s \*/ = \{isa = PBXFileReference;' % re.escape(name),
                          text)
        if not match:
            print(f"could not find a file reference for {name}", file=sys.stderr)
            return 1
        build_id = oid()
        builds.append(f'\t\t{build_id} /* {name} in Sources */ = {{isa = PBXBuildFile; '
                      f'fileRef = {match.group(1)} /* {name} */; }};')
        source_build_ids.append(build_id)

    product_line = (f'\t\t{ids["product"]} /* JimmsBroActivity.appex */ = {{isa = PBXFileReference; '
                    f'explicitFileType = "wrapper.app-extension"; includeInIndex = 0; '
                    f'path = JimmsBroActivity.appex; sourceTree = BUILT_PRODUCTS_DIR; }};')
    embed_build = (f'\t\t{ids["embed"]}B /* JimmsBroActivity.appex in Embed Foundation Extensions */ = '
                   f'{{isa = PBXBuildFile; fileRef = {ids["product"]} /* JimmsBroActivity.appex */; '
                   f'settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};')

    text = text.replace("/* End PBXFileReference section */",
                        "\n".join(refs + [product_line]) + "\n/* End PBXFileReference section */")
    text = text.replace("/* End PBXBuildFile section */",
                        "\n".join(builds + [embed_build]) + "\n/* End PBXBuildFile section */")

    # --- the group -----------------------------------------------------------------------
    group = (f'\t\t{ids["group"]} /* JimmsBroActivity */ = {{\n'
             f'\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n'
             + "\n".join(group_children) + "\n"
             f'\t\t\t);\n\t\t\tpath = JimmsBroActivity;\n\t\t\tsourceTree = "<group>";\n\t\t}};')
    text = text.replace("/* End PBXGroup section */", group + "\n/* End PBXGroup section */")
    # Into the main group, and the product into Products.
    text = re.sub(r'(%s = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n)' % MAIN_GROUP,
                  r'\1\t\t\t\t%s /* JimmsBroActivity */,\n' % ids["group"], text, count=1)
    text = re.sub(r'(%s /\* Products \*/ = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n)' % PRODUCT_GROUP,
                  r'\1\t\t\t\t%s /* JimmsBroActivity.appex */,\n' % ids["product"], text, count=1)

    # --- build phases ---------------------------------------------------------------------
    phases = (
        f'\t\t{ids["sources"]} /* Sources */ = {{\n\t\t\tisa = PBXSourcesBuildPhase;\n'
        f'\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n'
        + "\n".join(f'\t\t\t\t{bid} /* in Sources */,' for bid in source_build_ids) + "\n"
        f'\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};'
    )
    text = text.replace("/* End PBXSourcesBuildPhase section */",
                        phases + "\n/* End PBXSourcesBuildPhase section */")

    frameworks = (f'\t\t{ids["frameworks"]} /* Frameworks */ = {{\n'
                  f'\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n'
                  f'\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};')
    text = text.replace("/* End PBXFrameworksBuildPhase section */",
                        frameworks + "\n/* End PBXFrameworksBuildPhase section */")

    resources = (f'\t\t{ids["resources"]} /* Resources */ = {{\n'
                 f'\t\t\tisa = PBXResourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n'
                 f'\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};')
    text = text.replace("/* End PBXResourcesBuildPhase section */",
                        resources + "\n/* End PBXResourcesBuildPhase section */")

    # The app embeds the extension. dstSubfolderSpec 13 is PlugIns.
    embed_phase = (
        f'/* Begin PBXCopyFilesBuildPhase section */\n'
        f'\t\t{ids["embed"]} /* Embed Foundation Extensions */ = {{\n'
        f'\t\t\tisa = PBXCopyFilesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n'
        f'\t\t\tdstPath = "";\n\t\t\tdstSubfolderSpec = 13;\n\t\t\tfiles = (\n'
        f'\t\t\t\t{ids["embed"]}B /* JimmsBroActivity.appex in Embed Foundation Extensions */,\n'
        f'\t\t\t);\n\t\t\tname = "Embed Foundation Extensions";\n'
        f'\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n'
        f'/* End PBXCopyFilesBuildPhase section */\n\n'
    )
    text = text.replace("/* Begin PBXFileReference section */", embed_phase + "/* Begin PBXFileReference section */")

    # --- the target -----------------------------------------------------------------------
    target = (
        f'\t\t{ids["target"]} /* JimmsBroActivity */ = {{\n'
        f'\t\t\tisa = PBXNativeTarget;\n'
        f'\t\t\tbuildConfigurationList = {ids["configList"]} /* Build configuration list for PBXNativeTarget "JimmsBroActivity" */;\n'
        f'\t\t\tbuildPhases = (\n\t\t\t\t{ids["sources"]} /* Sources */,\n'
        f'\t\t\t\t{ids["frameworks"]} /* Frameworks */,\n'
        f'\t\t\t\t{ids["resources"]} /* Resources */,\n\t\t\t);\n'
        f'\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n\t\t\t);\n'
        f'\t\t\tname = JimmsBroActivity;\n\t\t\tproductName = JimmsBroActivity;\n'
        f'\t\t\tproductReference = {ids["product"]} /* JimmsBroActivity.appex */;\n'
        f'\t\t\tproductType = "com.apple.product-type.app-extension";\n\t\t}};'
    )
    text = text.replace("/* End PBXNativeTarget section */", target + "\n/* End PBXNativeTarget section */")

    # The app depends on it, and gains the embed phase.
    dependency = (
        f'\t\t{ids["dependency"]} /* PBXTargetDependency */ = {{\n'
        f'\t\t\tisa = PBXTargetDependency;\n\t\t\ttarget = {ids["target"]} /* JimmsBroActivity */;\n'
        f'\t\t\ttargetProxy = {ids["proxy"]} /* PBXContainerItemProxy */;\n\t\t}};'
    )
    text = text.replace("/* End PBXTargetDependency section */",
                        dependency + "\n/* End PBXTargetDependency section */")
    proxy = (
        f'\t\t{ids["proxy"]} /* PBXContainerItemProxy */ = {{\n'
        f'\t\t\tisa = PBXContainerItemProxy;\n\t\t\tcontainerPortal = {PROJECT_OBJECT} /* Project object */;\n'
        f'\t\t\tproxyType = 1;\n\t\t\tremoteGlobalIDString = {ids["target"]};\n'
        f'\t\t\tremoteInfo = JimmsBroActivity;\n\t\t}};'
    )
    text = text.replace("/* End PBXContainerItemProxy section */",
                        proxy + "\n/* End PBXContainerItemProxy section */")

    # The embed phase has to be *listed* by the app target, not merely exist. A regex with a
    # lazy multi-line body matched nothing here and failed silently, so this splits the target's
    # text and edits the one list it needs.
    marker = f'{APP_TARGET} /* JimmsBro */ = {{'
    head, tail = text.split(marker, 1)
    phases_end = tail.index('\t\t\t);')
    tail = (tail[:phases_end]
            + f'\t\t\t\t{ids["embed"]} /* Embed Foundation Extensions */,\n'
            + tail[phases_end:])
    text = head + marker + tail
    text = re.sub(r'(%s /\* JimmsBro \*/ = \{\n(?:.*?\n)*?\t\t\tdependencies = \(\n)' % APP_TARGET,
                  r'\1\t\t\t\t%s /* PBXTargetDependency */,\n' % ids["dependency"], text, count=1)

    # --- build configurations --------------------------------------------------------------
    def configuration(name: str, extra: str) -> str:
        return (
            f'\t\t{ids["debug" if name == "Debug" else "release"]} /* {name} */ = {{\n'
            f'\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {{\n'
            f'\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;\n'
            f'\t\t\t\tCODE_SIGN_STYLE = Automatic;\n'
            f'\t\t\t\tCURRENT_PROJECT_VERSION = 1;\n'
            f'\t\t\t\tGENERATE_INFOPLIST_FILE = YES;\n'
            f'\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = "Jimm’s Bro+";\n'
            f'\t\t\t\tINFOPLIST_KEY_NSHumanReadableCopyright = "";\n'
            # JimmsBroActivity/Info.plist carries the NSExtension dictionary, which is what
            # makes the bundle an extension; without it the simulator refuses to install the
            # app that embeds it. Xcode merges it with the generated keys.
            f'\t\t\t\tINFOPLIST_FILE = JimmsBroActivity/Info.plist;\n'
            f'\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;\n'
            f'\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (\n\t\t\t\t\t"$(inherited)",\n'
            f'\t\t\t\t\t"@executable_path/Frameworks",\n\t\t\t\t\t"@executable_path/../../Frameworks",\n\t\t\t\t);\n'
            f'\t\t\t\tMARKETING_VERSION = 1.0;\n'
            f'\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};\n'
            f'\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";\n'
            f'\t\t\t\tSKIP_INSTALL = YES;\n'
            f'\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;\n'
            f'\t\t\t\tSWIFT_VERSION = 5.0;\n'
            f'\t\t\t\tTARGETED_DEVICE_FAMILY = 1;\n'
            f'{extra}'
            f'\t\t\t}};\n\t\t\tname = {name};\n\t\t}};'
        )

    configs = (configuration("Debug", '\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;\n')
               + "\n" + configuration("Release", '\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;\n'))
    text = text.replace("/* End XCBuildConfiguration section */",
                        configs + "\n/* End XCBuildConfiguration section */")

    config_list = (
        f'\t\t{ids["configList"]} /* Build configuration list for PBXNativeTarget "JimmsBroActivity" */ = {{\n'
        f'\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n'
        f'\t\t\t\t{ids["debug"]} /* Debug */,\n\t\t\t\t{ids["release"]} /* Release */,\n\t\t\t);\n'
        f'\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t}};'
    )
    text = text.replace("/* End XCConfigurationList section */",
                        config_list + "\n/* End XCConfigurationList section */")

    # --- the project knows about it ----------------------------------------------------------
    text = re.sub(r'(\t\t\ttargets = \(\n)', r'\1\t\t\t\t%s /* JimmsBroActivity */,\n' % ids["target"],
                  text, count=1)
    text = re.sub(r'(\t\t\t\t\t%s = \{\n\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;\n\t\t\t\t\t\};\n)' % APP_TARGET,
                  r'\1\t\t\t\t\t%s = {\n\t\t\t\t\t\tCreatedOnToolsVersion = 26.0;\n\t\t\t\t\t};\n' % ids["target"],
                  text, count=1)

    # The app declares that it supports Live Activities at all.
    text = text.replace('\t\t\t\tINFOPLIST_KEY_LSRequiresIPhoneOS = YES;',
                        '\t\t\t\tINFOPLIST_KEY_LSRequiresIPhoneOS = YES;\n'
                        '\t\t\t\tINFOPLIST_KEY_NSSupportsLiveActivities = YES;')

    PROJECT.write_text(text)
    print(f"added JimmsBroActivity ({ids['target']}) with {len(source_build_ids)} sources")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
