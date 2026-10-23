#!/usr/bin/env python3
"""Generate a dependency-free Xcode project referencing the local Swift package."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "FTPunk.xcodeproj"


def identifier(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()


def quoted(value):
    return json.dumps(str(value))


objects = []


def add(name, content):
    key = identifier(name)
    objects.append(f"\t\t{key} = {{ {content} }};")
    return key


def refs(values):
    return "(" + ", ".join(values) + ")"


sources, files = [], []
for path in sorted((ROOT / "App").glob("*.swift")):
    relative = path.relative_to(ROOT).as_posix()
    file_id = add(relative, f"isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quoted(relative)}; sourceTree = SOURCE_ROOT;")
    files.append(file_id)
    sources.append(add(relative + ".build", f"isa = PBXBuildFile; fileRef = {file_id};"))

plist = add("plist", 'isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = App/Info.plist; sourceTree = SOURCE_ROOT;')
assets = add("assets", 'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = App/Assets.xcassets; sourceTree = SOURCE_ROOT;')
resource = add("assets.build", f"isa = PBXBuildFile; fileRef = {assets};")
product = add("product", 'isa = PBXFileReference; explicitFileType = wrapper.application; path = FTPunk.app; sourceTree = BUILT_PRODUCTS_DIR;')
products = add("products", f"isa = PBXGroup; name = Products; children = ({product}); sourceTree = {quoted('<group>')};")
group = add("group", f"isa = PBXGroup; children = {refs(files + [plist, assets, products])}; sourceTree = {quoted('<group>')};")
package = add("package", 'isa = XCLocalSwiftPackageReference; relativePath = ".";')
dependencies, frameworks = [], []
for module in ["FTPunkDomain", "FTPunkDevices", "FTPunkStorage", "FTPunkIntegrations"]:
    dependency = add(module, f"isa = XCSwiftPackageProductDependency; package = {package}; productName = {module};")
    dependencies.append(dependency)
    frameworks.append(add(module + ".build", f"isa = PBXBuildFile; productRef = {dependency};"))

source_phase = add("sources", f"isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {refs(sources)}; runOnlyForDeploymentPostprocessing = 0;")
resource_phase = add("resources", f"isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({resource}); runOnlyForDeploymentPostprocessing = 0;")
framework_phase = add("frameworks", f"isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = {refs(frameworks)}; runOnlyForDeploymentPostprocessing = 0;")

target_configs, project_configs = [], []
for mode in ["Debug", "Release"]:
    target_settings = {
        "PRODUCT_BUNDLE_IDENTIFIER": "com.kainkordian.ftpunk",
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "SWIFT_VERSION": "6.0",
        "INTERVALS_OAUTH_CLIENT_ID": "",
        "IPHONEOS_DEPLOYMENT_TARGET": "18.0",
        "TARGETED_DEVICE_FAMILY": "1,2",
        "SDKROOT": "iphoneos",
        "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
        "INFOPLIST_FILE": "App/Info.plist",
        "GENERATE_INFOPLIST_FILE": "NO",
        "CODE_SIGN_STYLE": "Automatic",
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if mode == "Debug" else "-O",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG" if mode == "Debug" else "",
        "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks",
    }
    settings = " ".join(f"{key} = {quoted(value)};" for key, value in target_settings.items())
    target_configs.append(add("target." + mode, f"isa = XCBuildConfiguration; name = {mode}; buildSettings = {{ {settings} }};"))
    project_configs.append(add("project." + mode, f"isa = XCBuildConfiguration; name = {mode}; buildSettings = {{ CLANG_ENABLE_MODULES = YES; SWIFT_STRICT_CONCURRENCY = complete; }};"))

target_list = add("target.configs", f"isa = XCConfigurationList; buildConfigurations = {refs(target_configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
project_list = add("project.configs", f"isa = XCConfigurationList; buildConfigurations = {refs(project_configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
target = add("target", f"isa = PBXNativeTarget; name = FTPunk; productName = FTPunk; productType = {quoted('com.apple.product-type.application')}; productReference = {product}; buildConfigurationList = {target_list}; buildPhases = {refs([source_phase, framework_phase, resource_phase])}; buildRules = (); dependencies = (); packageProductDependencies = {refs(dependencies)};")
root = add("project", f"isa = PBXProject; attributes = {{ LastUpgradeCheck = 1600; }}; buildConfigurationList = {project_list}; compatibilityVersion = {quoted('Xcode 14.0')}; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {group}; productRefGroup = {products}; projectDirPath = {quoted('')}; projectRoot = {quoted('')}; targets = ({target}); packageReferences = ({package});")

PROJECT.mkdir(exist_ok=True)
(PROJECT / "project.pbxproj").write_text("// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n" + "\n".join(objects) + f"\n\t}};\n\trootObject = {root};\n}}\n")
schemes = PROJECT / "xcshareddata" / "xcschemes"
schemes.mkdir(parents=True, exist_ok=True)
reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="FTPunk.app" BlueprintName="FTPunk" ReferencedContainer="container:FTPunk.xcodeproj"/>'
(schemes / "FTPunk.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"><Testables/></TestAction>
  <LaunchAction buildConfiguration="Debug" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print("Generated FTPunk.xcodeproj")
