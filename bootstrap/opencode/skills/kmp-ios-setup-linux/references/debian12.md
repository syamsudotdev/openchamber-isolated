# Debian 12 x86_64 setup reference

Use this Debian-first baseline with the workflow in `../SKILL.md`.
The complete fresh Debian procedure is not clean-room tested. The pinned tools and SDK interfaces were used in a configured Linux environment; the package baseline is conservative, not a proven minimum.
Pins are Swift `6.4.1`, xtool `1.22.2`, and an authorized Xcode `27` SDK input. Confirm project compatibility before adopting them.
Resolve every example path to the actual workspace before execution. `/home/iosbuilder` is an example, not a required user.
Run commands individually and stop on errors. Obtain approval for the resolved changes before execution.

## 1. Prepare Debian dependencies

Select the JDK from project requirements. Install Android SDK components only when project configuration requires them.
For other Debian releases, verify packages and binary compatibility first. For other distributions, research official distribution, Swift, and xtool documentation and adapt packages and paths before installation.

```sh
apt-get update
```

Refresh the Debian package index.

```sh
apt-get install --no-install-recommends ca-certificates curl gpg gpg-agent gzip xz-utils tar unzip zip file git nano clang pkg-config binutils libncurses6 libxml2 libicu72 libcurl4 libedit2 libsqlite3-0 libgcc-s1 libstdc++6 zlib1g tzdata
```

Install the conservative tool and Swift runtime baseline.

```sh
apt-get install --no-install-recommends llvm
```

Install an LLVM Mach-O inspector if none is available. This package does not qualify the port's compiler toolchain.

```sh
apt-get install --no-install-recommends build-essential libcurl4-openssl-dev zlib1g-dev
```

Install these optional development packages only when native dependencies require them.

```sh
mkdir -p /home/iosbuilder/ios-linux/tools /home/iosbuilder/ios-linux/downloads /home/iosbuilder/ios-linux/inputs
```

Create the resolved workspace directories.

## 2. Authenticate and extract Swift

```sh
curl --fail --show-error --silent --location --proto '=https' --proto-redir '=https' https://download.swift.org/swift-6.4.1-release/debian12/swift-6.4.1-RELEASE/swift-6.4.1-RELEASE-debian12.tar.gz -o /home/iosbuilder/ios-linux/downloads/swift-6.4.1-debian12.tar.gz
```

Download the pinned official Debian archive.

```sh
curl --fail --show-error --silent --location --proto '=https' --proto-redir '=https' https://download.swift.org/swift-6.4.1-release/debian12/swift-6.4.1-RELEASE/swift-6.4.1-RELEASE-debian12.tar.gz.sig -o /home/iosbuilder/ios-linux/downloads/swift-6.4.1-debian12.tar.gz.sig
```

Download its detached signature.

```sh
curl --fail --show-error --silent --location --compressed --proto '=https' --proto-redir '=https' https://swift.org/keys/release-key-swift-6.x.asc -o /home/iosbuilder/ios-linux/downloads/release-key-swift-6.x.asc
```

Download the official Swift 6.x release key.

```sh
curl --fail --show-error --silent --location --compressed --proto '=https' --proto-redir '=https' https://swift.org/keys/active/ -o /home/iosbuilder/ios-linux/downloads/swift-active-keys.html
```

Save the official active-key record for fingerprint comparison.

```sh
wc -c /home/iosbuilder/ios-linux/downloads/swift-6.4.1-debian12.tar.gz
```

Require an archive size of `1124105894` bytes.

```sh
sha256sum /home/iosbuilder/ios-linux/downloads/swift-6.4.1-debian12.tar.gz
```

Require SHA-256 `12a01b5658a679bc5970017a5173bfc28af3d45274e0878f586f2bcdc90acb60`.

```sh
gpg --show-keys --fingerprint /home/iosbuilder/ios-linux/downloads/release-key-swift-6.x.asc
```

Require primary fingerprint `52BB7E3DE28A71BE22EC05FFEF80A866B47A981F`.
Read the active-key record with a file reader and confirm the same fingerprint for Swift 6.x.

```sh
gpg --batch --import /home/iosbuilder/ios-linux/downloads/release-key-swift-6.x.asc
```

Import only the checked key.

```sh
gpg --batch --status-fd=1 --verify /home/iosbuilder/ios-linux/downloads/swift-6.4.1-debian12.tar.gz.sig /home/iosbuilder/ios-linux/downloads/swift-6.4.1-debian12.tar.gz
```

