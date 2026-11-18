# Xcode-project iOS app: Linux Debug build, signing and install

Placeholders. Inspect each value in the project and the host:
- `<GATE>`: a new, empty folder for one run, for example `/workspace/ios-linux-<app>/gate1`.
- `<TC>`: the toolchain root from `kmp-ios-setup-linux` (Swift distribution, `deps/`, Darwin SDK).
- `<XTOOL>`: `<GATE>/tools/xtool-2/squashfs-root/AppRun`.
- `<REPO>`, `<REV>`, `<SCHEME>`, `<CONFIG>`, `<BUNDLE_ID>`, `<PRODUCT_NAME>`, `<ENTS>`, `<TEAM_ID>`, `<UDID>`.

`<PRODUCT_NAME>` can contain spaces and dots (for example `My App DEV`). Quote every path that contains it.
Each shell block is one command. Stop on failure. Long commands write their full output to `<GATE>/logs/` and print only filtered lines.

## 1. Tool readiness

| Tool | Pinned version | Source and trust record | Check |
|---|---|---|---|
| Swift toolchain | from setup (6.4.1 on the last run) | `kmp-ios-setup-linux` handoff | `swift --version` |
| Darwin Swift SDK | made by the pinned xtool | `<XTOOL> sdk install <Xcode.xip> --slim` with `HOME=<GATE>/home`; record the `.xip` SHA256. An SDK made by xtool 1.x is rejected by 2.0 ("Darwin SDK is out of date"), and a slim SDK cannot be updated in place. | `<XTOOL> sdk status` |
| xtool | **2.0.0-beta.1** (prerelease) | `https://github.com/xtool-org/xtool/releases/download/2.0.0-beta.1/xtool-x86_64.AppImage`, 67,799,544 bytes, SHA256 `0361a2570e46a7734e8bafa71715ca8a72cf218e0e7a945eef0e4d71733b19e3` (GitHub release API, 2026-11-18). Extract with `--appimage-extract`; no FUSE. | `<XTOOL> --version` |
| XcodeGen | **2.47.0**, built from source | tag `2.47.0`, commit `8f1f80bb912df5fa1c732f96dadbdff14005056e`. The release zips are macOS binaries. Build with `swift build -c release --product xcodegen --build-system native`: the default Swift Build system drops `LD_LIBRARY_PATH` in its link step, and `swiftc` then cannot load `libncurses.so.6` from the setup's `deps/` (2026-11-18). | `xcodegen --version` |
| dsymutil | Darwin SDK toolset | `<SDK>/toolset/bin/dsymutil` | `dsymutil --version` |
| llvm-objdump | Swift distribution | `<TC>/swift-distribution/.../usr/bin/llvm-objdump` | `--version` |
| libimobiledevice-utils, ideviceinstaller, zip, rsync | the trixie package versions in the signed Debian index on the day | `.deb` files checked against the signed index, extracted without install scripts, as `kmp-ios-setup-linux` does | `--help` or `--version` |
| zsign | v1.1.3 | `kmp-ios-setup-linux` handoff | `zsign -v` |
| openssl, patch, unzip, uv | host packages | record `command -v` and version | `--version` |

xtool 2.0 build syntax (from `dev build --help`, 2026-11-18): `xtool dev build [-c debug|release] [--scheme <scheme>] [--sign] [--ipa] [--triple <triple>]`. The default triple is `arm64-apple-ios`. Without `--sign` the build is unsigned.

### 1.1 Clean environment

Run each command through this prefix. Add only variables that a command needs, and record them.

```sh
env -i HOME=<GATE>/home CFFIXED_USER_HOME=<GATE>/home TMPDIR=<GATE>/tmp LANG=C.UTF-8 USER=<user> LOGNAME=<user> PATH=<TC>/swift-distribution/<swift>/usr/bin:<SDK>/toolset/bin:<GATE>/deps/usr/bin:/usr/bin:/bin LD_LIBRARY_PATH=<TC>/deps/lib/x86_64-linux-gnu:<TC>/deps/usr/lib/x86_64-linux-gnu:<GATE>/deps/usr/lib/x86_64-linux-gnu <command>
```

