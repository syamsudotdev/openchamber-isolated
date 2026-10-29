---
name: kmp-ios-setup-linux
description: Debian-first setup for an existing KMP project's Linux-to-iOS toolchain. Use when dependencies, Swift, xtool, the Apple SDK, qualified Linux Kotlin/Native support, or signed-IPA and device-install readiness are missing. Research and adapt other distributions through official sources before installation.
---

# Set up KMP iOS tools on Linux

Prepare tools for an existing Kotlin Multiplatform (KMP) project and its real Swift/iOS host.
Use Debian first. End at a verified setup handoff, not an application build.
Default to a signed IPA artifact goal. Use an unsigned fallback only when the user explicitly narrows the goal.

## Prerequisites

- Existing KMP source and Swift/iOS host.
- Permission for the specific host changes.
- Authorized Apple SDK input and applicable license acceptance.
- A qualified Linux Kotlin/Native port, or approval to investigate one.

## 1. Inspect the host and project

Record the distribution, release, CPU architecture, libc, and package manager.
Resolve the actual workspace, project, and tool directories. Example paths are not existing accounts.
Inspect the Gradle wrapper, version catalog, plugin declarations, and native module configuration.
Record required JDK, Gradle, Kotlin, Kotlin Gradle Plugin, and other compiler/plugin versions.
Identify the `iosArm64` framework module, task, name, static/dynamic mode, and exported public API.
Inspect the real Swift host, entry point, deployment minimum, permissions, sources, and resources.
Include generated resources, fonts, licenses, native libraries, headers, and cinterop requirements.
Require an Android SDK only when project configuration needs it.

**Complete when:** the host facts and project constraints have source evidence and resolved paths.

## 2. Select a compatible setup recipe

Read [the Debian 12 reference](references/debian12.md) for fresh Debian 12 x86_64 setup or its pinned baseline.
Select tool versions by project compatibility, not by an assumption that these pins are universal or latest.
For another Debian release, verify package names, runtime libraries, and binary compatibility first.
For another distribution, research official distribution, Swift, and xtool documentation yourself.
Find equivalent packages, supported binaries, a compatible toolset, and SDK discovery paths.
Verify release, architecture, and libc support before proposing installation.
Do not run Debian package commands outside Debian or request a distribution-specific recipe from the user.
If official artifacts do not support the host, report the researched blocker; do not promise musl or architecture compatibility.
Offer a Debian container alternative only when the authorized scope includes it.
Present the specific changes and wait for approval under the host's approval policy before execution.

**Complete when:** a supported recipe and compatible versions are selected, and changes are approved.

## 3. Prepare host tools

Install only the approved dependencies and project-required JDK.
Authenticate Swift before extraction and check xtool against its official release digest.
Retain Swift's complete `usr` tree and select its real `usr/bin` tools.
Prepare xtool, `zip`, and a Mach-O inspector; record absolute executable paths and versions.
Use process-local environment settings when required and record their resolved literal values.

**Complete when:** authenticated tools execute with the required versions and runtime libraries.

## 4. Install and verify the Apple SDK

Locate an authorized Xcode XIP. Request the user's Apple-account download or permissions only when needed.
Record the input hash and provenance, then install the slim SDK with the selected xtool.
Use actual `sdk status` output and `swift sdk list` as installation and discovery evidence.
Resolve the device SDK from `swift-sdk.json`; verify platform and version in its `SDKSettings.json`.
Check `toolset.json` against actual paths, including executable linker, librarian, and `toolset/bin/dsymutil`.
Check the SDK bundle's root `OpenAppleMacrosServer` and record auxiliary versions and provenance.

**Complete when:** the same SDK is installed and discoverable, and device metadata and auxiliary tools are verified.

## 5. Qualify Linux Kotlin/Native capability

Swift SDK installation alone does not enable KMP Apple final binaries on stock Linux.
This skill supplies no compiler patch or qualified port bundle.
Inspect an existing port for version-matched iOS platform KLIBs and target runtime resources.
Verify compiler and Kotlin Gradle Plugin host enablement across classloaders and task dependencies.
Preserve Linux host identity, real dependency variants, compiler/plugin inputs, and resource generation.
Verify Linux LLVM AArch64 support, toolchain overrides, Xcode/sysroot resolution, and native cinterop.
Check Darwin archive handling, including baseline ARM64 selection from fat archives and flattened archive members.
If no qualified port exists, research available implementations and propose a bounded port experiment before implementation.
Do not replace investigation with an automatic request for a prebuilt framework.
After approval, qualify only a minimal device ARM64 framework probe with a real exported public Kotlin method.
Verify retained compiled implementation, headers, module map, device platform, and native SDK bridge where applicable.
Reuse unchanged qualification evidence when its compiler, plugins, port, and native inputs still match.
Keep the probe separate from the actual application; leave application compilation and packaging to the build skill.