Require exit zero, `Good signature`, and `VALIDSIG` identifying the expected primary fingerprint. A trust warning is not a signature failure; a hash alone does not authenticate the publisher.

```sh
tar -tvzf /home/iosbuilder/ios-linux/downloads/swift-6.4.1-debian12.tar.gz
```

Review archive paths and links. Require root `swift-6.4.1-RELEASE-debian12/`, no absolute or parent-traversal paths, and relative links contained within that root.

```sh
mkdir /home/iosbuilder/ios-linux/tools/swift
```

Create a fresh extraction destination.

```sh
tar -xzf /home/iosbuilder/ios-linux/downloads/swift-6.4.1-debian12.tar.gz --strip-components=1 -C /home/iosbuilder/ios-linux/tools/swift --no-same-owner --no-same-permissions
```

Retain the complete `usr` tree, including libraries, plugins, and metadata. A small executable-only tool view is insufficient for fresh host setup.

## 3. Verify and extract xtool

```sh
curl --fail --show-error --silent --location --proto '=https' --proto-redir '=https' https://api.github.com/repos/xtool-org/xtool/releases/tags/1.22.2 -o /home/iosbuilder/ios-linux/downloads/xtool-1.22.2-release.json
```

Download the official pinned release record.

```sh
curl --fail --show-error --silent --location --proto '=https' --proto-redir '=https' https://github.com/xtool-org/xtool/releases/download/1.22.2/xtool-x86_64.AppImage -o /home/iosbuilder/ios-linux/downloads/xtool-1.22.2-x86_64.AppImage
```

Download the x86_64 AppImage.
Read the release JSON with a file reader. Require asset `xtool-x86_64.AppImage`, size `56646136`, and digest `e3176cdf861f58b7f135c755c7bfaec92d0568ef826027b4e5e3d82b3219ddfe` in the same asset record.
This is an HTTPS release digest, not a separate publisher signature.

```sh
wc -c /home/iosbuilder/ios-linux/downloads/xtool-1.22.2-x86_64.AppImage
```

Require the downloaded size to match.

```sh
sha256sum /home/iosbuilder/ios-linux/downloads/xtool-1.22.2-x86_64.AppImage
```

Require SHA-256 `e3176cdf861f58b7f135c755c7bfaec92d0568ef826027b4e5e3d82b3219ddfe` before executing the AppImage.

```sh
chmod u+x /home/iosbuilder/ios-linux/downloads/xtool-1.22.2-x86_64.AppImage
```

Make the verified AppImage executable.

```sh
mkdir /home/iosbuilder/ios-linux/tools/xtool
```

Create a fresh extraction parent.

```sh
cd /home/iosbuilder/ios-linux/tools/xtool
```

Select the AppImage extraction parent.

```sh
/home/iosbuilder/ios-linux/downloads/xtool-1.22.2-x86_64.AppImage --appimage-extract
```

Extract without FUSE or mounting.

```sh
/home/iosbuilder/ios-linux/tools/swift/usr/bin/swift --version
```

Require Swift `6.4.1` for Linux.

```sh
env PATH=/home/iosbuilder/ios-linux/tools/swift/usr/bin:/home/iosbuilder/ios-linux/tools/xtool/squashfs-root/usr/bin:/usr/local/bin:/usr/bin:/bin /home/iosbuilder/ios-linux/tools/xtool/squashfs-root/AppRun --version
```

Require xtool `1.22.2` with the complete Swift distribution selected first.
Resolve and record `swiftc`, `zip`, and inspector paths and versions as well.

## 4. Install the authorized SDK

Obtain Xcode 27 from `https://developer.apple.com/download/all/` under the user's authorization and applicable license terms. A human Apple-account download can be necessary.
Place the authorized input at the resolved equivalent of `/home/iosbuilder/ios-linux/inputs/Xcode.xip`.
```sh
sha256sum /home/iosbuilder/ios-linux/inputs/Xcode.xip
```

Record its identity hash; this does not independently authenticate the Apple XIP certificate chain.

```sh
env PATH=/home/iosbuilder/ios-linux/tools/swift/usr/bin:/home/iosbuilder/ios-linux/tools/xtool/squashfs-root/usr/bin:/usr/local/bin:/usr/bin:/bin /home/iosbuilder/ios-linux/tools/xtool/squashfs-root/AppRun sdk install /home/iosbuilder/ios-linux/inputs/Xcode.xip --slim
```

