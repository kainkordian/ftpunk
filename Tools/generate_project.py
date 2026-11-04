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


def key_for(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()


def add(name, content):
    key = key_for(name)
    objects.append(f"\t\t{key} = {{ {content} }};")
    return key


def refs(values):
    return "(" + ", ".join(values) + ")"


def settings(values):
    return " ".join(f"{key} = {quoted(value)};" for key, value in values.items())


files, swift_files = [], []
for path in sorted((ROOT / "App").rglob("*.swift")):
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
# The iOS target is not called "FTPunk": the Swift package already vends an executable product with
# that name, and Xcode resolves the UI tests' TEST_TARGET_NAME by name, so "FTPunk" could be
# resolved to the package executable (".../Debug-iphonesimulator/FTPunk", no ".app"). The scheme
# name, product (FTPunk.app) and bundle id stay as they were. The UI test target also carries an
# explicit TestTargetID (below), which is what the IDE's test runner uses to find the app under test.
IOS_TARGET_NAME = "FTPunkiOS"
for scheme_name, target_name, mac in [("FTPunk", IOS_TARGET_NAME, False), ("FTPunkMac", "FTPunkMac", True)]:
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
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
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
    (schemes / f"{scheme_name}.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"><Testables/></TestAction>
  <LaunchAction buildConfiguration="Debug" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')

# UI smoke tests (iOS only). They drive the simulator, so they are compiled with build-for-testing
# and run only when someone explicitly asks for a UI test run.
ui_files = []
for path in sorted((ROOT / "UITests").rglob("*.swift")):
    relative = path.relative_to(ROOT).as_posix()
    ui_files.append(add(relative, f"isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quoted(relative)}; sourceTree = SOURCE_ROOT;"))
files.extend(ui_files)
ui_name = "FTPunkUITests"
ui_product = add(ui_name + ".product", f'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = {ui_name}.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
ui_sources = [add(ui_name + "." + file_id + ".build", f"isa = PBXBuildFile; fileRef = {file_id};") for file_id in ui_files]
ui_phases = [
    add(ui_name + ".sources", f"isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {refs(ui_sources)}; runOnlyForDeploymentPostprocessing = 0;"),
    add(ui_name + ".frameworks", "isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;"),
]
ui_proxy = add(ui_name + ".proxy", f"isa = PBXContainerItemProxy; containerPortal = {key_for('project')}; proxyType = 1; remoteGlobalIDString = {targets[0]}; remoteInfo = {IOS_TARGET_NAME};")
ui_dependency = add(ui_name + ".dependency", f"isa = PBXTargetDependency; target = {targets[0]}; targetProxy = {ui_proxy};")
ui_configs = []
for mode in ["Debug", "Release"]:
    values = {
        "PRODUCT_BUNDLE_IDENTIFIER": "com.kainkordian.ftpunk.uitests", "PRODUCT_NAME": "$(TARGET_NAME)",
        "SWIFT_VERSION": "5.0", "SDKROOT": "iphoneos", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
        "GENERATE_INFOPLIST_FILE": "YES", "TEST_TARGET_NAME": IOS_TARGET_NAME, "IPHONEOS_DEPLOYMENT_TARGET": "18.0",
        "TARGETED_DEVICE_FAMILY": "1,2", "CODE_SIGN_STYLE": "Automatic",
        "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks @loader_path/Frameworks",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if mode == "Debug" else "-O",
    }
    ui_configs.append(add(ui_name + "." + mode, f"isa = XCBuildConfiguration; name = {mode}; buildSettings = {{ {settings(values)} }};"))
ui_config_list = add(ui_name + ".configs", f"isa = XCConfigurationList; buildConfigurations = {refs(ui_configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
ui_target = add(ui_name + ".target", f"isa = PBXNativeTarget; name = {ui_name}; productName = {ui_name}; productType = {quoted('com.apple.product-type.bundle.ui-testing')}; productReference = {ui_product}; buildConfigurationList = {ui_config_list}; buildPhases = {refs(ui_phases)}; buildRules = (); dependencies = ({ui_dependency});")
ui_reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ui_target}" BuildableName="{ui_name}.xctest" BlueprintName="{ui_name}" ReferencedContainer="container:FTPunk.xcodeproj"/>'
# Attach the test target to the iOS scheme only.
scheme_path = PROJECT / "xcshareddata" / "xcschemes" / "FTPunk.xcscheme"
scheme = scheme_path.read_text()
scheme = scheme.replace("</BuildActionEntries>", f'<BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="NO">{ui_reference}</BuildActionEntry></BuildActionEntries>')
scheme = scheme.replace("<Testables/>", f'<Testables><TestableReference skipped="NO">{ui_reference}</TestableReference></Testables>')
scheme_path.write_text(scheme)
targets.append(ui_target)
products.append(ui_product)
products_group = add("products", f"isa = PBXGroup; name = Products; children = {refs(products)}; sourceTree = {quoted('<group>')};")
group = add("group", f"isa = PBXGroup; children = {refs(files + [products_group])}; sourceTree = {quoted('<group>')};")
root = add("project", f"isa = PBXProject; attributes = {{ LastUpgradeCheck = 1600; TargetAttributes = {{ {ui_target} = {{ TestTargetID = {targets[0]}; }}; }}; }}; buildConfigurationList = {project_list}; compatibilityVersion = {quoted('Xcode 14.0')}; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {group}; productRefGroup = {products_group}; projectDirPath = {quoted('')}; projectRoot = {quoted('')}; targets = {refs(targets)}; packageReferences = ({package});")
(PROJECT / "project.pbxproj").write_text("// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n" + "\n".join(objects) + f"\n\t}};\n\trootObject = {root};\n}}\n")
print("Generated FTPunk (iOS) and FTPunkMac (native macOS) schemes")
