# KMP framework, signed IPA, and authorized device workflow

## Prerequisites

- Complete the setup handoff and the main skill's preflight.
- Approve the concrete source and build actions before execution.
- Resolve actual project names, paths, tasks, versions, and resource destinations.
- Use a qualified Linux Kotlin/Native port or an approved supported-macOS framework build.
- Request the default signed goal's identity/private key, profiles, bundle/team IDs, and target through the main skill's step 0.
- Obtain separate signing approval and explicit security approval for the selected key-handling method.

The framework and unsigned-intermediate pipeline adapts steps 7–11 of `/workspace/oneai-linux-probe/LINUX-IOS-IPA-BUILD.md`, source SHA256 `a83f2e0b22311bade7d82a141a56d930cbfe33a9537acf29320996db0679b34d`; preserve that source unchanged.
The fresh-Debian procedure was not clean-room tested; other-distribution adaptations are not automatically validated.
The examples describe Debian paths, not universal Linux package or compiler compatibility.

Examples use `/home/iosbuilder/ios-linux/src/ExampleApp`, module `shared`, framework `Shared`, host product `ExampleApp`, identifier `com.example.exampleapp`, and iOS `16.0`.
Replace these values consistently before use, including the example tool and SDK paths.
Use the installed versions and trust evidence from setup, not an assumed JDK or SDK version.
Each shell block contains one physical command; stop on failure.
The protected signing fragments in section 8 require one approved controlled lifetime, not independent tool calls.
The default deliverable is a signed development IPA; unsigned output alone completes the goal only when the user explicitly narrows it.

## 1. Build the actual framework

Proceed only when setup proves that the version-matched port enables Apple final-binary tasks on the actual Linux host and integrates with this project's Gradle/plugin pipeline.
An installed Swift SDK is insufficient.
If this gate fails, return the port blocker to `kmp-ios-setup-linux`; never substitute a skipped Kotlin task or a dummy framework.

```sh
cd /home/iosbuilder/ios-linux/src/ExampleApp
```
Select the inspected KMP checkout.

```sh
./gradlew :shared:linkReleaseFrameworkIosArm64
```
Run the actual Release framework task only after the preceding qualification gate; replace the example task with the project's task.

Retain the build log, compiler/plugin versions, link arguments, and actual output path.
Require an executed task, nonempty iOS variant dependencies, and the actual Compose compiler and cinterop inputs where used.
Check that the output contains compiled implementations of the expected exported Kotlin APIs, not only declarations.
Run resource generation/sync tasks selected from this project's configuration.
Finish with a real static device framework and its generated resources.

## 2. Stage the device-only XCFramework

Inspect the actual framework before copying it.
Require a static archive with device ARM64 Mach-O members and a compatible deployment minimum.
Check exported headers, module map, framework/module names, and native ABI dependencies.
Use the qualified port's baseline ARM64 selection for universal native archives and flattened archive members rather than nested archives.
Stop this static route if the framework is dynamic.

```sh
mkdir -p /home/iosbuilder/ios-linux/src/ExampleApp/Frameworks/Shared.xcframework/ios-arm64
```
Prepare the inspected framework's device slice destination after confirming that it will not overwrite unrelated outputs.

```sh
cp -a /home/iosbuilder/ios-linux/src/ExampleApp/shared/build/bin/iosArm64/releaseFramework/Shared.framework /home/iosbuilder/ios-linux/src/ExampleApp/Frameworks/Shared.xcframework/ios-arm64/
```
Stage the actual Gradle output; adapt the source path to the recorded task output.

Write `Frameworks/Shared.xcframework/Info.plist` with the actual slice name and framework name:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
  <key>AvailableLibraries</key><array><dict>
    <key>LibraryIdentifier</key><string>ios-arm64</string>
    <key>LibraryPath</key><string>Shared.framework</string>
    <key>SupportedArchitectures</key><array><string>arm64</string></array>
    <key>SupportedPlatform</key><string>ios</string>
  </dict></array>
  <key>CFBundlePackageType</key><string>XFWK</string>
  <key>XCFrameworkFormatVersion</key><string>1.0</string>