- Do not source a setup `env.sh` that sets `SWIFT_EXEC` to a wrapper for host builds: SwiftPM then searched for `swiftc` in the package folder and failed (2026-11-18).
- `USER` and `LOGNAME` are required: XcodeGen stops with `Couldn't find current username` without them. `CFFIXED_USER_HOME` makes Foundation use the gate `HOME`.
- xtool reads its Darwin SDK and any saved login under `HOME`. With `HOME=<GATE>/home`, the gate's own SDK is used and no login token is present. A login token is a secret: never print that folder.
- The device commands need `USBMUXD_SOCKET_ADDRESS` from the device route.

### 1.2 Gate settings and one-liners

`scripts/preflight.sh` and `scripts/build.sh` read `<GATE>/gate.env`. It holds paths and names only, never a secret:

```sh
TC=<toolchain root>
SWIFT_BIN=<TC>/swift-distribution/<swift>/usr/bin
XTOOL=<GATE>/tools/xtool-2/squashfs-root/AppRun
XCODEGEN=<path to the built xcodegen>
SCHEME=<scheme>
CONFIG=debug
RUN_USER=<user>
APP_SOURCES=<app source folder inside the export, for example MyApp>
DEVTOOLS=<folder with bin/idevice_id>          # optional, install step
USBMUXD_SOCKET=<device relay socket>           # optional, install step
```

The stand-ins are installed into `<GATE>/stub-bin/` (`actool`, `ibtool`, `ld`, `lipo`, `asset_symbols.py`); the preflight fails when they differ from the skill's copies.

The preflight checks, in one run of about 1 second: swift, xtool 2.x, the Darwin SDK (present and accepted by this xtool), XcodeGen, `dsymutil`, `zip`, `rsync`, the stand-ins, the applied overlay, a project generated after the last `project.yml` change, macOS-only calls left in `project.yml`, `@State static` in compiled sources, stale empty symbol files, asset-symbol coverage of the app and of each local package, the device route and the free disk space.

## 2. Gate and source export

```sh
mkdir -p <GATE>/src <GATE>/logs <GATE>/out <GATE>/tools <GATE>/home <GATE>/tmp <GATE>/deps
```

```sh
git -C <REPO> archive <REV> | tar -x -C <GATE>/src
```

```sh
find <GATE>/src \( -type f -o -type l \) | wc -l
```

The count must equal `git -C <REPO> ls-tree -r --name-only <REV> | wc -l`, before any patch or generation.
`git archive` omits submodules, Git LFS objects and ignored files. Add each needed one and list it with its SHA256.
Check that generated sources are tracked, for example SwiftGen outputs. If one is not tracked and no Linux generator exists, report `Blocked`.

## 3. Linux overlay and project generation

Read `project.yml`, every file in its `include:` list, and every `configFiles` xcconfig of `<CONFIG>`. Classify every `preBuildScripts`, `postBuildScripts`, build rule and build setting of the app target:

| Class | Meaning | Action |
|---|---|---|
| Keeps working | Uses only tools that the gate provides (POSIX tools, `rsync`). | Keep. Confirm its result in the build log. |
| Skips itself | Guarded by a condition that is false in this build. | Keep. Confirm in the build log that the guarded branch did not run. |
| Depends on the Xcode build layout | Uses a DerivedData path such as `${BUILD_DIR%/Build/*}/SourcePackages/checkouts/...`. | Keep only if the build log shows the path exists under Swift Build; else replace the path in the overlay. |
| Needs macOS | Calls a macOS-only binary (`/usr/bin/codesign`, `xcrun`, a vendor macOS executable such as Firebase Crashlytics `run`). | Remove only that call. List it as a limit. A Homebrew `PATH` export alone is harmless; keep it. |
| Compile-time generator | A setting that makes Xcode run `actool` or `ibtool` to generate code, such as `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS: YES`. | Generate the same Swift symbols with a stand-in generator into the gate (section 3.1), or report `Blocked`. |

