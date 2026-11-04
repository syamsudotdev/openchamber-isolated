---
name: kmp-ios-build-linux
description: Build a signed iOS IPA from a real Kotlin Multiplatform framework and its existing Swift host on prepared Linux. Use for framework builds, rebuilds of a new revision, SwiftPM/xtool packaging, signing, and explicitly authorized device installation, reinstallation, and launch. Debian-first; requires a qualified Linux Kotlin/Native port or a framework built on supported macOS.
---

## Scope and prerequisites

The default goal is a signed development IPA for the intended device.
The unsigned IPA is an intermediate, unless the user explicitly narrows the goal to unsigned output.
Installation and launch require explicit user authorization; invoking or editing this skill does not grant it.
Signing approval and explicit security approval for private-key handling are separate gates.

Use the existing KMP project, real Swift/iOS host, and completed `kmp-ios-setup-linux` handoff.
Obtain approval for concrete source changes and build actions before execution.
Use the project's JDK, Gradle, Kotlin, plugin versions, authorized Apple SDK, and native dependencies.
This workflow is Debian-first. For another distribution, inspect its OS, release, architecture, and libc.
Research official compatibility sources yourself and adapt; do not ask the human for a distribution recipe.
Route missing tools, SDK installation, or stale qualification to `kmp-ios-setup-linux`.

Stock Kotlin/Native on Linux does not support Apple final-binary targets.
A Swift SDK alone does not qualify a Linux Kotlin/Native port; these skills supply no portable compiler patch bundle.
Require a qualified version-matched port or an explicitly approved supported-macOS framework build.
Preserve the real Kotlin build; return a blocker rather than a dummy framework or skipped task.

Read [the build reference](references/build.md) before executing this workflow.
It supplies packaging, protected signing, verification limits, and version-specific installation commands.
Replace its literal examples with inspected project and setup values before use.

## Workflow

### 0. Request signing inputs for the default goal

Request local paths and nonsecret identifiers for:
- An Apple Development identity with its private key, usually `.p12`, or a supported existing identity.
- A matching `.mobileprovision` for each app and extension.
- Intended per-bundle entitlement sources/files, or reviewed resolved entitlement files.
- The actual bundle IDs, team ID, and intended device UDID or authorized target to enumerate.
- A protected secret-input mechanism; request a password-file path, never password contents in chat.

