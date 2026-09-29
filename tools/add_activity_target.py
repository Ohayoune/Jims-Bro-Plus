#!/usr/bin/env python3
"""Add the JimmsBroActivity widget extension target to JimmsBro.xcodeproj (D40, v1.2).

The project lists everything explicitly (it predates synchronized folder groups), so a new
target has to be written out in full: file references, a group, the target with its three build
phases, two build configurations and their list, the target itself in the project's `targets`,
and — so the extension actually ships inside the app — an "Embed Foundation Extensions" copy
phase and a dependency on the app target.

The file references and build files go through `add_sources.py`, the one script that edits the
project; this adds only what a new target needs besides them. Idempotent: running it twice is a
no-op. Run once (v1.2 V7); the result is committed.

    python3 tools/add_activity_target.py
"""
import re
import sys

from add_sources import PROJECT, add_file, group_for, insert_into_list, insert_into_section, oid

APP_TARGET = "4F6027D858B72CC70E5CC8E9"          # JimmsBro
PROJECT_OBJECT = "98F54143AB4E86B28C3AFEE0"
PRODUCT_GROUP = "FBDC4F23F93125BBEEAE800C"
MAIN_GROUP = "B28B7AF69320201D1CF206EB"
BUNDLE_ID = "com.ohayoune.jimmsbro.activity"

# The extension's own sources, plus the Core file it needs to speak the app's language.
EXTENSION_SOURCES = [
    ("JimmsBroActivity", "JimmsBroActivityBundle.swift"),
    ("JimmsBroActivity", "WorkoutActivityAttributes.swift"),
    ("JimmsBroActivity", "WorkoutLiveActivity.swift"),
]
# Compiled into the extension as well as the app: one definition of the state, and the tiny
# helpers it leans on. `add_sources.py` adds the second build file, as it does for any file a
# group already holds.
SHARED_SOURCES = [
    ("JimmsBro/Core", "WorkoutActivityState.swift"),
]


def empty_phase(ident, name, isa):
    return (f'{ident} /* {name} */ = {{\n\t\t\tisa = {isa};\n'
            f'\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n'
            f'\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};')