Also put these into the overlay. The last 5 items are walls that the first tested app build met (2026-11-18):
- Remove the app extension targets from the app target's `dependencies`, and remove scripts that only serve those extensions. The user decided to ship without extensions.
- Set `CURRENT_PROJECT_VERSION` of `<CONFIG>` to a unique value for this run, for example the UTC time `YYYYMMDDHHMM`. Step 7 checks this value on the iPhone.
- `CODE_SIGNING_ALLOWED: NO`: xtool's `codesign` emulation rejects the options that Swift Build passes. zsign signs in step 6.
- `STRIP_BITCODE_FROM_COPIED_FILES: NO`: the Darwin SDK toolset has no `bitcode_strip`. Bitcode is obsolete since Xcode 14.
- Add `-L<SDK>/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/iphoneos` to the app's `OTHER_LDFLAGS`. Swift Build links with the Linux Swift toolchain, which has no iOS back-deployment libraries (`libswiftCompatibility*.a`); prebuilt objects for older deployment targets need them.
- Delete each `.strings` resource file that a Swift package or the app copies as a translation. Swift Build on Linux decodes no `.strings` file, ASCII included. List the deleted files as a limit.
- A prebuilt static archive with "private external" `l<digits>` symbols (for example `libGoogleConversionTracking.a`) fails in `ld64.lld` as duplicate symbols. Replace it in the gate copy with its arm64 slice where those symbols are local: extract the slice, run `llvm-objcopy --wildcard --localize-symbol='l[0-9]*'` on each member, and archive the members again in the same order. Check that no private external `l` symbol remains and that the count of exported symbols is unchanged.

A replaced archive is binary content, which `patch` cannot apply. Make the overlay with `git diff --no-index --binary`, and apply it with `git apply`:

```sh
cd <GATE>/src && git apply -p1 <GATE>/linux-overlay.patch
```

```sh
sha256sum <GATE>/linux-overlay.patch
```

```sh
cd <GATE>/src && <xcodegen> generate --spec project.yml
```

Storyboards, xibs and asset catalogs stay in the project. Swift Build still plans `actool` and `ibtool` steps for them, in the app target and in every package with resources. Without the tools, planning fails with `<src>/actool is not an executable file` (2026-11-18, 433 errors, no file compiled). Put the stand-ins of `scripts/stub-tools/` first on `PATH` and set `STUB_TOOL_LOG=<GATE>/logs/stub-tools-<n>.log`:
- `actool` and `ibtool` answer the version and asset-tag queries and write empty outputs; `actool` also writes the asset symbols (section 3.1). `ibtool --link` takes a folder, and the dependency-info file needs a version record. List the result as a limit: no compiled nibs, storyboards or `Assets.car`.
- `ld`: clang on Linux calls the host GNU `ld`. The stand-in sends Apple links to the SDK's `ld64.lld` and translates `-<os>_version_min` to `-platform_version`; host links go to `/usr/bin/ld`.
- `lipo`: answers `-create`, `-info` and `-archs`, static archives included.

### 3.1 Asset symbol stand-in

Xcode's asset catalog compiler writes `GeneratedAssetSymbols.swift`: one `ColorResource` constant per color set and one `ImageResource` constant per image set in the target's catalogs, plus back-deployed `UIColor(resource:)` and `UIImage(resource:)` initializers when the deployment target is below iOS 17.

Swift Build calls `actool` once per target that has catalogs (the app and each package with resources), with `--generate-swift-asset-symbols <file>`. The `actool` stand-in runs `scripts/asset_symbols.py` on that target's catalogs and writes the file, so each target gets its own symbols, as in Xcode. Keep the asset symbol settings of the project unchanged, and add no symbol file to the overlay: a second copy defines `ImageResource` twice (build 18).

- Extensions: with `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS: YES`, Xcode also writes `UIColor`, `UIImage`, SwiftUI `Color` and `ShapeStyle` statics, so code can write `.blue500` without importing the module that owns the catalog. Swift Build passes `--generate-swift-asset-symbol-extensions` only as `NO`; a target with the setting on gets no option, so the stand-in treats a missing option as YES (build 19).
- Like Xcode, the generator skips an extension name that the SDK already declares on that type. It reads the UIKit class properties from the SDK headers (for example `addImage` makes `UIImage.add`) and uses a fixed list of SwiftUI system colors.
- Name rule: lower camel case, separators dropped, a trailing `Color` or `Image` dropped. Check the names against the call sites (`git grep -o 'resource: \.[A-Za-z0-9_]*'`). A call-site name that the generator does not make is a defect in the generator.
- Check: on the first tested app, the app target got 681 image and 208 color symbols, with 680 `UIImage` and 208 `UIColor` extensions (`UIImage.add` skipped), and every call-site name compiled.
- The initializers load by name at run time. Without `Assets.car` they find nothing. That is part of the asset catalog limit.

