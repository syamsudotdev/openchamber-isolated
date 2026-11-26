"""Stand-in for Xcode's asset symbol generator (GeneratedAssetSymbols.swift).

Linux has no actool. This script reads the image sets and color sets of the given
asset catalogs and writes ImageResource and ColorResource constants plus
back-deployed UIKit and SwiftUI initializers, as Xcode does for a deployment
target below iOS 17. In a package target it loads from Bundle.module.

Usage: asset_symbols.py [--extensions] [--uikit-headers DIR] OUTPUT.swift CATALOG...

--extensions adds what ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS
adds in Xcode: UIColor, SwiftUI Color and ShapeStyle statics for color sets, and
UIImage statics for image sets. Like Xcode, it skips a name that the SDK already
declares on that type (UIKit class properties read from --uikit-headers, for example
UIImage.add from `addImage`; SwiftUI's system colors).
"""

import json
import os
import re
import sys


def symbol_name(asset, suffix):
    words = [w for w in re.split(r"[^A-Za-z0-9]+", asset) if w]
    if not words:
        return None
    first = words[0]
    # A leading capital run is lowered, keeping the capital that starts the
    # next word: "NLChevron" -> "nlChevron", "URL" -> "url".
    match = re.match(r"^([A-Z]+)(?=[A-Z][a-z]|$)", first)
    if match:
        first = match.group(1).lower() + first[len(match.group(1)) :]
    else:
        first = first[0].lower() + first[1:]
    name = first + "".join(w[0].upper() + w[1:] for w in words[1:])
    # A letter after a digit starts a new word: "24px" -> "24Px".
    name = re.sub(r"(\d)([a-z])", lambda m: m.group(1) + m.group(2).upper(), name)
    if name.endswith(suffix) and name != suffix.lower():
        name = name[: -len(suffix)]
    if name[0].isdigit():
        name = "_" + name
    return name


def asset_sets(catalog, extension):
    """Yield the asset name of each set, with namespace folder prefixes."""
    for root, dirs, _files in os.walk(catalog):
        dirs.sort()
        for directory in dirs:
            if not directory.endswith(extension):
                continue
            prefix = []
            parent = root
            while os.path.abspath(parent) != os.path.abspath(catalog):
                contents = os.path.join(parent, "Contents.json")
                if os.path.exists(contents):
                    props = json.load(open(contents)).get("properties", {})
                    if props.get("provides-namespace"):
                        prefix.insert(0, os.path.basename(parent))
                parent = os.path.dirname(parent)
            yield "/".join(prefix + [directory[: -len(extension)]])


def collect(catalogs, extension, suffix):
    symbols = {}
    for catalog in catalogs:
        for asset in asset_sets(catalog, extension):
            name = symbol_name(asset, suffix)
            if name and name not in symbols:
                symbols[name] = asset
    return symbols


def resource_type(kind, symbols):
    lines = [
        f"/// A {kind.lower()} resource.",
        f"struct {kind}Resource: Swift.Hashable, Swift.Sendable {{",
        "    fileprivate let name: Swift.String",
        "    nonisolated(unsafe) fileprivate let bundle: Foundation.Bundle",
        "    init(name: Swift.String, bundle: Foundation.Bundle) {",
        "        self.name = name",
        "        self.bundle = bundle",
        "    }",
        "}",
        "",
        f"extension {kind}Resource {{",
    ]
    for name in sorted(symbols):
        asset = symbols[name].replace("\\", "\\\\").replace('"', '\\"')
        lines.append(
            f'    static let {name} = {kind}Resource(name: "{asset}", bundle: resourceBundle)'
        )
    return lines + ["}", ""]


SWIFTUI_COLOR_NAMES = {
    "accentColor", "black", "blue", "brown", "clear", "cyan", "gray", "green", "indigo",
    "mint", "orange", "pink", "primary", "purple", "red", "secondary", "teal", "white",
    "yellow",
}