Install the slim SDK using normal configuration discovery. Preserve any existing required XDG settings consistently across commands.
The installer can download Darwin tools and OpenAppleMacros. Record actual versions and official release provenance; automatic downloads are not independent signature checks.
Previously selected auxiliary versions were Darwin tools `1.1.0` and OpenAppleMacros `1.3.0`.

```sh
env PATH=/home/iosbuilder/ios-linux/tools/swift/usr/bin:/home/iosbuilder/ios-linux/tools/xtool/squashfs-root/usr/bin:/usr/local/bin:/usr/bin:/bin /home/iosbuilder/ios-linux/tools/xtool/squashfs-root/AppRun sdk status
```

Require installed status and record the actual `Path:` as the SDK bundle authority.

```sh
env PATH=/home/iosbuilder/ios-linux/tools/swift/usr/bin:/home/iosbuilder/ios-linux/tools/xtool/squashfs-root/usr/bin:/usr/local/bin:/usr/bin:/bin /home/iosbuilder/ios-linux/tools/swift/usr/bin/swift sdk list
```

Require Swift to discover the same `darwin` SDK.

Use a file reader to inspect these files relative to the reported SDK bundle, not a guessed home directory:

- `swift-sdk.json`: resolve the iOS device target's `sdkRootPath`.
- Device SDK `SDKSettings.json`: verify SDK version and iOS device platform, separately from the deployment minimum.
- `toolset.json`: compare every recorded tool path with installed files.

Verify executable files `toolset/bin/ld64.lld`, `toolset/bin/llvm-lib`, `toolset/bin/dsymutil`, and root `OpenAppleMacrosServer`.
Record the resolved toolset directory for later process-local `PATH` use and the real Swift compiler for `SWIFT_EXEC`.

## 5. Qualify the Linux port

Return to step 5 of `../SKILL.md` for the complete qualification gate.
Stock Linux Kotlin/Native and Kotlin Gradle Plugin disable Apple final-binary tasks; xtool does not provide the required port.
This reference supplies no patch or bundle. Research and propose a bounded experiment if no matching qualified implementation exists.
Use a separate minimal framework probe after approval, or reuse matching unchanged evidence. Do not compile the actual application during setup.
Report partial readiness when the port gate fails, even if all Swift and SDK checks pass.

## 6. Prepare signing and device readiness

Return to step 6 of `../SKILL.md` for the readiness gate. This section prepares capabilities, not an application build or a device operation.

### Select a signer and credential route

