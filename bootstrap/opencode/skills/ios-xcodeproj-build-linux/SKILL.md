---
name: ios-xcodeproj-build-linux
description: Build a plain Xcode or XcodeGen iOS app (Swift with Objective-C, no Kotlin Multiplatform) on Linux into a development-signed Debug IPA and install it on a USB-connected iPhone, without launching it. Use to compile, sign, or install such an app from Linux. For a KMP project, use kmp-ios-build-linux.
---

# ios-xcodeproj-build-linux

## Scope

The goal is a development-signed **Debug** IPA, **installed** on one authorized iPhone. Launch is out of scope.

This skill adapts `kmp-ios-build-linux` to an app that Xcode builds from an `.xcodeproj`. That skill stays the single source for the outcome names, the signing gates, secret handling and the zsign route. `kmp-ios-setup-linux` stays the source for the Swift toolchain, the Darwin SDK, zsign and the container device route. [The build reference](references/build.md) holds every command and every fact about this project type.

Why this route: SwiftPM cannot build one target that mixes Swift and Objective-C with a bridging header, and xtool 2.0.0-beta.1 builds `.xcodeproj` files on Linux through Swift Build. Linux has no `ibtool` and no `actool`, so storyboards, xibs and asset catalogs are not compiled. The installed app can crash at launch. That is a recorded **limit**, because launch is out of scope.

An app that loads a storyboard at launch (`UIMainStoryboardFile`, or `UISceneStoryboardFile` in `UIApplicationSceneManifest`) always crashes at launch from this build: `SIGABRT` in `+[UIStoryboard storyboardWithName:bundle:]`. Before you start, count the `.storyboard` and `.xib` files and read those `Info.plist` keys. Tell the user that a runnable app needs a Mac (a full Xcode build, or `ibtool` and `actool` output merged into the bundle). Skipping the launch storyboard only moves the crash to the next screen that loads one.

## Guardrails

- **Clean environment.** Run every build, generator and inspection command under `env -i` with only the variables in [reference section 1.1](references/build.md#11-clean-environment). A failing tool can print its whole environment, and the agent's environment holds credentials. If a credential still reaches output, follow the leak rules in `kmp-ios-build-linux/references/build.md` (secret placement and leak handling).
- **Gate copy only.** Every patch, generated file and build output goes inside the gate folder. The repository stays unchanged.
- **Approvals.** Get approval for the build plan before the first download or build. Signing approval and key-handling security approval are separate gates. Installation needs explicit authorization for the named iPhone; it covers install only.

## One-liners

Find every wall in one pass, not one wall per build. After step 2, write `<GATE>/gate.env` ([reference section 1.2](references/build.md#12-gate-settings-and-one-liners)), then use only these two commands:

```sh
bash ~/.config/opencode/skills/ios-xcodeproj-build-linux/scripts/preflight.sh <GATE>
```

```sh
bash ~/.config/opencode/skills/ios-xcodeproj-build-linux/scripts/build.sh <GATE> <n>
```

- Run the preflight before each build. Fix every `FAIL` it lists in one round, then run it again. Start a build only when it prints `RESULT: 0 failed`.
- `build.sh` prints the exit code, the time, the peak load, the task counts and each distinct error with its file. Read that summary; open the full log only for an error the summary does not explain.
- When a build fails on a new kind of problem, add a check for it to `preflight.sh`, so the next run finds it before the build.

## Workflow

### 0. Record the goal and the inputs

Record the repository, the revision, the scheme and its run configuration, the bundle ID, the product name and the entitlements file of that configuration ([reference section 6](references/build.md#6-sign) shows where each value comes from). List each capability in the entitlements file.

Ask for the signing inputs as `kmp-ios-build-linux` step 0 describes. Check the profile type and its capabilities now, from its public metadata, before the long build ([reference section 6](references/build.md#6-sign)).

Done when every value is recorded and the profile allows every listed capability, or a missing one is reported as `Blocked`.

### 1. Check readiness

Done when every row of [the readiness table](references/build.md#1-tool-readiness) has an absolute path, a version and a trust record. Route a missing toolchain, SDK, zsign or device route to `kmp-ios-setup-linux`.

### 2. Export the source into a fresh gate

Done when the exported file count equals the tracked file count of the revision and every needed untracked file is listed with its SHA256 ([reference section 2](references/build.md#2-gate-and-source-export)).

### 3. Apply the Linux overlay, then generate the project

The **Linux overlay** is one reviewed patch to the gate copy. It removes or replaces each build step and each compile-time code generator that needs a macOS-only tool, and it stamps a unique build number ([reference section 3](references/build.md#3-linux-overlay-and-project-generation)).

Done when the overlay is applied, its SHA256 is recorded, every generated stand-in file is listed, `xcodegen generate` has made the `.xcodeproj`, and each removed step is listed as a limit.

### 4. Build Debug for the device

Run the build command in [reference section 4](references/build.md#4-build). Once the first attempt has resolved the packages, apply the codemods in `scripts/codemods/` to the gate copy, with a reviewed dry run first (reference section 4). Fix a pattern that repeats with a codemod, and a one-off problem in the overlay. Stop after the same failure three times, or after ten overlay changes without a new compile stage reached.

Done when the build exits 0 and the `.app` at the recorded output path contains an ARM64 iOS executable.

### 5. Package and inspect the unsigned IPA

Done as `UnsignedIntermediate` when the checks in [reference section 5](references/build.md#5-package-and-inspect) pass and the IPA path, size, SHA256 and limits are recorded.

### 6. Sign

Done as `SignedIPAProduced` when the guarded zsign route of `kmp-ios-build-linux/references/build.md` section 8 has run with the entitlements file from [reference section 6](references/build.md#6-sign), and the signed-artifact checks listed there pass.

### 7. Install

Done as `Installed` when the commands in [reference section 7](references/build.md#7-install) report `Install: Complete` and the app list on the iPhone shows this run's build number. Without authorization or a visible device, report `DevicePending` with the exact next steps.

## Final report

Report the outcome, the artifact path, size and SHA256, the revision, the gate, the overlay SHA256, the tool versions, the signing identifiers without secrets, the UDID and install evidence, and every limit. Update [the run evidence](references/build.md#8-run-evidence) after each run.