## 4. Build

```sh
bash ~/.config/opencode/skills/ios-xcodeproj-build-linux/scripts/build.sh <GATE> <n>
```

The script runs `<XTOOL> dev build -c <CONFIG> --scheme <SCHEME> --verbose` from `<GATE>/src` under the clean environment of section 1.1, with the stand-ins first on `PATH`.

- The first build fetches every Swift package and needs network access. Record its time in section 8; use it as the estimate for the next run.
- Print only `error:` lines and the last lines of the log. Stop after two progress intervals without new log lines.
- Separate three failure classes: a missing Linux tool, a project setting that the Linux build cannot honour, and a real compile error. Fix the first two only in the overlay. Report the third.
- Record the `.app` output path that xtool prints. The bundle is `<PRODUCT_NAME>.app`.
- Without `--verbose`, xtool prints only `Build failed`. Use `--verbose`, then read the `Kind.error` diagnostics and the failing `taskComplete ... Result.failed` lines.
- After you change a stand-in tool or the symbol generator, delete the outputs it made before (for example every `GeneratedAssetSymbols.swift` under `DerivedData/Intermediates.noindex`). Swift Build does not run a task again when only the tool changed.
- The container's process limit (`pids.max`, 1,024 here) can hang a build at the limit. `build.sh` stops a build after 300 seconds without new log output, and the preflight checks the headroom. This build peaked at about 430 processes.
- Known compiler difference: Swift 6.4.1 with the iOS 27 SwiftUI `@State` macro rejects `@State static var` ("static functions must not be declared mutating"). It occurs in SwiftUI preview code. Fix every occurrence with the codemod `scripts/codemods/state-static.yml` (ast-grep 0.51.3): it drops `@State`, keeps the value as `nonisolated(unsafe) static var`, and turns each `$name` use in the same struct into `.constant(name)`. Run it on the gate copy only, after the package checkouts exist (after the first build has resolved packages):
  1. Dry run, and save the list: `uvx --from ast-grep-cli==0.51.3 ast-grep scan --rule <skill>/scripts/codemods/state-static.yml --json=compact <GATE>/src > <GATE>/logs/codemod-state-static.json`.
  2. Review each match. Drop matches under sample, example or test folders, which are not compiled.
  3. Apply: the same command with `--update-all` instead of `--json=compact`.
  4. Run the preflight: it must report `codemod state-static: no matches`. List each changed file as a limit.
- Evidence (2026-11-18): the codemod made the 4 changes that the 2 hand fixes needed (Wormholy 2.1.1 `SearchBar.swift:68`, `:71`; `ClientView.swift:98`, `:104`), and 0 changes in a test file of instance `@State var` code.

## 5. Package and inspect

1. Copy `"<PRODUCT_NAME>.app"` into `<GATE>/out/Payload/`.
2. If `PlugIns/` exists, the overlay missed an extension dependency. Remove `PlugIns/`, record each `.appex` and its bundle ID, and fix the overlay for the next run.
3. Keep `Frameworks/`. zsign signs nested frameworks with the app identity.
4. xtool 2.0.0-beta.1 runs no shell-script build phase. Read each `preBuildScripts` and `postBuildScripts` entry that the overlay kept, and do in `Payload/` what its `<CONFIG>` branch puts into the bundle. Example: the tested app's Debug script copies `GoogleService-Info-Dev.plist` as `GoogleService-Info.plist`. List each script whose effect you did not reproduce as a limit.
5. Package from inside `<GATE>/out`: `zip -qr -X app-unsigned.ipa Payload`.