</dict></plist>
```

```sh
sha256sum /home/iosbuilder/ios-linux/src/ExampleApp/shared/build/bin/iosArm64/releaseFramework/Shared.framework/Shared /home/iosbuilder/ios-linux/src/ExampleApp/Frameworks/Shared.xcframework/ios-arm64/Shared.framework/Shared
```
Record matching source and staged binary hashes as build provenance, not proof of executable linkage.

Finish when the staged binary, headers, module map, and metadata match the actual output.

## 3. Wrap the real Swift host

Preserve the existing host entry point and exported Kotlin API calls.
Reuse an existing compatible SwiftPM layout where available.
Otherwise, place the real host sources under `Sources/ExampleApp`, with approved path changes, and preserve all additional dependencies.
Use this minimal `Package.swift` shape only after resolving the host's requirements:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ExampleApp",
    platforms: [.iOS(.v16)],
    products: [.library(name: "ExampleApp", targets: ["ExampleApp"])],
    targets: [
        .binaryTarget(name: "Shared", path: "Frameworks/Shared.xcframework"),
        .target(name: "ExampleApp", dependencies: ["Shared"])
    ]
)
```

Match the Swift tools version to the actual source and toolchain requirements.
Import the real framework module in the existing host.
Derive extra libraries and system frameworks from actual producer documentation, link arguments, or Mach-O auto-link metadata; there is no universal native-framework list.
Static Kotlin code links into the app executable and does not need dynamic framework embedding.
Finish when the manifest retains the real host behavior and all required dependency links.

## 4. Preserve metadata and resource policy

Use `xtool.yml` with the actual product, identifier, and existing or adapted plist path:

```yaml
version: 1
bundleID: com.example.exampleapp
product: ExampleApp
infoPath: Info.plist
```

Adapt the existing Info.plist rather than replacing its application policy.
Resolve Xcode build macros to literal values, including versions, identifier, executable, and deployment settings.
This example shows basic fields only; preserve actual permissions, orientations, capabilities, URL schemes, and other host settings:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>ExampleApp</string>
  <key>CFBundleIdentifier</key><string>com.example.exampleapp</string>
  <key>CFBundleName</key><string>ExampleApp</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSRequiresIPhoneOS</key><true/>
  <key>MinimumOSVersion</key><string>16.0</string>