- Prefer a separate Linux signer for a user-provided developer identity and provisioning profile. Community zsign `v1.1.3` is not an Apple tool.
- Inspect the [upstream release](https://github.com/zhlynn/zsign/releases/tag/v1.1.3) and its [release API record](https://api.github.com/repos/zhlynn/zsign/releases/tags/v1.1.3). Select an actual CPU-compatible asset, verify its release SHA-256 when supplied, and check libc requirements. Record any trust-verification limit; do not invent an asset name or digest.
- Pin the selected version and record provenance. Verify the installed signer's actual version/help and identity formats before use. Debian's package baseline below does not install zsign.
- zsign `v1.1.3` accepts a `.p12`, but its password option exposes the password in process arguments. No safe standard-input, environment, or password-file interface is verified for that version. Never request or render a password in chat or command arguments.
- zsign `v1.1.3` also supports an unencrypted PEM private key with `-k` and a PEM or DER certificate with `-c`; it checks the certificate/key match with `X509_check_private_key`.
- A protected `.p12` can use OpenSSL 3 with an approved password-file input mechanism and explicitly approved temporary unencrypted PEM export. Credentials alone do not authorize this route. Keep exact export/signing commands in the build reference.
- Qualify a fresh private staging directory with mode `0700` and temporary key/certificate files with mode `0600`. Require mode `0600` for the approved password file; do not change a user-owned file without approval.
- Arrange cleanup before temporary key creation. Remove temporary key/certificate files on success, failure, or interruption and verify their absence. Preserve the original `.p12` and user password file. Ordinary deletion does not guarantee secure erasure on an SSD.
- Keep secret values out of chat, command arguments, logs, and standard-output dumps. File permissions do not establish consent to private-key export.
- If this route is not approved, select an approved signer with protected secret input or an approved human-managed signing step. Otherwise record a signed-build blocker. Record route evidence without secret values.
- Record already-provided identity/profile paths and safe identifiers only. Leave certificate/key matching and profile App ID, team, expiry, entitlement, and target-device coverage validation to `kmp-ios-build-linux`.
- xtool `1.22.2` `dev build --sign` uses xtool authentication with Apple Developer Services; it is not a `.p12` import route. Rights to download Xcode are separate from signing credentials.

### Prepare device tools

```sh
apt-get install --no-install-recommends openssl usbmuxd libimobiledevice-utils ideviceinstaller
```

Install this Debian baseline only after approval and selection of compatible package versions.

- Record exact selected package versions and package provenance. For another distribution, derive equivalent official packages, binaries, and libc paths yourself. Use a source build only when host packages are incompatible and the user approves it.
- Inspect actual version/help output for OpenSSL, device enumeration/pairing helpers, and `ideviceinstaller`. Record executable paths and the selected install/list/UDID syntax. Bookworm baselines are `ideviceinstaller` `1.1.1-1` and `libimobiledevice-utils` `1.3.0-6`; confirm installed versions instead of assuming them.
- Use Bookworm's legacy installer interface, not current upstream's `install`/`list` subcommands. The build reference owns version-specific installation and pairing commands; setup records capabilities only.
- Inspect the existing xtool executable's actual `install` and `launch` help. Record the required process-local Swift path from the toolchain handoff.
- xtool `1.22.2` installation reads `AuthToken.saved`; a pre-signed IPA alone does not satisfy this installer's authentication requirement. Qualify that prerequisite or select an approved compatible installer.
- A pre-signed IPA installed with `ideviceinstaller` does not require a new Apple login or xtool authentication.
- xtool launch does not require that authentication, but it requires installed-bundle lookup and debugserver access. Tool/help availability is capability evidence, not installation or launch evidence.

### Record independent verification limits

- Record the approved independent verifier's path, version, and demonstrated capability, or **Unavailable**. No Linux verifier for CodeDirectory, CMS, sealed resources, and nested signatures is qualified by this reference.
- zsign `-C` reports certificate/OCSP information; it does not verify signed-archive integrity. A signature load command or signer success is not independent cryptographic verification.
- Report signer-produced output with static-check evidence and the explicit unverified cryptographic limit. If independent verification is required, research a suitable verifier or propose macOS validation only within approved scope.
- Treat device installation acceptance as a separate observable gate. It does not verify every runtime feature.

### Record target readiness

- Record the explicit target UDID before any device mutation. Keep device enumeration read-only and within the user's authorization; otherwise report the target state as unavailable.
- Verify host USB/usbmuxd visibility. Request approval for container USB passthrough when needed; do not assume root mounts or device access.
- Ask the human to connect and unlock the device, select **Trust** on the device, and enter its passcode when prompted. Wait for confirmation before an approved pairing operation.
- When required, ask the human to open **Settings > Privacy & Security > Developer Mode**, enable it, restart, and confirm after restart. Wait for completion; do not bypass Trust or Developer Mode.
- Record connection, pairing, profile/device validation, and Developer Mode separately from an actual installation event. Missing device access means **Install pending**, not failure to build a signed IPA.

Complete the step 7 handoff in `../SKILL.md`. Missing credentials or an unapproved secret route block the signed goal; an unsigned artifact is an explicit user-selected fallback only.

## Sources

- Swift Linux installation: `https://www.swift.org/install/linux/`
- Swift active keys: `https://swift.org/keys/active/`
- xtool release: `https://github.com/xtool-org/xtool/releases/tag/1.22.2`
- xtool pinned source: `https://github.com/xtool-org/xtool/tree/1.22.2`
- Darwin tools: `https://github.com/xtool-org/darwin-tools-linux-llvm/releases/tag/v1.1.0`
- OpenAppleMacros: `https://github.com/xtool-org/OpenAppleMacros/releases/tag/v1.3.0`
- Community zsign release: `https://github.com/zhlynn/zsign/releases/tag/v1.1.3`
- Debian package versions: `https://packages.debian.org/bookworm/ideviceinstaller`
- Device tools upstream: `https://github.com/libimobiledevice/libimobiledevice` and `https://github.com/libimobiledevice/ideviceinstaller`