**Complete when:** matching framework capability has recorded evidence, or an explicit blocker prevents readiness.

## 6. Qualify signing and device readiness

Read [signing and device readiness](references/debian12.md#6-prepare-signing-and-device-readiness) for signer constraints and the Debian package baseline.
Inspect the selected signer's actual version, help, and credential-input capabilities before proposing a signing route.
Qualify a developer certificate and private key (`.p12` or a supported compatible identity), a matching `.mobileprovision`, and an approved secure signing route.
Record paths and safe identifiers only for inputs already provided. Keep private keys and passwords out of chat, command arguments, history, and logs.
Treat private-key handling as explicit security scope; restrictive file permissions alone do not approve an unencrypted identity.
For the protected-file OpenSSL route, qualify explicit approval, private temporary staging, and cleanup safeguards from the reference; leave decryption and signing commands to the build skill.
If credentials or a safe signing route are missing, record a signed-build blocker rather than unsigned success.
Leave profile App ID, team, expiry, entitlements, target UDID coverage, and certificate/key matching to the build skill's validation gate.
Record installer and launch tools, actual versions/help, target-UDID selection, and authentication prerequisites separately.
Record an approved independent signature verifier or **Unavailable**. Keep cryptographic verification limits separate from static checks and device acceptance.
Obtain approval before root/package changes, USB passthrough, or device pairing under the host policy.
Record device visibility and pairing only when read-only enumeration is authorized; otherwise mark them unavailable.
Ask the human to connect and unlock the target, accept Trust with the passcode, and enable Developer Mode when required.
Give the concrete human steps in the reference and wait for confirmation. Developer Mode does not permit unsigned applications.
Require an explicit target UDID before any later device mutation; never select all devices.
Keep setup limited to capability checks. Leave application build, signing, installation, and launch to the build skill.

**Complete when:** signer capability, credential availability, and the security route are qualified or explicitly blocked; device prerequisites have evidence or an **Install pending** status.

## 7. Hand off the setup

Report **Ready for signed build** only when project, SDK, framework capability, signer capability, credentials, and the security route pass.
Otherwise report **Partial readiness** and identify the failed gate and next approved action.
Use **TOOLS_READY** only for qualified tools; it does not establish credential or security-route readiness for the signed goal.
Missing USB access does not block creation of a signed file. Report **Install pending** until the authorized target is visible and paired.
Include this handoff:

- Host distribution/release, architecture, libc, and actual workspace/project directories.
- Project JDK/Gradle/Kotlin/plugin versions; framework module/task/name/mode; host paths; deployment and resource requirements.
- Absolute Swift, `swiftc`, xtool, `zip`, and inspector paths, versions, and trust-verification results.
- Actual SDK bundle, device SDK, and toolset paths; SDK metadata; auxiliary versions and provenance.
- Qualified Linux port version/configuration and probe evidence, or the remaining blocker.
- Required process-local `PATH`, `SWIFT_EXEC`, and XDG settings, if used, with resolved literal values.
- Artifact goal (`signed IPA` by default); approved signer name, absolute executable path, version, provenance/trust checks, and secret-input mode without secret values.
- Already-provided identity/profile paths and safe identifiers or hashes; credential blockers and required private-key security approvals.
- Installer/launch paths, versions, target-selection syntax, and authentication prerequisites; authorized operations and pending approvals.
- Explicit target UDID if provided; USB/usbmuxd visibility, container access, pairing, and Developer Mode evidence or pending status.
- Approved independent signature verifier and capability evidence, or **Unavailable** with the cryptographic verification limit and any required follow-up.
- Commands, results, reused evidence, and remaining limits.

When the user or main agent requests the application build after this handoff, load `kmp-ios-build-linux`.
Setup does not create an application wrapper or IPA and does not claim application readiness on a device.
