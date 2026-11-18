"""Example: write the Linux overlay for one app revision as a unified patch.

Set APP, PACKAGE and the expected line numbers for your project.

Each edit checks the exact text it replaces, so a different revision fails
instead of being patched in the wrong place. Output: <gate>/linux-overlay.patch.
"""

import os
import shutil
import subprocess
import sys

APP = "<APP>"  # the app source folder, APP_SOURCES in references/build.md
PACKAGE = "<PACKAGE>"  # the local Swift package that holds the preview code

gate, stamp = sys.argv[1], sys.argv[2]
src = f"{gate}/src"
work = f"{gate}/overlay-work"
shutil.rmtree(work, ignore_errors=True)
for side in ("a", "b"):
    os.makedirs(f"{work}/{side}/XcodeGen")
    shutil.copy(f"{src}/project.yml", f"{work}/{side}/project.yml")
    shutil.copy(f"{src}/XcodeGen/base.yml", f"{work}/{side}/XcodeGen/base.yml")

lines = open(f"{work}/b/project.yml").read().split("\n")


def expect(number, text):
    actual = lines[number - 1].strip()
    if actual != text:
        raise SystemExit(f"project.yml:{number}: expected {text!r}, found {actual!r}")


# Asset symbols, and their UIColor/UIImage extensions, come from the actool stand-in
# (scripts/stub-tools/actool), so the asset symbol settings stay as they are.
# Extensions are dropped (user decision): remove the target dependencies and
# the CTNotificationContent embed script that serves only the content extension.
expect(333, f"- target: {APP}NotificationServiceExtension")
expect(334, f"- target: {APP}NotificationContentExtension")
expect(335, "postBuildScripts:")
expect(340, "- name: Embed CTNotificationContent")
expect(361, 'echo "Embedded CTNotificationContent.framework into ${DEST}"')
expect(362, "- script: |")
# Needs macOS: the Crashlytics upload runs a macOS executable.
expect(383, '"${BUILD_DIR%/Build/*}/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run"')
# The Darwin SDK toolset has no bitcode_strip (build 13); bitcode is obsolete since
# Xcode 14, so embedded frameworks are copied without stripping it.
expect(176, f"INFOPLIST_FILE: {APP}/Supporting Files/Info.plist")
lines[175] = lines[175] + "\n        STRIP_BITCODE_FROM_COPIED_FILES: NO"
# The build is unsigned; zsign signs the IPA later. xtool's codesign emulation rejects
# the options Swift Build passes when it signs embedded frameworks (build 17).
lines[175] = lines[175] + "\n        CODE_SIGNING_ALLOWED: NO"
# Swift Build takes its toolchain from the Linux Swift distribution, which has no iOS
# back-deployment libraries (libswiftCompatibility*.a); the app link needs them for
# objects built for older deployment targets (build 20). The SDK's Xcode toolchain has
# them.
expect(194, 'OTHER_LDFLAGS: "-ObjC"')
compat = (f"{gate}/home/.config/xtool/darwin.xtoolsdk/Xcode.app/Contents/Developer/"
          "Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/iphoneos")
if not os.path.exists(f"{compat}/libswiftCompatibility56.a"):
    raise SystemExit(f"no back-deployment libraries in {compat}")
lines[193] = lines[193].replace('"-ObjC"', f'"-ObjC -L{compat}"')
removed = {*range(333, 335), *range(336, 362), 383}
lines = [line for number, line in enumerate(lines, 1) if number not in removed]
open(f"{work}/b/project.yml", "w").write("\n".join(lines))

base = open(f"{work}/b/XcodeGen/base.yml").read()
if base.count("    CURRENT_PROJECT_VERSION: 1\n") != 1:
    raise SystemExit("XcodeGen/base.yml: CURRENT_PROJECT_VERSION: 1 not found once")
base = base.replace("    CURRENT_PROJECT_VERSION: 1\n", f"    CURRENT_PROJECT_VERSION: {stamp}\n")
open(f"{work}/b/XcodeGen/base.yml", "w").write(base)

# Swift 6.4.1 with the iOS 27 SwiftUI @State macro rejects `@State static var`
# ("static functions must not be declared mutating"). Preview code only.
client = f"Packages/{PACKAGE}/Sources/{PACKAGE}/Client/ClientView.swift"
for side in ("a", "b"):
    os.makedirs(os.path.dirname(f"{work}/{side}/{client}"), exist_ok=True)
    shutil.copy(f"{src}/{client}", f"{work}/{side}/{client}")
text = open(f"{work}/b/{client}").read()
old_property = "    @State static var initParams: [AnyHashable: Any] = [:]\n"
old_binding = "            initParams: $initParams,\n"
if text.count(old_property) != 1 or text.count(old_binding) != 1:
    raise SystemExit(f"{client}: preview text not found once")
text = text.replace(old_property, "").replace(old_binding, "            initParams: .constant([:]),\n")
open(f"{work}/b/{client}", "w").write(text)

# Swift Build's built-in .strings copy on Linux decodes none of the TUSafariActivity
# translations, ASCII included (builds 11 and 12), and an XcodeGen exclude did not
# remove them from the project. The gate copy deletes them; a recorded limit.
assets = f"{APP}/Common/Third Parties/TUSafariActivity/Assets"
deleted = 0
for folder in sorted(os.listdir(f"{src}/{assets}")):
    rel = f"{assets}/{folder}/TUSafariActivity.strings"
    if folder.endswith(".lproj") and os.path.exists(f"{src}/{rel}"):
        os.makedirs(os.path.dirname(f"{work}/a/{rel}"), exist_ok=True)
        shutil.copy(f"{src}/{rel}", f"{work}/a/{rel}")
        deleted += 1
if deleted != 21:
    raise SystemExit(f"expected 21 TUSafariActivity.strings files, found {deleted}")
print(f"DELETED TUSafariActivity.strings files: {deleted}", flush=True)

# libGoogleConversionTracking.a holds 1,521 "private external" l<digits> symbols in its
# Objective-C string sections; ld64.lld reports them as duplicates (build 20). The gate
# uses its arm64 slice with those symbols made local (llvm-objcopy --localize-symbol);
# the exported symbols are unchanged. Made by scripts/localize-act.sh into gen/.
act = f"{APP}/Common/Third Parties/ACTReporter/libGoogleConversionTracking.a"
for side, source in (("a", f"{src}/{act}"), ("b", f"{gate}/gen/libGoogleConversionTracking.a")):
    os.makedirs(os.path.dirname(f"{work}/{side}/{act}"), exist_ok=True)
    shutil.copy(source, f"{work}/{side}/{act}")

# Binary-safe (UTF-16 .strings): apply with `git apply -p1` in <gate>/src.
diff = subprocess.run(
    ["git", "diff", "--no-index", "--binary", "--no-prefix", "a", "b"],
    cwd=work, capture_output=True,
)
if diff.returncode != 1:
    raise SystemExit(f"git diff failed: {diff.stderr.decode()}")
open(f"{gate}/linux-overlay.patch", "wb").write(diff.stdout)
print(f"REMOVED project.yml lines: {len(removed)}", flush=True)
