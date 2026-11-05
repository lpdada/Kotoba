#!/usr/bin/env python3
"""Generate Kotoba.xcodeproj/project.pbxproj from the files on disk.

The project is intentionally a plain, hand-rolled Xcode project (no XcodeGen,
no package manager) so it opens in Xcode 14+ and builds on GitHub's macOS
runners without extra tooling.

Run:  python3 Tools/generate_project.py
"""
from __future__ import annotations

import hashlib
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP_DIR = "Kotoba"
PROJECT_NAME = "Kotoba"
BUNDLE_ID = "app.kotoba.ios"
DEPLOYMENT_TARGET = "17.0"

SOURCE_EXTS = {".swift"}
RESOURCE_EXTS = {".json", ".xcassets", ".strings", ".mp3", ".mp4", ".m4a", ".wav"}
IGNORED_NAMES = {".DS_Store", "Info.plist"}


def uid(*parts: str) -> str:
    digest = hashlib.md5("/".join(parts).encode("utf-8")).hexdigest().upper()
    return digest[:24]


def file_type(path: str) -> str:
    if path.endswith(".swift"):
        return "sourcecode.swift"
    if path.endswith(".json"):
        return "text.json"
    if path.endswith(".xcassets"):
        return "folder.assetcatalog"
    if path.endswith(".plist"):
        return "text.plist.xml"
    if path.endswith(".md"):
        return "net.daringfireball.markdown"
    if path.endswith(".mp4") or path.endswith(".m4v") or path.endswith(".mov"):
        return "file"
    if path.endswith(".mp3") or path.endswith(".m4a") or path.endswith(".wav"):
        return "file"
    return "file"


class Node:
    def __init__(self, name: str, rel: str, is_dir: bool):
        self.name = name
        self.rel = rel
        self.is_dir = is_dir
        self.children: list[Node] = []
        self.uid = uid("node", rel)


def build_tree() -> Node:
    root = Node(APP_DIR, APP_DIR, True)

    def walk(node: Node) -> None:
        abs_path = os.path.join(ROOT, node.rel)
        for entry in sorted(os.listdir(abs_path)):
            if entry in IGNORED_NAMES or entry.startswith("."):
                continue
            rel = os.path.join(node.rel, entry)
            child = Node(entry, rel, os.path.isdir(os.path.join(ROOT, rel)))
            node.children.append(child)
            if child.is_dir and not entry.endswith(".xcassets"):
                walk(child)

    walk(root)
    return root


def collect(node: Node) -> tuple[list[Node], list[Node]]:
    sources, resources = [], []

    def visit(current: Node) -> None:
        for child in current.children:
            if child.is_dir:
                if child.name.endswith(".xcassets"):
                    resources.append(child)
                else:
                    visit(child)
            else:
                ext = os.path.splitext(child.name)[1]
                if ext in SOURCE_EXTS:
                    sources.append(child)
                elif ext in RESOURCE_EXTS:
                    resources.append(child)

    visit(node)
    return sources, resources