</dict></plist>
```

Keep the deployment minimum compatible across Kotlin/native inputs, SwiftPM, and the plist.
Inspect the real resource loader before selecting copy rules.
Use SwiftPM bundles if that loader expects bundles.
Use main-bundle `compose-resources/...` only if required by the actual Compose loader.
Preserve generated bytes, assets, fonts, and licenses.
Record a source-to-destination manifest and source SHA256 values for every required resource.
Configure packaging from that manifest; do not invent a universal root-resource directory.
Finish when every required source resource has a documented packaged destination and hash.

## 5. Build the unsigned Release IPA intermediate

Use setup's literal environment only when it was selected for this installation.
The following long command illustrates an explicitly selected SDK configuration location, not a requirement to introduce XDG overrides or custom caches.
Keep the complete real Swift distribution selected before xtool's tools.
Include the actual SDK toolset for bare `dsymutil` calls.

```sh
cd /home/iosbuilder/ios-linux/src/ExampleApp
```
Select the SwiftPM packaging root containing the real host and compiled framework.

```sh
env PATH=/home/iosbuilder/ios-linux/tools/swift/usr/bin:/home/iosbuilder/ios-linux/config/swiftpm/swift-sdks/darwin.artifactbundle/toolset/bin:/home/iosbuilder/ios-linux/tools/xtool/squashfs-root/usr/bin:/usr/local/bin:/usr/bin:/bin SWIFT_EXEC=/home/iosbuilder/ios-linux/tools/swift/usr/bin/swiftc XDG_CONFIG_HOME=/home/iosbuilder/ios-linux/config /home/iosbuilder/ios-linux/tools/xtool/squashfs-root/AppRun dev build --configuration release --ipa
```
Build Release and package an unsigned IPA with the actual setup paths; omit `--sign`.

Require exit zero, xtool's completion message, and the actual unsigned-intermediate IPA path.
Use `/home/iosbuilder/ios-linux/src/ExampleApp/xtool/ExampleApp.ipa` only if this build reports that output.
An intermediate executable or successful Kotlin task alone does not complete this step.
Stage that reported output at `/home/iosbuilder/ios-linux/output/ExampleApp-unsigned.ipa` after approving the destination and checking for existing user data.
Require matching reported-output and staged-intermediate hashes before using the staged path below.
Use the distinct `/home/iosbuilder/ios-linux/output/ExampleApp-signed.ipa` path for signed output.

## 6. Inspect the unsigned intermediate

Inspect only the output of your own trusted build with these examples; they are not a hostile-ZIP validation procedure.

```sh
unzip -t /home/iosbuilder/ios-linux/output/ExampleApp-unsigned.ipa
```
Require every ZIP member and CRC check to pass.

```sh
unzip -Z -l /home/iosbuilder/ios-linux/output/ExampleApp-unsigned.ipa
```
Check paths, links, and attributes before extraction; require intended entries under `Payload/`, one intended app, and no absolute paths, parent traversal, backslash paths, or unexpected links.

```sh
unzip -q /home/iosbuilder/ios-linux/output/ExampleApp-unsigned.ipa -d /home/iosbuilder/ios-linux/verification
```
Extract the reviewed archive into a previously unused verification directory.

Use a capable plist parser that accepts both XML and binary plists.
Check the extracted Info.plist against independently recorded host requirements: identifier, executable, `APPL`, versions, minimum OS, and application-specific settings.
Verify that all required Xcode build macros became literal values.

```sh
/usr/bin/llvm-objdump --macho --private-headers /home/iosbuilder/ios-linux/verification/Payload/ExampleApp.app/ExampleApp
```
Use the setup-qualified inspector to require ARM64, `MH_EXECUTE`, device iOS platform, the intended minimum OS, and an executable entry such as `LC_MAIN`; record the SDK version separately.

ARM64 alone does not distinguish an iOS device binary from an ARM64 simulator binary.
Inspect linked libraries and load commands for unintended dependencies.
Confirm the static framework is not embedded or loaded as a dynamic runtime dependency.
Compare each resource's extracted SHA256 with the independently recorded source manifest at its actual destination.
Retain framework hashes and host link arguments.
Use a link map or capable symbol inspection to identify the expected compiled Kotlin entry point and required native implementations inside the executable.
A header, copied framework, or IPA hash alone does not prove Kotlin linkage.
Report incomplete validation if inspection tools or linkage evidence are unavailable.

```sh
wc -c /home/iosbuilder/ios-linux/output/ExampleApp-unsigned.ipa
```
Record the unsigned intermediate's size in bytes.

```sh
sha256sum /home/iosbuilder/ios-linux/output/ExampleApp-unsigned.ipa
```
Record the unsigned intermediate's identity without claiming runtime correctness or deterministic rebuilds.

Record the intermediate path, size, SHA256, project revision and dirty state, tool/SDK/port versions and provenance, check results, and signature state.
An `LC_CODE_SIGNATURE` can represent an ad-hoc linker signature rather than Apple developer signing.
Report `UnsignedIntermediate`; continue to signing for the default goal, subject to its separate authorization gates.

## 7. Validate signing inputs

Require setup's actual verified zsign v1.1.3 binary path and provenance; do not guess a Debian package or binary location.
zsign is a community tool, not an Apple tool.
xtool 1.22.2 `dev build --sign` uses xtool authentication rather than supplied `.p12` import; preserve unsigned packaging above and sign its output separately.
Use local protected paths such as `/secure/ios/AppleDevelopment.p12`, `/secure/ios/p12-password`, and `/secure/ios/App.mobileprovision`.
A `.cer` without its private key cannot sign; missing inputs block the signed goal rather than trigger an automatic unsigned fallback.

Before signing, validate these facts without dumping private keys, passwords, or profile contents to chat or external logs:
- The certificate and private key match; zsign's `X509_check_private_key` support does not replace the preflight gate.
- The identity certificate is within its validity dates and is an Apple Development identity.
- Each profile is current and unexpired; record profile authentication evidence or trusted provenance and any remaining chain-validation limit.
- Each app/extension bundle ID matches the profile App ID and team, and its intended device UDID is covered.
- Each profile's `DeveloperCertificates` contains the actual identity certificate.
- Requested signed entitlements are permitted by that profile, including `application-identifier`, keychain groups, and `get-task-allow` as the app needs.

Require a reviewed resolved intended entitlement file for each app/extension, derived from real app needs and required identity keys.
Resolve identity wildcards for the actual bundle/App ID and team; resolve Xcode macros instead of blindly copying target sources.
Use `/secure/ios/App.entitlements.plist` as the main app's read-only nonsecret metadata input after reviewing its exact intended keys and values in the signing plan.
Do not synthesize the intended set from the profile's whole `Entitlements` dictionary; it can include wildcards or unwanted capabilities.
Use an independent platform plist parser for actual profile values and dates, including binary plists where applicable.
CMS decoding with `openssl cms -verify -inform DER -noverify` can check the CMS signature and extract the plist, but does not authenticate the Apple certificate chain.
Record that distinction; parsing alone is not profile authentication.
Inspect actual `.appex`, frameworks, and dylibs; establish inside-out signing order and one matching profile per app/extension as needed.
zsign accepts repeatable `-m` profiles, but those do not prove per-bundle entitlement mapping; verify profile mapping and nested signing behavior for this archive.
Stop if entitlement, identity, profile, or nested-bundle requirements cannot be established.

## 8. Protected signing and signed-artifact checks

zsign accepts `-k` for a `.p12` or PEM private key, `-c` for a PEM/DER certificate, `-m` for profiles, `-e` for an entitlement file, and `-o` for output.
Require explicit `-e` with the reviewed resolved intended file; omission uses the profile's whole entitlement dictionary rather than the app's exact intended set.
Its password option takes a password in argv; no stdin, environment, or password-file mode is verified for zsign v1.1.3.
Use an approved secret-capable signer or human-managed signing if the controlled route below is unavailable.

### Approved OpenSSL 3 route

This route temporarily extracts an unencrypted PEM private key; private file modes alone do not authorize decryption.
Obtain explicit security approval for this exposure and the password-file method before starting.
The user supplies the local password-file path through a protected mechanism, not its contents in chat.
Require an owner-only `0600` password file and a fresh owner-only `0700` staging directory.
Keep the original `.p12` and password file unchanged; disable secret stdout, shell tracing, and debug logs.
Before extraction, arrange guarded cleanup for success, failure, and interruption in one approved controlled operation.
The executor must own that lifetime, wait for signing to finish, and remove only the key/certificate files it created.
If the execution mechanism cannot guarantee that cleanup, report a blocker rather than run independent decryption calls.
The following blocks are operation fragments, not a complete cleanup implementation or permission to execute them now.

```sh
mkdir -m 700 /secure/ios/staging-run-001
```
Require successful creation of a fresh directory; stop if it exists, and never overwrite existing user data.

```sh
install -m 600 /dev/null /secure/ios/staging-run-001/key.pem
```
Create the empty private-key destination only inside this operation's newly created staging directory.

```sh
install -m 600 /dev/null /secure/ios/staging-run-001/cert.pem
```
Create the empty certificate destination with owner-only permissions before extraction.

```sh
stat -c '%a %U %n' /secure/ios/p12-password /secure/ios/staging-run-001 /secure/ios/staging-run-001/key.pem /secure/ios/staging-run-001/cert.pem
```
Require the intended owner, mode `700` for staging, and mode `600` for the password/key/certificate files before extraction and again for output files afterward.

```sh
openssl pkcs12 -in /secure/ios/AppleDevelopment.p12 -passin file:/secure/ios/p12-password -nocerts -noenc -out /secure/ios/staging-run-001/key.pem
```
Extract the private key within the approved controlled lifetime; the password value stays out of argv, but its file path does not.

```sh
openssl pkcs12 -in /secure/ios/AppleDevelopment.p12 -passin file:/secure/ios/p12-password -clcerts -nokeys -out /secure/ios/staging-run-001/cert.pem
```
Extract the identity certificate without printing its contents and confirm that it is the validated signing certificate.

Use the following single-command route only when one reviewed entitlement set is appropriate for its signing targets.
If a nested app or `.appex` needs distinct entitlements, block this route until a verified per-bundle entitlement-file mapping and signing plan establishes actual tool behavior; additional `-m` profiles alone do not resolve this gate.

```sh
zsign -k /secure/ios/staging-run-001/key.pem -c /secure/ios/staging-run-001/cert.pem -m /secure/ios/App.mobileprovision -e /secure/ios/App.entitlements.plist -o /home/iosbuilder/ios-linux/output/ExampleApp-signed.ipa /home/iosbuilder/ios-linux/output/ExampleApp-unsigned.ipa
```
Replace `zsign` with setup's actual verified binary path only after the entitlement and signing-plan gates pass.

```sh
rm -- /secure/ios/staging-run-001/key.pem /secure/ios/staging-run-001/cert.pem
```
The approved cleanup removes only these operation-created files after tools finish, including failure/interruption paths.

```sh
test ! -e /secure/ios/staging-run-001/key.pem
```
Verify removal of the temporary private-key file without claiming secure SSD erasure.

```sh
test ! -e /secure/ios/staging-run-001/cert.pem
```
Verify removal of the temporary certificate file while preserving the original `.p12` and password file.

### Signed-artifact evidence

Require signer exit zero, its completion evidence, and a nonempty signed output at the distinct destination.
Repeat section 6's ZIP, plist, device-platform, resource, and linkage checks on that signed output in a fresh verification directory.
Account for expected executable signature/profile/entitlement changes without excusing unrelated resource changes.
Check embedded profiles against section 7 and independently read actual signed entitlements for the main app and every nested signed bundle.
Require exact intended keys and values per bundle, as well as the matching profile's permitted subset; profile allowance alone is insufficient.
Permit only documented tool-required transformations approved in the signing plan; block a pass if actual sets or per-bundle mapping cannot be checked.
Record signed path, size, SHA256, tool/signer versions, nonsecret identity/profile identifiers, and each check result.
No independently verified Linux verifier for CodeDirectory hashes, CMS, sealed resources, and all nested signatures is established here.
zsign `-C` reports certificate information/OCSP, not application signature integrity.
Signer success, CMS decode, or an `LC_CODE_SIGNATURE` does not prove all hashes or nested signatures valid.
Investigate an approved capable verifier if required; macOS `codesign` verification is an option only within explicitly approved scope.
Otherwise report `SignedIPAProduced`, static checks and `StaticChecksPassed` only when all applicable static checks passed, and cryptographic verification unavailable.
Do not report `SignatureVerified` or `InstallabilityProven` without relevant evidence; retain a valid signed artifact when device access is pending.

## 9. Authorized device installation and launch

Run device operations only when the user explicitly authorizes installation and launch on the intended target.
Skill creation and signed-artifact production do not grant that authorization.
When authorization or access is missing, report `DevicePending` and provide the adapted commands below as next steps, not executed results.
Ask the human to connect the device by USB, unlock it, and complete Trust and passcode prompts when shown.
On iOS 16+, enable Settings > Privacy & Security > Developer Mode, restart, and confirm Turn On.
Developer Mode does not bypass signing or provisioning.
Require approved host/container USB and usbmuxd visibility; return a pending connection state rather than guess root mounts or passthrough changes.

The readiness examples use Debian 12 Bookworm `libimobiledevice-utils` `1.3.0-6` and the installation examples use `ideviceinstaller` `1.1.1-1`.
Use setup's actual executable paths and installed help/version; adapt other versions through verified documentation.

```sh
idevice_id --list
```
Enumerate visible USB devices and select only the explicitly authorized target covered by the profile.

```sh
idevicepair --udid 00008110-001234567890001E validate
```
Replace the example UDID consistently with the actual authorized device and retain successful pairing-validation evidence.

```sh
idevicepair --udid 00008110-001234567890001E pair
```
Run only if pairing is needed within the authorized workflow, with human Trust interaction; skip when validation already succeeded.

```sh
ideviceinstaller --udid 00008110-001234567890001E --list-apps
```
Record preinstall bundle/version state and this build's signed-artifact hash and intended version to distinguish an old installed copy.

```sh
ideviceinstaller --udid 00008110-001234567890001E --install /home/iosbuilder/ios-linux/output/ExampleApp-signed.ipa
```
Use Bookworm's option-style syntax and require exit zero plus the actual installation-completion response.

```sh
ideviceinstaller --udid 00008110-001234567890001E --list-apps
```
Require the intended bundle and version after this completed installation; an unchanged old listing alone is not a pass.

Newer upstream installers use subcommands such as `--udid UDID --notify-wait install IPA` and `list`; use them only if installed help confirms that interface.
The default `ideviceinstaller` route needs no Developer Services login.
xtool 1.22.2 `install` reads `AuthToken.saved`; supplied signing inputs or a valid pre-signed IPA alone do not satisfy that installer.
Only with an already approved valid xtool auth session may the alternative be used:

```sh
/home/iosbuilder/ios-linux/tools/xtool/squashfs-root/AppRun install --usb --udid 00008110-001234567890001E /home/iosbuilder/ios-linux/output/ExampleApp-signed.ipa
```
Require the same installation-completion and postinstall bundle/version evidence as the default route.

```sh
/home/iosbuilder/ios-linux/tools/xtool/squashfs-root/AppRun launch --usb --udid 00008110-001234567890001E com.example.exampleapp
```
Launch the actual installed bundle and require a successful debugserver launch response with PID/status where available, not CLI help or an operator conclusion.

xtool launch does not read `AuthToken.saved`, but it requires compatible device debug services and the installed bundle.
If enumeration needs xtool, its verified interface is `AppRun devices --usb --no-wait`; use the actual AppRun path and retain the explicit target selection.
Unsupported device OS, DDI, or debugservice errors are target-compatibility blockers; research official sources within approved scope rather than claim universal modern-iOS support.
Record target UDID, prior state, artifact identity, installation completion, postinstall bundle/version, launch response, and remaining limits.
Use `InstalledAndLaunched` only with both observable results; platform acceptance does not prove every runtime feature or App Store acceptance.
Report signed-artifact state separately from `DevicePending` or a device blocker, with exact manual next steps when pending.

## Sources

- zsign release: https://github.com/zhlynn/zsign/releases/tag/v1.1.3
- zsign options/nested signing: https://raw.githubusercontent.com/zhlynn/zsign/v1.1.3/src/zsign.cpp
- zsign key/certificate handling: https://raw.githubusercontent.com/zhlynn/zsign/v1.1.3/src/openssl.cpp
- OpenSSL 3 extraction: https://docs.openssl.org/3.0/man1/openssl-pkcs12/
- OpenSSL password-file input: https://docs.openssl.org/3.0/man1/openssl-passphrase-options/
- Bookworm installer: https://manpages.debian.org/bookworm/ideviceinstaller/ideviceinstaller.1.en.html
- Bookworm enumeration: https://manpages.debian.org/bookworm/libimobiledevice-utils/idevice_id.1.en.html
- Bookworm pairing: https://manpages.debian.org/bookworm/libimobiledevice-utils/idevicepair.1.en.html
- Apple development profiles: https://developer.apple.com/help/account/provisioning-profiles/create-a-development-provisioning-profile/
- Apple profile structure: https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles
- Apple Developer Mode: https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device
- Apple Trust interaction: https://support.apple.com/en-us/109054
- xtool 1.22.2 source (`InstallCommand`, `LaunchCommand`, `DevCommand`): https://github.com/xtool-org/xtool/tree/1.22.2