def uikit_class_names(headers, type_name):
    """Swift names of the UIKit class properties that return type_name: the ObjC
    importer drops the type's suffix ("addImage" -> "add", "redColor" -> "red")."""
    names = set()
    if not headers or not os.path.isdir(headers):
        return names
    suffix = type_name[2:]  # "UIImage" -> "Image"
    pattern = re.compile(r"@property\s*\(\s*class[^)]*\)\s*" + type_name + r"\s*\*\s*(?:_Nonnull\s*|nonnull\s*)?(\w+)")
    for name in os.listdir(headers):
        if name.endswith(".h"):
            text = open(os.path.join(headers, name), errors="ignore").read()
            for match in pattern.finditer(text):
                prop = match.group(1)
                names.add(prop[: -len(suffix)] if prop.endswith(suffix) and prop != suffix else prop)
    return names


def extensions(images, colors, headers):
    skip_image = uikit_class_names(headers, "UIImage")
    skip_color = uikit_class_names(headers, "UIColor")
    lines = ["#if canImport(UIKit)"]
    lines.append("extension UIKit.UIColor {")
    for name in sorted(n for n in colors if n not in skip_color):
        lines.append(f"    static var {name}: UIKit.UIColor {{ .init(resource: ColorResource.{name}) }}")
    lines += ["}", "", "extension UIKit.UIImage {"]
    for name in sorted(n for n in images if n not in skip_image):
        lines.append(f"    static var {name}: UIKit.UIImage {{ .init(resource: ImageResource.{name}) }}")
    lines += ["}", "#endif", "", "#if canImport(SwiftUI)", "extension SwiftUI.Color {"]
    swiftui = sorted(n for n in colors if n not in SWIFTUI_COLOR_NAMES)
    for name in swiftui:
        lines.append(f"    static var {name}: SwiftUI.Color {{ .init(ColorResource.{name}) }}")
    lines += ["}", "", "extension SwiftUI.ShapeStyle where Self == SwiftUI.Color {"]
    for name in swiftui:
        lines.append(f"    static var {name}: SwiftUI.Color {{ .init(ColorResource.{name}) }}")
    lines += ["}", "#endif", ""]
    return lines


def main():
    argv = sys.argv[1:]
    with_extensions = "--extensions" in argv
    argv = [a for a in argv if a != "--extensions"]
    headers = None
    if "--uikit-headers" in argv:
        i = argv.index("--uikit-headers")
        headers = argv[i + 1]
        del argv[i : i + 2]
    output, catalogs = argv[0], argv[1:]
    images = collect(catalogs, ".imageset", "Image")
    colors = collect(catalogs, ".colorset", "Color")
    lines = [
        "// Generated by ios-xcodeproj-build-linux/scripts/asset_symbols.py.",
        "// Linux stand-in for Xcode's GeneratedAssetSymbols.swift.",
        "import Foundation",
        "#if canImport(UIKit)",
        "import UIKit",
        "#endif",
        "#if canImport(SwiftUI)",
        "import SwiftUI",
        "#endif",
        "",
        "#if SWIFT_PACKAGE",
        "private let resourceBundle = Foundation.Bundle.module",
        "#else",
        "private class ResourceBundleClass {}",
        "private let resourceBundle = Foundation.Bundle(for: ResourceBundleClass.self)",
        "#endif",
        "",
    ]
    lines += resource_type("Image", images)
    lines += resource_type("Color", colors)
    lines += [
        "#if canImport(UIKit)",
        "extension UIKit.UIImage {",
        "    convenience init(resource: ImageResource) {",
        "        self.init(named: resource.name, in: resource.bundle, compatibleWith: nil)!",
        "    }",
        "}",
        "",
        "extension UIKit.UIColor {",
        "    convenience init(resource: ColorResource) {",
        "        self.init(named: resource.name, in: resource.bundle, compatibleWith: nil)!",
        "    }",
        "}",
        "#endif",
        "",
        "#if canImport(SwiftUI)",
        "extension SwiftUI.Image {",
        "    init(_ resource: ImageResource) {",
        "        self.init(resource.name, bundle: resource.bundle)",
        "    }",
        "}",
        "",
        "extension SwiftUI.Color {",
        "    init(_ resource: ColorResource) {",
        "        self.init(resource.name, bundle: resource.bundle)",
        "    }",
        "}",
        "#endif",
        "",
    ]
    if with_extensions:
        lines += extensions(images, colors, headers)
    with open(output, "w") as handle:
        handle.write("\n".join(lines))
    print(f"SYMBOLS: images={len(images)} colors={len(colors)}", flush=True)


if __name__ == "__main__":
    main()