Apply these checks from `kmp-ios-build-linux/references/build.md` section 6: `unzip -t`, the entry list review, the extraction into a fresh folder, the plist parser check, the Mach-O header check with `llvm-objdump --macho --private-headers` (ARM64, `MH_EXECUTE`, platform iOS, `minos` = the deployment target), the size and the SHA256.
Do not apply its Kotlin linkage, static-framework, resource-manifest and required-icon checks.
Add these checks: the `Info.plist` has `<BUNDLE_ID>`, the run's `CURRENT_PROJECT_VERSION` as `CFBundleVersion`, and no unresolved `$(...)` macro. List what an Xcode build would add: `.storyboardc`, `.nib`, `Assets.car`, the app icon, `PrivacyInfo.xcprivacy`.

## 6. Sign

Values, in this order of precedence: the target's settings for `<CONFIG>` in `project.yml`, then the `include:` files, then the `configFiles` xcconfig for `<CONFIG>`.

Profile, checked in step 0 from public metadata (`kmp-ios-build-linux/references/build.md` section 7, intake): iOS App Development, App ID `<TEAM_ID>.<BUNDLE_ID>`, lists `<UDID>`, `get-task-allow` `true`, and allows each capability in `<ENTS>` (for example `aps-environment`, Sign in with Apple, associated domains, app groups, keychain groups).

Intended entitlements file: make it with `scripts/entitlements.py`. It reads no secret, so it can run before the signing approvals:

```sh
uv run python -I <skill>/scripts/entitlements.py "<ENTS>" "<CONFIG xcconfig>" <TEAM_ID> <BUNDLE_ID> <profile> <GATE>/out/app.entitlements
```

It replaces each `$(NAME)` (`AppIdentifierPrefix` = `<TEAM_ID>.`, the others from the xcconfig and its includes), adds `application-identifier`, `com.apple.developer.team-identifier` and `get-task-allow` = `true`, and exits 1 for each value that the profile does not allow. That exit is `Blocked`. It prints macro names, never values: an xcconfig can hold API keys. Evidence (2026-11-18): 8 keys for the tested app's Debug configuration, all allowed by an iOS App Development profile; a capability missing from the profile, an app group outside it, and an unknown macro each stopped it with exit 1.

Then run sections 7 and 8 of `kmp-ios-build-linux/references/build.md` with these changes: one profile only (the extensions are gone); `ENTS` is `<GATE>/out/app.entitlements`; in the signed-artifact checks, repeat only the section 5 checks above. Use its guarded OpenSSL 3 script as it is, with the paths of this run, rather than a new signing script: it also checks the password file's owner and mode, requires tmpfs staging, and refuses to overwrite an output.

## 7. Install

Authorization covers install only. Use the subcommand syntax of Debian 13 `ideviceinstaller`; confirm it with `ideviceinstaller --help` (`OPTIONS COMMAND`).

A device on Wi-Fi through netmuxd is a network device: `idevice_id -l` omits it. Use `idevice_id -n`, and add `-n` to each command below. If the user launches the app and it crashes, get the reports as `kmp-ios-build-linux/references/build.md` section 9 describes.

```sh
idevice_id -l
```

```sh
idevicepair -u <UDID> validate
```

```sh
ideviceinfo -u <UDID> -q com.apple.security.mac.amfi -k DeveloperModeStatus
```

```sh
ideviceinstaller -u <UDID> list --user
```

Record whether `<BUNDLE_ID>` is installed and its build number. If a TestFlight or App Store copy has the same bundle ID, get confirmation first: the install replaces it.

```sh
ideviceinstaller -u <UDID> install <GATE>/out/app-signed.ipa
```

```sh
ideviceinstaller -u <UDID> list --user
```

`Installed` needs `Install: Complete` and a listing of `<BUNDLE_ID>` with this run's `CURRENT_PROJECT_VERSION`.

## 8. Run evidence

Keep only the newest run per project.

