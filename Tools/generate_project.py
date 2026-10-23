#!/usr/bin/env python3
"""Generate iOS and native macOS targets referencing the local Swift package."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "FTPunk.xcodeproj"
objects = []


def quoted(value):
    return json.dumps(str(value))


def add(name, content):
    key = hashlib.sha1(name.encode()).hexdigest()[:24].upper()
    objects.append(f"\t\t{key} = {{ {content} }};")
    return key


def refs(values):
    return "(" + ", ".join(values) + ")"


def settings(values):
    return " ".join(f"{key} = {quoted(value)};" for key, value in values.items())


files, swift_files = [], []
for path in sorted((ROOT / "App").glob("*.swift")):
    relative = path.relative_to(ROOT).as_posix()
    file_id = add(relative, f"isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quoted(relative)}; sourceTree = SOURCE_ROOT;")
    files.append(file_id)
    swift_files.append(file_id)
for name, filetype in [("Info.plist", "text.plist.xml"), ("MacInfo.plist", "text.plist.xml"), ("Mac.entitlements", "text.plist.entitlements")]:
    files.append(add(name, f"isa = PBXFileReference; lastKnownFileType = {filetype}; path = App/{name}; sourceTree = SOURCE_ROOT;"))
assets = add("assets", 'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = App/Assets.xcassets; sourceTree = SOURCE_ROOT;')
files.append(assets)
package = add("package", 'isa = XCLocalSwiftPackageReference; relativePath = ".";')
project_configs = [add("project." + mode, f"isa = XCBuildConfiguration; name = {mode}; buildSettings = {{ CLANG_ENABLE_MODULES = YES; SWIFT_STRICT_CONCURRENCY = complete; }};") for mode in ["Debug", "Release"]]
project_list = add("project.configs", f"isa = XCConfigurationList; buildConfigurations = {refs(project_configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
targets, products = [], []
for target_name, mac in [("FTPunk", False), ("FTPunkMac", True)]:
    prefix = target_name + "."
    product = add(prefix + "product", 'isa = PBXFileReference; explicitFileType = wrapper.application; path = FTPunk.app; sourceTree = BUILT_PRODUCTS_DIR;')
    products.append(product)
    sources = [add(prefix + file_id + ".build", f"isa = PBXBuildFile; fileRef = {file_id};") for file_id in swift_files]
    resource = add(prefix + "assets.build", f"isa = PBXBuildFile; fileRef = {assets};")
    dependencies, frameworks = [], []
    for module in ["FTPunkDomain", "FTPunkDevices", "FTPunkStorage", "FTPunkIntegrations"]:
        dependency = add(prefix + module, f"isa = XCSwiftPackageProductDependency; package = {package}; productName = {module};")
        dependencies.append(dependency)
        frameworks.append(add(prefix + module + ".build", f"isa = PBXBuildFile; productRef = {dependency};"))
    phases = [
        add(prefix + "sources", f"isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {refs(sources)}; runOnlyForDeploymentPostprocessing = 0;"),
        add(prefix + "frameworks", f"isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = {refs(frameworks)}; runOnlyForDeploymentPostprocessing = 0;"),
        add(prefix + "resources", f"isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({resource}); runOnlyForDeploymentPostprocessing = 0;")
    ]
    configs = []
    for mode in ["Debug", "Release"]:
        values = {
            "PRODUCT_BUNDLE_IDENTIFIER": "com.kainkordian.ftpunk.mac" if mac else "com.kainkordian.ftpunk",
            "PRODUCT_NAME": "FTPunk", "SWIFT_VERSION": "6.0", "INTERVALS_OAUTH_CLIENT_ID": "",
            "SDKROOT": "macosx" if mac else "iphoneos",
            "SUPPORTED_PLATFORMS": "macosx" if mac else "iphoneos iphonesimulator",
            "INFOPLIST_FILE": "App/MacInfo.plist" if mac else "App/Info.plist",
            "GENERATE_INFOPLIST_FILE": "NO", "CODE_SIGN_STYLE": "Automatic",
            "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
            "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if mode == "Debug" else "-O",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG" if mode == "Debug" else "",
            "ONLY_ACTIVE_ARCH": "YES" if mode == "Debug" else "NO",
            "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/../Frameworks" if mac else "$(inherited) @executable_path/Frameworks",
        }
        if mac:
            values.update({"MACOSX_DEPLOYMENT_TARGET": "14.0", "ENABLE_HARDENED_RUNTIME": "YES", "CODE_SIGN_ENTITLEMENTS": "App/Mac.entitlements"})
        else:
            values.update({"IPHONEOS_DEPLOYMENT_TARGET": "18.0", "TARGETED_DEVICE_FAMILY": "1,2"})
        configs.append(add(prefix + mode, f"isa = XCBuildConfiguration; name = {mode}; buildSettings = {{ {settings(values)} }};"))
    config_list = add(prefix + "configs", f"isa = XCConfigurationList; buildConfigurations = {refs(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
    target = add(prefix + "target", f"isa = PBXNativeTarget; name = {target_name}; productName = FTPunk; productType = {quoted('com.apple.product-type.application')}; productReference = {product}; buildConfigurationList = {config_list}; buildPhases = {refs(phases)}; buildRules = (); dependencies = (); packageProductDependencies = {refs(dependencies)};")
    targets.append(target)
    schemes = PROJECT / "xcshareddata" / "xcschemes"
    schemes.mkdir(parents=True, exist_ok=True)
    reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="FTPunk.app" BlueprintName="{target_name}" ReferencedContainer="container:FTPunk.xcodeproj"/>'
    (schemes / f"{target_name}.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"><Testables/></TestAction>
  <LaunchAction buildConfiguration="Debug" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
products_group = add("products", f"isa = PBXGroup; name = Products; children = {refs(products)}; sourceTree = {quoted('<group>')};")
group = add("group", f"isa = PBXGroup; children = {refs(files + [products_group])}; sourceTree = {quoted('<group>')};")
root = add("project", f"isa = PBXProject; attributes = {{ LastUpgradeCheck = 1600; }}; buildConfigurationList = {project_list}; compatibilityVersion = {quoted('Xcode 14.0')}; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {group}; productRefGroup = {products_group}; projectDirPath = {quoted('')}; projectRoot = {quoted('')}; targets = {refs(targets)}; packageReferences = ({package});")
(PROJECT / "project.pbxproj").write_text("// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n" + "\n".join(objects) + f"\n\t}};\n\trootObject = {root};\n}}\n")
print("Generated FTPunk (iOS) and FTPunkMac (native macOS) schemes")