def main() -> int:
    tree = build_tree()
    sources, resources = collect(tree)

    if not sources:
        print("no Swift sources found", file=sys.stderr)
        return 1

    lines: list[str] = []
    add = lines.append

    add("// !$*UTF8*$!")
    add("{")
    add("\tarchiveVersion = 1;")
    add("\tclasses = {")
    add("\t};")
    add("\tobjectVersion = 56;")
    add("\tobjects = {")

    # PBXBuildFile
    add("")
    add("/* Begin PBXBuildFile section */")
    for node in sources:
        add(
            f"\t\t{uid('build', node.rel)} /* {node.name} in Sources */ = "
            f"{{isa = PBXBuildFile; fileRef = {node.uid} /* {node.name} */; }};"
        )
    for node in resources:
        add(
            f"\t\t{uid('build', node.rel)} /* {node.name} in Resources */ = "
            f"{{isa = PBXBuildFile; fileRef = {node.uid} /* {node.name} */; }};"
        )
    add("/* End PBXBuildFile section */")

    # PBXFileReference
    add("")
    add("/* Begin PBXFileReference section */")
    for node in sources + resources:
        add(
            f"\t\t{node.uid} /* {node.name} */ = {{isa = PBXFileReference; "
            f"lastKnownFileType = {file_type(node.rel)}; path = {node.name}; "
            f"sourceTree = \"<group>\"; }};"
        )
    product_uid = uid("product", PROJECT_NAME)
    add(
        f"\t\t{product_uid} /* {PROJECT_NAME}.app */ = {{isa = PBXFileReference; "
        f"explicitFileType = wrapper.application; includeInIndex = 0; "
        f"path = {PROJECT_NAME}.app; sourceTree = BUILT_PRODUCTS_DIR; }};"
    )
    plist_uid = uid("fileref", f"{APP_DIR}/Info.plist")
    add(
        f"\t\t{plist_uid} /* Info.plist */ = {{isa = PBXFileReference; "
        f"lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; }};"
    )
    add("/* End PBXFileReference section */")

    # PBXFrameworksBuildPhase
    frameworks_uid = uid("phase", "frameworks")
    add("")
    add("/* Begin PBXFrameworksBuildPhase section */")
    add(f"\t\t{frameworks_uid} /* Frameworks */ = {{")
    add("\t\t\tisa = PBXFrameworksBuildPhase;")
    add("\t\t\tbuildActionMask = 2147483647;")
    add("\t\t\tfiles = (")
    add("\t\t\t);")
    add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    add("\t\t};")
    add("/* End PBXFrameworksBuildPhase section */")

    # PBXGroup
    add("")
    add("/* Begin PBXGroup section */")

    main_group_uid = uid("group", "main")
    add(f"\t\t{main_group_uid} = {{")
    add("\t\t\tisa = PBXGroup;")
    add("\t\t\tchildren = (")
    add(f"\t\t\t\t{tree.uid} /* {APP_DIR} */,")
    add(f"\t\t\t\t{uid('group', 'products')} /* Products */,")
    add("\t\t\t);")
    add("\t\t\tsourceTree = \"<group>\";")
    add("\t\t};")

    add(f"\t\t{uid('group', 'products')} /* Products */ = {{")
    add("\t\t\tisa = PBXGroup;")
    add("\t\t\tchildren = (")
    add(f"\t\t\t\t{product_uid} /* {PROJECT_NAME}.app */,")
    add("\t\t\t);")
    add("\t\t\tname = Products;")
    add("\t\t\tsourceTree = \"<group>\";")
    add("\t\t};")

    def emit_group(node: Node) -> None:
        add(f"\t\t{node.uid} /* {node.name} */ = {{")
        add("\t\t\tisa = PBXGroup;")
        add("\t\t\tchildren = (")
        for child in node.children:
            add(f"\t\t\t\t{child.uid} /* {child.name} */,")
        if node.rel == APP_DIR:
            add(f"\t\t\t\t{plist_uid} /* Info.plist */,")
        add("\t\t\t);")
        add(f"\t\t\tpath = {node.name};")
        add("\t\t\tsourceTree = \"<group>\";")
        add("\t\t};")
        for child in node.children:
            if child.is_dir and not child.name.endswith(".xcassets"):
                emit_group(child)

    emit_group(tree)
    add("/* End PBXGroup section */")

    # PBXNativeTarget
    target_uid = uid("target", PROJECT_NAME)
    sources_phase = uid("phase", "sources")
    resources_phase = uid("phase", "resources")
    add("")
    add("/* Begin PBXNativeTarget section */")
    add(f"\t\t{target_uid} /* {PROJECT_NAME} */ = {{")
    add("\t\t\tisa = PBXNativeTarget;")
    add(f"\t\t\tbuildConfigurationList = {uid('configlist', 'target')} /* Build configuration list for PBXNativeTarget \"{PROJECT_NAME}\" */;")
    add("\t\t\tbuildPhases = (")
    add(f"\t\t\t\t{sources_phase} /* Sources */,")
    add(f"\t\t\t\t{frameworks_uid} /* Frameworks */,")
    add(f"\t\t\t\t{resources_phase} /* Resources */,")
    add("\t\t\t);")
    add("\t\t\tbuildRules = (")
    add("\t\t\t);")
    add("\t\t\tdependencies = (")
    add("\t\t\t);")
    add(f"\t\t\tname = {PROJECT_NAME};")
    add(f"\t\t\tproductName = {PROJECT_NAME};")
    add(f"\t\t\tproductReference = {product_uid} /* {PROJECT_NAME}.app */;")
    add("\t\t\tproductType = \"com.apple.product-type.application\";")
    add("\t\t};")
    add("/* End PBXNativeTarget section */")

    # PBXProject
    project_uid = uid("project", PROJECT_NAME)
    add("")
    add("/* Begin PBXProject section */")
    add(f"\t\t{project_uid} /* Project object */ = {{")
    add("\t\t\tisa = PBXProject;")
    add("\t\t\tattributes = {")
    add("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    add("\t\t\t\tLastSwiftUpdateCheck = 1500;")
    add("\t\t\t\tLastUpgradeCheck = 1500;")
    add("\t\t\t\tTargetAttributes = {")
    add(f"\t\t\t\t\t{target_uid} = {{")
    add("\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;")
    add("\t\t\t\t\t};")
    add("\t\t\t\t};")
    add("\t\t\t};")
    add(f"\t\t\tbuildConfigurationList = {uid('configlist', 'project')} /* Build configuration list for PBXProject \"{PROJECT_NAME}\" */;")
    add("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
    add("\t\t\tdevelopmentRegion = en;")
    add("\t\t\thasScannedForEncodings = 0;")
    add("\t\t\tknownRegions = (")
    add("\t\t\t\ten,")
    add("\t\t\t\tBase,")
    add("\t\t\t\t\"zh-Hans\",")
    add("\t\t\t);")
    add(f"\t\t\tmainGroup = {main_group_uid};")
    add(f"\t\t\tproductRefGroup = {uid('group', 'products')} /* Products */;")
    add("\t\t\tprojectDirPath = \"\";")
    add("\t\t\tprojectRoot = \"\";")
    add("\t\t\ttargets = (")
    add(f"\t\t\t\t{target_uid} /* {PROJECT_NAME} */,")
    add("\t\t\t);")
    add("\t\t};")
    add("/* End PBXProject section */")

    # PBXResourcesBuildPhase
    add("")
    add("/* Begin PBXResourcesBuildPhase section */")
    add(f"\t\t{resources_phase} /* Resources */ = {{")
    add("\t\t\tisa = PBXResourcesBuildPhase;")
    add("\t\t\tbuildActionMask = 2147483647;")
    add("\t\t\tfiles = (")
    for node in resources:
        add(f"\t\t\t\t{uid('build', node.rel)} /* {node.name} in Resources */,")
    add("\t\t\t);")
    add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    add("\t\t};")
    add("/* End PBXResourcesBuildPhase section */")

    # PBXSourcesBuildPhase
    add("")
    add("/* Begin PBXSourcesBuildPhase section */")
    add(f"\t\t{sources_phase} /* Sources */ = {{")
    add("\t\t\tisa = PBXSourcesBuildPhase;")
    add("\t\t\tbuildActionMask = 2147483647;")
    add("\t\t\tfiles = (")
    for node in sources:
        add(f"\t\t\t\t{uid('build', node.rel)} /* {node.name} in Sources */,")
    add("\t\t\t);")
    add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    add("\t\t};")
    add("/* End PBXSourcesBuildPhase section */")

    # XCBuildConfiguration
    common_project_settings = [
        "ALWAYS_SEARCH_USER_PATHS = NO;",
        "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;",
        "CLANG_ANALYZER_NONNULL = YES;",
        "CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;",
        "CLANG_CXX_LANGUAGE_STANDARD = \"gnu++20\";",
        "CLANG_ENABLE_MODULES = YES;",
        "CLANG_ENABLE_OBJC_ARC = YES;",
        "CLANG_ENABLE_OBJC_WEAK = YES;",
        "CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;",
        "CLANG_WARN_BOOL_CONVERSION = YES;",
        "CLANG_WARN_COMMA = YES;",
        "CLANG_WARN_CONSTANT_CONVERSION = YES;",
        "CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;",
        "CLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;",
        "CLANG_WARN_DOCUMENTATION_COMMENTS = YES;",
        "CLANG_WARN_EMPTY_BODY = YES;",
        "CLANG_WARN_ENUM_CONVERSION = YES;",
        "CLANG_WARN_INFINITE_RECURSION = YES;",
        "CLANG_WARN_INT_CONVERSION = YES;",
        "CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;",
        "CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;",
        "CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;",
        "CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;",
        "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;",
        "CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;",
        "CLANG_WARN_STRICT_PROTOTYPES = YES;",
        "CLANG_WARN_SUSPICIOUS_MOVE = YES;",
        "CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;",
        "CLANG_WARN_UNREACHABLE_CODE = YES;",
        "CLANG_WARN__DUPLICATE_METHOD_MATCH = YES;",
        "COPY_PHASE_STRIP = NO;",
        "ENABLE_STRICT_OBJC_MSGSEND = YES;",
        "ENABLE_USER_SCRIPT_SANDBOXING = YES;",
        f"IPHONEOS_DEPLOYMENT_TARGET = {DEPLOYMENT_TARGET};",
        "LOCALIZATION_PREFERS_STRING_CATALOGS = YES;",
        "MTL_FAST_MATH = YES;",
        "SDKROOT = iphoneos;",
        "SWIFT_VERSION = 5.0;",
    ]
    target_settings = [
        "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;",
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;",
        "CODE_SIGN_STYLE = Automatic;",
        "CURRENT_PROJECT_VERSION = 1;",
        "DEVELOPMENT_ASSET_PATHS = \"\";",
        "ENABLE_PREVIEWS = YES;",
        "GENERATE_INFOPLIST_FILE = NO;",
        "INFOPLIST_FILE = Kotoba/Info.plist;",
        "LD_RUNPATH_SEARCH_PATHS = (",
        "\t\t\t\t\t\"$(inherited)\",",
        "\t\t\t\t\t\"@executable_path/Frameworks\",",
        "\t\t\t\t);",
        "MARKETING_VERSION = 1.0;",
        f"PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};",
        "PRODUCT_NAME = \"$(TARGET_NAME)\";",
        "SWIFT_EMIT_LOC_STRINGS = YES;",
        "TARGETED_DEVICE_FAMILY = \"1,2\";",
    ]

    configs = [
        ("Debug", "project", common_project_settings + [
            "DEBUG_INFORMATION_FORMAT = dwarf;",
            "ENABLE_TESTABILITY = YES;",
            "GCC_DYNAMIC_NO_PIC = NO;",
            "GCC_OPTIMIZATION_LEVEL = 0;",
            "GCC_PREPROCESSOR_DEFINITIONS = (",
            "\t\t\t\t\t\"DEBUG=1\",",
            "\t\t\t\t\t\"$(inherited)\",",
            "\t\t\t\t);",
            "MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;",
            "ONLY_ACTIVE_ARCH = YES;",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS = \"DEBUG $(inherited)\";",
            "SWIFT_OPTIMIZATION_LEVEL = \"-Onone\";",
        ]),
        ("Release", "project", common_project_settings + [
            "DEBUG_INFORMATION_FORMAT = \"dwarf-with-dsym\";",
            "ENABLE_NS_ASSERTIONS = NO;",
            "MTL_ENABLE_DEBUG_INFO = NO;",
            "SWIFT_COMPILATION_MODE = wholemodule;",
            "VALIDATE_PRODUCT = YES;",
        ]),
        ("Debug", "target", target_settings),
        ("Release", "target", target_settings),
    ]

    add("")
    add("/* Begin XCBuildConfiguration section */")
    for name, scope, settings in configs:
        config_uid = uid("config", scope, name)
        add(f"\t\t{config_uid} /* {name} */ = {{")
        add("\t\t\tisa = XCBuildConfiguration;")
        add("\t\t\tbuildSettings = {")
        for setting in settings:
            if setting.startswith("LD_RUNPATH_SEARCH_PATHS") or setting.startswith("GCC_PREPROCESSOR"):
                add(f"\t\t\t\t{setting}")
            else:
                add(f"\t\t\t\t{setting}")
        add("\t\t\t};")
        add(f"\t\t\tname = {name};")
        add("\t\t};")
    add("/* End XCBuildConfiguration section */")

    add("")
    add("/* Begin XCConfigurationList section */")
    for scope in ("project", "target"):
        list_uid = uid("configlist", scope)
        add(f"\t\t{list_uid} /* Build configuration list for {'PBXProject' if scope == 'project' else 'PBXNativeTarget'} \"{PROJECT_NAME}\" */ = {{")
        add("\t\t\tisa = XCConfigurationList;")
        add("\t\t\tbuildConfigurations = (")
        add(f"\t\t\t\t{uid('config', scope, 'Debug')} /* Debug */,")
        add(f"\t\t\t\t{uid('config', scope, 'Release')} /* Release */,")
        add("\t\t\t);")
        add("\t\t\tdefaultConfigurationIsVisible = 0;")
        add("\t\t\tdefaultConfigurationName = Release;")
        add("\t\t};")
    add("/* End XCConfigurationList section */")

    add("\t};")
    add(f"\trootObject = {project_uid} /* Project object */;")
    add("}")

    project_dir = os.path.join(ROOT, f"{PROJECT_NAME}.xcodeproj")
    os.makedirs(project_dir, exist_ok=True)
    with open(os.path.join(project_dir, "project.pbxproj"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")

    # Shared scheme so CI can call `-scheme Kotoba` without opening Xcode.
    schemes_dir = os.path.join(project_dir, "xcshareddata", "xcschemes")
    os.makedirs(schemes_dir, exist_ok=True)
    with open(os.path.join(schemes_dir, f"{PROJECT_NAME}.xcscheme"), "w", encoding="utf-8") as fh:
        fh.write(scheme_xml(target_uid, product_uid))

    workspace_dir = os.path.join(project_dir, "project.xcworkspace")
    os.makedirs(workspace_dir, exist_ok=True)
    with open(os.path.join(workspace_dir, "contents.xcworkspacedata"), "w", encoding="utf-8") as fh:
        fh.write(workspace_xml())

    print(f"wrote {PROJECT_NAME}.xcodeproj with {len(sources)} sources and {len(resources)} resources")
    return 0


def scheme_xml(target_uid: str, product_uid: str) -> str:
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1500" version="1.7">
   <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
            <BuildableReference
               BuildableIdentifier="primary"
               BlueprintIdentifier="{target_uid}"
               BuildableName="{PROJECT_NAME}.app"
               BlueprintName="{PROJECT_NAME}"
               ReferencedContainer="container:{PROJECT_NAME}.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
      <BuildableProductRunnable runnableDebuggingMode="0">
         <BuildableReference
            BuildableIdentifier="primary"
            BlueprintIdentifier="{target_uid}"
            BuildableName="{PROJECT_NAME}.app"
            BlueprintName="{PROJECT_NAME}"
            ReferencedContainer="container:{PROJECT_NAME}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">
      <BuildableProductRunnable runnableDebuggingMode="0">
         <BuildableReference
            BuildableIdentifier="primary"
            BlueprintIdentifier="{target_uid}"
            BuildableName="{PROJECT_NAME}.app"
            BlueprintName="{PROJECT_NAME}"
            ReferencedContainer="container:{PROJECT_NAME}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration="Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES">
   </ArchiveAction>
</Scheme>
"""


def workspace_xml() -> str:
    return """<?xml version="1.0" encoding="UTF-8"?>
<Workspace version = "1.0">
   <FileRef location = "self:">
   </FileRef>
</Workspace>
"""


if __name__ == "__main__":
    raise SystemExit(main())