A `.cer` without its private key is insufficient.
Check each supplied profile's type at intake from its public metadata ([reference section 7](references/build.md#7-validate-signing-inputs)), before requesting the password.
A USB install needs a development profile that lists the target UDID and allows `get-task-allow: true`, signed by an `Apple Development:` or legacy `iPhone Developer:` certificate.
An App Store or TestFlight profile (no devices, `beta-reports-active`) with an `Apple Distribution:` certificate is the CI identity; return it with the development-profile steps.
Place, read, and check every secret under the mandatory [secret placement and leak handling](references/build.md#secret-placement-and-leak-handling) rules; read the password only with `-passin file:`.
If a secret appears or may have appeared in the conversation, a command line, a log, or a commit, stop and warn the user without repeating the value.
Missing signing inputs block the default goal; do not offer an automatic unsigned fallback or claim unsigned success.
Record any explicit user decision to narrow the goal to unsigned output.
Record signing approval and the separate approved key-handling method before signing.
Finish when the goal, required inputs, target, and authorization boundaries are recorded, or report `Blocked`.

### 1. Check project state and setup readiness

Record checkout revision and dirty state without changing unrelated files.
Inspect the real framework module/task/name/static mode, Swift entry point, exported Kotlin API, and deployment minimum.
Inspect native dependencies, cinterop, Compose compiler inputs, and generated-resource tasks and loaders.
Require Android SDK setup only when project configuration needs it.
Compare setup's handoff with the current host and project. Require:
- Distribution, release, architecture, libc, project path, and required JDK/Gradle/Kotlin/plugin versions.
- Real framework and host paths, deployment/native/resource constraints, and qualified port integration/probe evidence.
- Absolute Swift, swiftc, xtool, ZIP and Mach-O inspector paths, versions, and trust evidence.
- Actual SDK bundle/device SDK/toolset paths and auxiliary versions.
- Literal process `PATH`, `SWIFT_EXEC`, and XDG settings when used.
- Verified signer path/version/provenance, supported secret mode, profile paths, and key-handling constraints.
- Device connection visibility, installer path/version/help, pairing/auth readiness, and verifier capability limits.

For a rebuild, export the new revision into a fresh gate directory with `git archive`.
Before the first task, repoint every scratch root, init script, output guard, and log path to that gate; prior gates are read-only evidence ([reference: rebuild a new revision](references/build.md#rebuild-a-new-revision)).
Finish when all required values match current state; route readiness gaps to setup before affected actions.

### 2. Build the real device framework

Run the actual Gradle `iosArm64` Release framework task after port qualification and integration.
Retain logs proving execution rather than `SKIPPED`, nonempty iOS dependency variants, and actual compiler/plugin/cinterop inputs.
Run the project's resource generation and sync tasks.
Finish with compiled Kotlin implementations, framework, headers, module map, resources, native inputs, and provenance.

### 3. Stage the static device framework

Require a static archive with device ARM64 members, compatible deployment minimum, implementation, and matching module name.
Use the port's qualified native-archive selection and flattening behavior; nested archives are not a replacement.
Stage the actual framework as a device-only XCFramework and retain matching source/staged hashes.
Stage required generated resources, fonts, licenses, headers, and exported code.
Finish when the staged slice matches source output, native ABI, and deployment requirements.
Route dynamic frameworks to a separately approved embedding/runpath/dependency/signing plan.

### 4. Configure the existing host

Preserve the real Swift application entry point, behavior, and exported Kotlin API calls.
Reuse packaging configuration or add an approved SwiftPM wrapper with the real XCFramework `binaryTarget` and host library product.
Preserve host dependencies and producer-required linker settings from actual documentation or binary metadata.
Resolve Xcode macros to literal values while preserving plist policy, identifiers, deployment minimum, permissions, and capabilities.
Map resources to the actual Kotlin/host loader; use main-bundle `compose-resources` only when required.
Account for the host's app icon: Linux has no `actool`, so xtool packages no asset catalog and the app shows a blank icon. Convert the `AppIcon` set into loose PNGs with `CFBundleIcons` before signing ([reference: app icon without actool](references/build.md#app-icon-without-actool)).
Finish when host behavior, metadata, dependencies, resource destinations, and the app icon are accounted for without a dummy app.

### 5. Produce and inspect the unsigned intermediate

Use setup's real Swift distribution, SDK/toolset paths, and process settings.
Include the SDK toolset in `PATH` for `dsymutil` and real `swiftc` in `SWIFT_EXEC` when needed.
Run xtool Release packaging with `--ipa` and omit `--sign`.
Require exit zero, xtool's completion message, and a nonempty IPA.
Inspect ZIP integrity/paths, XML or binary plists, device ARM64 platform, `MH_EXECUTE`, minimum OS, and entry point.
Compare packaged resource hashes with independently recorded source manifests at their actual destinations.
Retain link provenance and prove compiled Kotlin/native implementation linkage with a link map or capable symbol inspection.
For a rebuild, also prove revision currency: a string added in the new revision is present in the executable, and one it removed is absent. A fast cached xtool build alone does not prove it.
Confirm the static framework is not an embedded dynamic dependency.
Require the icon PNGs and `CFBundleIcons` in the packaged app.
Record host parts still not packaged, such as other asset catalog content and privacy manifests, as known limits.
Finish as `UnsignedIntermediate`; this is not completion of the default signed goal.

### 6. Validate inputs and sign

Use [reference sections 7–8](references/build.md#7-validate-signing-inputs) before any key operation.
Require certificate/key match, valid Apple Development identity, and current profiles with recorded authentication or trusted provenance.
Match the `.p12` certificate fingerprint against the profile's `DeveloperCertificates` with a certificate-only read before any key extraction.
Check bundle/App ID, team, target UDID, profile identity certificate, and permitted application entitlements for every app/extension.
Require approved resolved intended entitlements from actual app needs and required identity keys, with actual App ID/team values permitted by the matching profile.
Review actual nested frameworks, dylibs, and `.appex` bundles and their signing order/profile needs.
Pass the reviewed entitlement file through zsign `-e`; block the single-command route when nested bundles need distinct entitlements until per-bundle mapping and tool behavior are verified.
xtool `--sign` uses xtool auth, not supplied `.p12` import; use setup's verified community zsign route for supplied inputs.
zsign's password option exposes the password in argv; the documented protected route uses OpenSSL 3 password-file input and temporary PEM files.
Require explicit security approval, fresh private staging, and one controlled extraction/signing operation with guarded cleanup on success, failure, and interruption.
Use the reference's tested guarded script: staging on a memory-backed tmpfs where available, a trap-owned cleanup, and a key/certificate public-key match before signing.
If that lifetime cannot be guaranteed, stop for an approved secret-capable signer or human-managed signing.
Finish with signer completion, a nonempty signed IPA, and verified removal of only the created temporary key/certificate files.
Record `SignedIPAProduced` only with the static evidence and limits in the next step.

### 7. Inspect the signed artifact and report verification limits

Repeat archive, metadata, platform, resource, and linkage checks on the signed artifact, accounting for expected signing changes.
Check embedded profiles against validated inputs and actual main/nested signed entitlement sets against each exact intended set and profile allowance; the reference parses the entitlement blob from `LC_CODE_SIGNATURE`.
Allow only documented tool-required entitlement transformations approved in the signing plan; profile permission alone is insufficient.
Record final path, size, SHA256, revision/dirty state, tool/SDK/port/signer versions, and each check result.
No independently verified Linux verifier for all CodeDirectory/CMS/resource/nested signatures is established by this workflow.
Signer exit, `LC_CODE_SIGNATURE`, CMS decoding, and zsign `-C` do not prove signature integrity.
Investigate an approved capable verifier when required; use macOS `codesign` verification only if that scope is approved.
Report cryptographic verification as unavailable unless actual capable-verifier evidence exists.
`SignedIPAProduced` plus `StaticChecksPassed` does not mean `SignatureVerified` or `InstallabilityProven`.
Finish the signed-output goal with explicit limits; preserve the artifact if device access is unavailable.

### 8. Install and launch only when authorized

Use [reference section 9](references/build.md#9-authorized-device-installation-and-launch) for literal commands and evidence requirements.
If authorization or device readiness is missing, report `DevicePending` with exact manual next steps and adapted commands.
Have the human connect and unlock the device, complete Trust/passcode prompts, and enable Developer Mode on iOS 16+.
Require approved USB/usbmuxd visibility; return a connection blocker instead of guessing privileged container changes.
In a container, use setup's usbmuxd relay route and verify it from inside the running container before device steps.
Enumerate devices and use the actual authorized, profile-covered UDID; never select all devices or an ambiguous target.
Read Developer Mode state from the device instead of asking the human to recheck it.
Validate existing pairing; pair only when needed within the authorized workflow.
Use installed-version-compatible `ideviceinstaller` by default; it needs no xtool Developer Services login.
xtool install is an alternative only with an already approved valid xtool auth session; a pre-signed IPA alone is insufficient.
Record preinstall app state and current build identity before installation.
If the same bundle ID is already installed, such as a TestFlight or App Store build, report that the install replaces it and get confirmation first.
Require installation completion and app-list bundle/version evidence tied to this build, not an old installed copy.
Finish as `Installed` on that evidence.
For a reinstall request, reuse the signed IPA when the source revision and artifact hash are unchanged; rebuild only after a revision change.
Launch the actual installed bundle with xtool and require a successful debugserver response, PID or status where available.
On iOS 17 and later, debugserver launch needs Apple's developer tunnel, which this workflow has no verified Linux route to, and a developer disk image mount changes the device; mounting one needs its own approval.
When launch from Linux is unavailable, ask the human to open the app and report `Installed` with launch pending.
Report unsupported device/debugservice/DDI compatibility as a blocker and research official sources within approved scope.
Finish as `InstalledAndLaunched` only with observable installation and launch evidence; this does not prove every runtime feature.

## Final report

Report artifact identity, signing identity/profile identifiers without secrets, provenance, static checks, verifier limits, and authorization state.
Use distinct outcomes: `Blocked`, `UnsignedIntermediate`, `SignedIPAProduced`, `DevicePending`, `Installed`, and `InstalledAndLaunched`.
A missing signing prerequisite blocks the default goal even if an unsigned intermediate exists.
Report signed-artifact and device outcomes separately; `DevicePending` is not an installation pass.
Include exact authorized next steps when pending; never claim App Store acceptance or runtime coverage from archive checks.