def main() -> int:
    text = PROJECT.read_text()
    if "JimmsBroActivity.appex" in text:
        print("the activity target is already in the project")
        return 0
    for folder, name in SHARED_SOURCES:
        if not re.search(r'/\* %s \*/ = \{isa = PBXFileReference;' % re.escape(name), text):
            print(f"could not find a file reference for {folder}/{name}", file=sys.stderr)
            return 1

    ids = {name: oid() for name in [
        "target", "product", "group", "sources", "frameworks", "resources", "embed",
        "configList", "debug", "release", "dependency", "proxy",
    ]}

    # --- the product, and the build file that embeds it ----------------------------------
    text = insert_into_section(
        text, "PBXFileReference",
        f'{ids["product"]} /* JimmsBroActivity.appex */ = {{isa = PBXFileReference; '
        f'explicitFileType = "wrapper.app-extension"; includeInIndex = 0; '
        f'path = JimmsBroActivity.appex; sourceTree = BUILT_PRODUCTS_DIR; }};')
    text = insert_into_section(
        text, "PBXBuildFile",
        f'{ids["embed"]}B /* JimmsBroActivity.appex in Embed Foundation Extensions */ = '
        f'{{isa = PBXBuildFile; fileRef = {ids["product"]} /* JimmsBroActivity.appex */; '
        f'settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};')

    # --- the group, in the main group, and the product in Products -------------------------
    text = insert_into_section(
        text, "PBXGroup",
        f'{ids["group"]} /* JimmsBroActivity */ = {{\n\t\t\tisa = PBXGroup;\n'
        f'\t\t\tchildren = (\n\t\t\t);\n\t\t\tpath = JimmsBroActivity;\n'
        f'\t\t\tsourceTree = "<group>";\n\t\t}};')
    text = insert_into_list(text, MAIN_GROUP, "children", f'{ids["group"]} /* JimmsBroActivity */,')
    text = insert_into_list(text, PRODUCT_GROUP, "children",
                            f'{ids["product"]} /* JimmsBroActivity.appex */,')

    # --- build phases ---------------------------------------------------------------------
    text = insert_into_section(text, "PBXSourcesBuildPhase",
                               empty_phase(ids["sources"], "Sources", "PBXSourcesBuildPhase"))
    text = insert_into_section(text, "PBXFrameworksBuildPhase",
                               empty_phase(ids["frameworks"], "Frameworks", "PBXFrameworksBuildPhase"))
    text = insert_into_section(text, "PBXResourcesBuildPhase",
                               empty_phase(ids["resources"], "Resources", "PBXResourcesBuildPhase"))

    # The app embeds the extension. dstSubfolderSpec 13 is PlugIns. The project had no copy
    # phase before this one, so the section is written too.
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
    text = insert_into_section(
        text, "PBXNativeTarget",
        f'{ids["target"]} /* JimmsBroActivity */ = {{\n'
        f'\t\t\tisa = PBXNativeTarget;\n'
        f'\t\t\tbuildConfigurationList = {ids["configList"]} /* Build configuration list for PBXNativeTarget "JimmsBroActivity" */;\n'
        f'\t\t\tbuildPhases = (\n\t\t\t\t{ids["sources"]} /* Sources */,\n'
        f'\t\t\t\t{ids["frameworks"]} /* Frameworks */,\n'
        f'\t\t\t\t{ids["resources"]} /* Resources */,\n\t\t\t);\n'
        f'\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n\t\t\t);\n'
        f'\t\t\tname = JimmsBroActivity;\n\t\t\tproductName = JimmsBroActivity;\n'
        f'\t\t\tproductReference = {ids["product"]} /* JimmsBroActivity.appex */;\n'
        f'\t\t\tproductType = "com.apple.product-type.app-extension";\n\t\t}};')

    # The app depends on it, and lists the embed phase last — listed, not merely present.
    text = insert_into_section(
        text, "PBXTargetDependency",
        f'{ids["dependency"]} /* PBXTargetDependency */ = {{\n'
        f'\t\t\tisa = PBXTargetDependency;\n\t\t\ttarget = {ids["target"]} /* JimmsBroActivity */;\n'
        f'\t\t\ttargetProxy = {ids["proxy"]} /* PBXContainerItemProxy */;\n\t\t}};')
    text = insert_into_section(
        text, "PBXContainerItemProxy",
        f'{ids["proxy"]} /* PBXContainerItemProxy */ = {{\n'
        f'\t\t\tisa = PBXContainerItemProxy;\n\t\t\tcontainerPortal = {PROJECT_OBJECT} /* Project object */;\n'
        f'\t\t\tproxyType = 1;\n\t\t\tremoteGlobalIDString = {ids["target"]};\n'
        f'\t\t\tremoteInfo = JimmsBroActivity;\n\t\t}};')
    text = insert_into_list(text, APP_TARGET, "buildPhases",
                            f'{ids["embed"]} /* Embed Foundation Extensions */,', last=True)
    text = insert_into_list(text, APP_TARGET, "dependencies",
                            f'{ids["dependency"]} /* PBXTargetDependency */,')

    # --- build configurations --------------------------------------------------------------
    def configuration(name: str, extra: str) -> str:
        return (
            f'{ids["debug" if name == "Debug" else "release"]} /* {name} */ = {{\n'
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

    text = insert_into_section(text, "XCBuildConfiguration",
                               configuration("Debug", '\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;\n'))
    text = insert_into_section(text, "XCBuildConfiguration",
                               configuration("Release", '\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;\n'))
    text = insert_into_section(
        text, "XCConfigurationList",
        f'{ids["configList"]} /* Build configuration list for PBXNativeTarget "JimmsBroActivity" */ = {{\n'
        f'\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n'
        f'\t\t\t\t{ids["debug"]} /* Debug */,\n\t\t\t\t{ids["release"]} /* Release */,\n\t\t\t);\n'
        f'\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t}};')

    # --- the project knows about it ----------------------------------------------------------
    text = insert_into_list(text, PROJECT_OBJECT, "targets", f'{ids["target"]} /* JimmsBroActivity */,')
    text = re.sub(r'(\t\t\t\t\t%s = \{\n\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;\n\t\t\t\t\t\};\n)' % APP_TARGET,
                  r'\1\t\t\t\t\t%s = {\n\t\t\t\t\t\tCreatedOnToolsVersion = 26.0;\n\t\t\t\t\t};\n' % ids["target"],
                  text, count=1)

    # The app declares that it supports Live Activities at all.
    text = text.replace('\t\t\t\tINFOPLIST_KEY_LSRequiresIPhoneOS = YES;',
                        '\t\t\t\tINFOPLIST_KEY_LSRequiresIPhoneOS = YES;\n'
                        '\t\t\t\tINFOPLIST_KEY_NSSupportsLiveActivities = YES;')

    # --- the sources, the way add_sources.py adds any file -------------------------------------
    sources = EXTENSION_SOURCES + SHARED_SOURCES
    for folder, name in sources:
        group = ids["group"] if folder == "JimmsBroActivity" else group_for(text, folder)
        text, _ = add_file(text, group, name, ids["sources"], "Sources")

    PROJECT.write_text(text)
    print(f"added JimmsBroActivity ({ids['target']}) with {len(sources)} sources")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