- Project: a private production iOS app, one Debug scheme, gate `<GATE>` (2026-11-18).
- Build 2: 1,542 s, nearly all package fetch (41 packages, Firebase binaries). Later attempts reuse the cache: 20 to 260 s each.
- Build 21: exit 0. Unsigned IPA 71,381,167 bytes; executable ARM64 `MH_EXECUTE`, iOS, `minos` 16.0, SDK 27.0; 15 embedded frameworks; no `PlugIns`.
- Walls met in builds 3 to 21, one per build (the preflight did not yet check them). Each fix now lives in the named section; todo: a preflight check for each:
  1. Darwin SDK from xtool 1.x rejected (§1). 2. No `actool`/`ibtool` (§3). 3. Asset symbols and their extensions (§3.1). 4. Stale outputs after a stand-in change (§4). 5. `@State static var` (§4, codemod). 6. Process limit hang (§4). 7. `.strings` not decoded (§3). 8. No `bitcode_strip` (§3). 9. No `lipo` (§3). 10. clang calls GNU `ld` (§3). 11. `codesign` emulation (§3). 12. No `libswiftCompatibility*.a` (§3). 13. Private external `l` symbols in an old archive (§3). 14. No script build phases (§5). 15. netmuxd device needs `-n` (§7). 16. zsign password in argv (KMP §8 script). 17. Entitlement macros (§6, `entitlements.py`).
- Outcome: `Installed` (2026-11-18), launch not requested. Signed IPA 277,359,788 bytes; install `Install: Complete`; the device lists the bundle ID, build number `202611180740` and the Apple Development signer.
- Manual launch by the user: crash at launch, `EXC_CRASH SIGABRT` in `+[UIStoryboard storyboardWithName:bundle:]` from `UISceneConfiguration`, because `UISceneStoryboardFile: Common` has no compiled storyboard. Not compiled: 88 storyboards, 99 xibs, 34 asset catalogs; 423 source files load a storyboard or nib. User decision: no Mac, so this build is compile, signing and install evidence only.

## 9. Dead ends

Routes tried for an app that must launch, and why each failed. Read this before you propose one again.

- **Open-source `ibtool`** (`woct0rdho/ibtool` at `1282b92a07a4`, a 2015 reverse-engineered Python compiler for iOS nibs, 2026-11-18): 85 of 187 files compiled (33 of 88 storyboards, 52 of 99 xibs); both launch storyboards failed. Causes: 60 "object with id not found", 39 "connection destination not found", 2 "scene without view controller", 1 other. A compiled file is still unchecked: without a Mac there is no real `ibtool` output to compare. Making it work means reverse-engineering current Interface Builder features with no reference, so the cost has no clear bound. Result list: `<GATE>/logs/ibprobe-1-results.tsv`.
- **Skipping the launch storyboard** in `Info.plist`: the crash moves to the next screen that loads a storyboard or nib.
- **OS sandbox for a downloaded tool**: `unshare` is not permitted and `bwrap` is missing in this container. What worked: review the code (imports, file and process calls, encoded or dynamic code, git hooks, history, text aimed at an agent), then run it under a Python `sys.addaudithook` guard that stops on network, process, `ctypes` and fork calls, on writes or deletes outside the output folder, and on reads outside the source, the tool and the Python library. The guard (`scripts/examples/ibsandbox.py`, written for that ibtool run; the overlay maker and the archive fix of this run are in the same folder) stopped all 11 bad actions of a test tool. Set `sys.dont_write_bytecode`, and report errors without a traceback, which reads source files.
- What remains for a runnable app: a Mac with Xcode, either for the full build or for `ibtool` and `actool` output merged into this bundle.

## Sources

- xtool 2.0.0-beta.1 release notes (Xcode project support; asset catalogs, app intents and storyboards not supported on Linux): https://github.com/xtool-org/xtool/releases/tag/2.0.0-beta.1
- SwiftPM mixed-language targets, SE-0403 (returned for revision): https://github.com/swiftlang/swift-evolution/blob/main/proposals/0403-swiftpm-mixed-language-targets.md
- XcodeGen 2.47.0 (`make install` on Linux, #1665): https://github.com/yonaskolb/XcodeGen/releases/tag/2.47.0
- Trixie ideviceinstaller: https://manpages.debian.org/trixie/ideviceinstaller/ideviceinstaller.1.en.html
- Linux stand-ins for an app that must launch, not used by default: omarchy `tools/ibtool` (https://github.com/joshuaswarren/omarchy-apple-dev) and xtool-org AssetKit (https://github.com/xtool-org/AssetKit).
- Open-source iOS `ibtool` (section 9): https://github.com/woct0rdho/ibtool, after https://github.com/davidquesada/ibtool.
