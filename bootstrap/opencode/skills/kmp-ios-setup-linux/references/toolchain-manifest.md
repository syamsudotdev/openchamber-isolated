# Machine toolchain manifest

Use with `../SKILL.md`. This file is the build list for one Debian 12 x86_64 machine: every component the KMP-iOS toolchain needs, its official source, its integrity check, where it goes, and the environment that makes it work. Read it before the first install on a machine; on a machine that already has a record, read the record instead.

A new machine is reproducible when every row below is either installed from its official URL, or rebuilt from the sources in `../scripts/port/`. Nothing here is a third-party binary stored in the skill.

## 1. The machine record

One root per machine holds every component and the record that describes them.

```text
<root>/
  env.sh                     the record: exports every path below
  manifest.tsv               component, version, path, sha256 (tab-separated)
  downloads/                 verified archives, kept for reinstall
  bin/                       konanc, swift, swiftc, xtool, zsign shims (see §2)
  konan-data/dependencies/   JetBrains LLVM, libffi; .extracted lists them
  kotlin-native/             the Linux Kotlin/Native distribution
  macos-selected/            iOS-only members taken from the macOS archive
  linux-toolchain/bin/       the libtool adapter (custom, §6)
  port/                      inspect-archive.cjs and select-slice.cjs (custom, §6)
  agent/                     probe-agent.jar and probe-bootstrap.jar (custom, §6)
  empty-sysroot/             deliberately empty Xcode sysroot
  swift-distribution/        the complete Swift `usr` tree
  xtool-distribution/        xtool 1.22.2 squashfs-root
  xtool2-distribution/       xtool 2.0.0-beta.1 squashfs-root
  xtool-home/                shared HOME for the SDK install; holds no SDK and no login token
  xdg/config/                shared XDG_CONFIG_HOME; holds swiftpm/swift-sdks/darwin.artifactbundle, the one Darwin SDK
  sdk/                       optional copy target for the darwin.artifactbundle
  deps/                      extracted Debian runtime libraries for Swift
  zsign/                     zsign executable (C19)
  packaging-tools/root/      extracted Debian zip (C20)
  devtools/root/ devtools/bin/  extracted Trixie device tools (C21) and their wrappers
  python/                    Python venv with the pinned Pillow (C25)
  cache/ tmp/ logs/          build scratch and evidence; cache/framework-probe/ holds the step 5 probe
```

Choose the root and write the record with one command:

```sh
bash scripts/setup-toolchain-root.sh
```

It picks the first usable root in this fixed order, and prints `BLOCK <path>: <reason>` for each candidate it rejects:

1. `--root <dir>`, when given.
2. `$KMP_IOS_TOOLCHAIN_ROOT`, when set.
3. `${XDG_DATA_HOME:-$HOME/.local/share}/kmp-ios-toolchain`.
4. `$HOME/.kmp-ios-toolchain`.

A candidate is rejected on tmpfs or under `/tmp`, when it cannot be created or written, or when it has less than 20 GiB free (`--min-free-gib`). Never select `/tmp` or `/dev/shm`: this machine mounts `/tmp` as a 1 GB tmpfs, and a Kotlin/Native plus Swift plus SDK set needs about 15 GiB after extraction.

Record every install as soon as it verifies, so no later project repeats it:

```sh
bash scripts/record-component.sh <component> <version> <path> [sha256|compute]
```

`compute` hashes the file now and stores `computed locally:<hash>`; that marks a value that no publisher digest was compared against. Add `--env NAME` to export `NAME=<path>` in the record at the same time, for example `record-component.sh zsign v1.1.3 <root>/bin/zsign.bin compute --env ZSIGN`.

The record exports these names. A build reads the record, not a per-gate copy:

| Export | Meaning |
|---|---|
| `KMP_IOS_TOOLCHAIN_ROOT` | the root above |
| `KONAN_HOME` | `kotlin-native-prebuilt-linux-x86_64-2.4.20` directory (C01) |
| `KONAN_DATA_DIR` | `<root>/konan-data`; `konan.properties` reads it |
| `KONAN_USE_INTERNAL_SERVER` | `0`; the Kotlin/Native build server is not used |
| `SWIFT_BIN` | the Swift `usr/bin` directory (C11) |
| `XTOOL` | xtool 1.22.2 `squashfs-root/AppRun` (C15) |
| `XTOOL2` | xtool 2.0.0-beta.1 `squashfs-root/AppRun` (C16) |
| `XTOOL_HOME` | shared `HOME` for `install-sdk.sh`; the SDK itself is under `XTOOL_XDG_CONFIG_HOME` |
| `XTOOL_XDG_CONFIG_HOME` | shared `XDG_CONFIG_HOME` that holds the Darwin SDK (C17) and makes it discoverable |
| `KMP_IOS_SDK` | the one `darwin.artifactbundle` (C17); empty until `install-sdk.sh` runs |
| `LLVM_BIN` | JetBrains LLVM `bin/` (C03); `llvm-ar` lives here, `llvm-objdump` does not |
| `OBJDUMP` | the Mach-O inspector binary: Swift's `usr/bin/llvm-objdump` (C11), because the C03 essentials set has none |
| `ZSIGN` | zsign executable (C19) |
| `KMP_IOS_AGENT_JAR`, `KMP_IOS_BOOTSTRAP_JAR` | the two agent jars (§6) |
| `KMP_IOS_LIBTOOL` | the libtool adapter (§6) |
| `KMP_IOS_ARCHIVE_INSPECTOR`, `KMP_IOS_SLICER` | the fat-archive tools (§6) |
| `KMP_IOS_ARCHIVER_LOG` | optional command log of the adapter |
| `KMP_IOS_LD_LIBRARY_PATH` | the `deps/` library path for Swift and xtool |
| `PATH` | `<root>/bin` first |

If the record path must differ, set `KMP_IOS_RECORD` to the `env.sh` to read.

## 2. PATH shims

A tool that is installed but not on `PATH` is missing on the next project. `setup-toolchain-root.sh` writes five shims to the first writable directory already on `PATH`, with `~/.local/bin` first: `konanc`, `swift`, `swiftc`, `xtool`, `zsign`. Each shim sources `<root>/env.sh`, so it keeps working after a later install fills a value, and names the setup step when its tool is not installed yet.

The `xtool` shim keeps the `devices --no-wait` behaviour: `xtool devices` returns at once when no device is connected, and `--wait` asks for waiting.

The `swift`, `swiftc` and `xtool` shims export `XDG_CONFIG_HOME=$XTOOL_XDG_CONFIG_HOME` from the record, so `xtool sdk status` and `swift sdk list` find the one shared SDK in every project. They keep the caller's `HOME`, so no xtool login token is written under the root. Without the shims, pass the same value yourself.

When no directory on `PATH` is writable, the script creates `~/.local/bin`, adds one guarded `PATH` line to `~/.profile` and `~/.bashrc` (the marker makes a second run a no-op), and reports the change as a `BLOCK` line with that fix.

Re-run `setup-toolchain-root.sh` after the installs that set `KONAN_HOME`, `SWIFT_BIN`, `XTOOL` or `ZSIGN` in the record. The shims read the record at run time, so this only refreshes their target values.

## 3. Install order

1. Machine record and shims (§1, §2).
2. Kotlin/Native compiler set: C01 to C04, then the port (§6).
3. Swift and its runtime libraries: C11 to C14.
4. xtool 1.22.2 and 2.0.0-beta.1: C15, C16.
5. The one Darwin SDK from the Xcode XIP: C17, C18, with `scripts/install-sdk.sh`.
6. Signing, packaging and device tools: C19 to C23.
7. Helper runtimes: C25, C26.
8. Record every component as it verifies (§1).

## 4. Components from official sources

Sizes are recorded bytes; use them to catch a truncated transfer, not as a checksum.

### Kotlin/Native compiler set

| ID | Component and version | Official URL | Integrity | Bytes | Install path |
|---|---|---|---|---|---|
| C01 | Kotlin/Native Linux prebuilt `2.4.20` | `https://github.com/JetBrains/kotlin/releases/download/v2.4.20/kotlin-native-prebuilt-linux-x86_64-2.4.20.tar.gz` | SHA256 `32d33c15c4da668a8d47a0ce2aea95be2c2cf8f5d1d65f6f4ed3697e4686dc7f` (GitHub release digest); no separate signature | 219,971,249; 793,559,608 extracted (earlier record; method not recorded); 727,478,122 file bytes in 41,476 `tar -tv` entries, computed locally 2026-11-24 | `<root>/kotlin-native/` |
| C02 | Kotlin/Native macOS x86_64 `2.4.20` (iOS ARM64 members only) | `https://github.com/JetBrains/kotlin/releases/download/v2.4.20/kotlin-native-prebuilt-macos-x86_64-2.4.20.tar.gz` | SHA256 `eecb7ecd392c092fca216602d468a49d4a820aaab480109d2c9ee104a9d97de3` | 287,661,134; 50,079,450 selected (earlier record; method not recorded); 42,776,282 file bytes in the 3,552 selected `tar -tv` entries, computed locally 2026-11-24 | `klib/` and `konan/targets/ios_arm64` of C01 |
| C03 | JetBrains LLVM `llvm-21-x86_64-linux-essentials-116` | `https://download.jetbrains.com/kotlin/native/resources/llvm/21-x86_64-linux/llvm-21-x86_64-linux-essentials-116.tar.gz` | SHA256 `0b1f290214dd7ec20e2506210967e0ebd735cdefc3a3b4485bbccb439fa78e5b`, computed locally | 189,782,367 | `<root>/konan-data/dependencies/` |
| C04 | libffi `libffi-3.2.1-2-linux-x86-64` | `https://download.jetbrains.com/kotlin/native/libffi-3.2.1-2-linux-x86-64.tar.gz` | SHA256 `9d817bbca098a2fa0f1d5a8b9e57674c30d100bb4c6aeceff18d8acc5b9f382c`, computed locally | 56,412 | `<root>/konan-data/dependencies/` |

The LLVM URL needs its `21-x86_64-linux` directory; without it the server returns HTTP 404. The macOS archive supplies only data: no Darwin compiler, host tool or cache is executed. Keep the two versions equal, because `konan.properties` names its dependencies by version.

```sh
curl -fL --max-time 1200 <C01 URL> -o <root>/downloads/kotlin-native-linux-2.4.20.tar.gz
printf '%s  %s\n' 32d33c15c4da668a8d47a0ce2aea95be2c2cf8f5d1d65f6f4ed3697e4686dc7f <root>/downloads/kotlin-native-linux-2.4.20.tar.gz | sha256sum -c -
tar -xzf <root>/downloads/kotlin-native-linux-2.4.20.tar.gz -C <root>
mv <root>/kotlin-native-prebuilt-linux-x86_64-2.4.20 <root>/kotlin-native
```

```sh
curl -fL --max-time 1200 <C02 URL> -o <root>/downloads/kotlin-native-macos-2.4.20.tar.gz
printf '%s  %s\n' eecb7ecd392c092fca216602d468a49d4a820aaab480109d2c9ee104a9d97de3 <root>/downloads/kotlin-native-macos-2.4.20.tar.gz | sha256sum -c -
tar -tzf <root>/downloads/kotlin-native-macos-2.4.20.tar.gz > <root>/macos-members.txt
node -e 'const fs=require("fs");const re=/^kotlin-native-prebuilt-macos-x86_64-2.4.20\/(klib\/(platform\/ios_arm64|common\/stdlib\/default\/targets\/ios_arm64)|konan\/targets\/ios_arm64)(\/|$)/;const out=fs.readFileSync(process.argv[1],"utf8").split("\n").filter(l=>re.test(l));fs.writeFileSync(process.argv[2],out.join("\n")+"\n");console.log("selected",out.length)' <root>/macos-members.txt <root>/ios-members.txt
mkdir -p <root>/macos-selected
tar -xzf <root>/downloads/kotlin-native-macos-2.4.20.tar.gz -C <root>/macos-selected --no-recursion -T <root>/ios-members.txt
cp -a <root>/macos-selected/kotlin-native-prebuilt-macos-x86_64-2.4.20/klib/. <root>/kotlin-native/klib/
cp -a <root>/macos-selected/kotlin-native-prebuilt-macos-x86_64-2.4.20/konan/targets/ios_arm64 <root>/kotlin-native/konan/targets/
```

Require `selected 3552`. The member list must come before `-C`; the reverse order failed once.

```sh
curl -fL --max-time 1200 --max-filesize 4000000000 <C03 URL> -o <root>/downloads/llvm-21-essentials-116.tar.gz
printf '%s  %s\n' 0b1f290214dd7ec20e2506210967e0ebd735cdefc3a3b4485bbccb439fa78e5b <root>/downloads/llvm-21-essentials-116.tar.gz | sha256sum -c -
mkdir -p <root>/konan-data/dependencies
tar -xzf <root>/downloads/llvm-21-essentials-116.tar.gz -C <root>/konan-data/dependencies
printf 'llvm-21-x86_64-linux-essentials-116\n' >> <root>/konan-data/dependencies/.extracted
```

```sh
curl -fL --max-time 180 --max-filesize 100000000 <C04 URL> -o <root>/downloads/libffi-3.2.1-2-linux-x86-64.tar.gz
printf '%s  %s\n' 9d817bbca098a2fa0f1d5a8b9e57674c30d100bb4c6aeceff18d8acc5b9f382c <root>/downloads/libffi-3.2.1-2-linux-x86-64.tar.gz | sha256sum -c -
tar -xzf <root>/downloads/libffi-3.2.1-2-linux-x86-64.tar.gz -C <root>/konan-data/dependencies
printf 'libffi-3.2.1-2-linux-x86-64\n' >> <root>/konan-data/dependencies/.extracted
```

Re-run `setup-toolchain-root.sh` after these extractions: it fills the empty `KONAN_HOME`, `SWIFT_BIN`, `XTOOL`, `XTOOL2` and `OBJDUMP` fields of the record from the paths above. `LLVM_BIN` and `KONAN_DATA_DIR` are written by the first run.

### Swift and its runtime libraries

| ID | Component and version | Official URL | Integrity | Bytes | Install path |
|---|---|---|---|---|---|
| C11 | Swift `6.4.1-RELEASE-debian12` | `https://download.swift.org/swift-6.4.1-release/debian12/swift-6.4.1-RELEASE/swift-6.4.1-RELEASE-debian12.tar.gz` and `.sig` | SHA256 `12a01b5658a679bc5970017a5173bfc28af3d45274e0878f586f2bcdc90acb60`; detached signature verified with Swift 6.x key `52BB7E3DE28A71BE22EC05FFEF80A866B47A981F` | 1,124,105,894; 3,702,069,811 extracted | `<root>/swift-distribution/` |
| C12 | libncurses6 `6.4-4` | `https://deb.debian.org/debian/` (`Filename` from the authenticated bookworm index) | SHA256 `72300f09f02669c06c99b641ea795d52300ec7eb65eaccddf7bc3b72934f0ef5`, 103,136 bytes, from the signed index | 103,136 | `<root>/deps/` |
| C13 | libxml2 `2.9.14+dfsg-1.3~deb12u6` | as C12 | SHA256 `4460e39dda10a815881374217cde08474747cfa018358cd8612c14b390eff53b`, 688,760 bytes | 688,760 | `<root>/deps/` |
| C14 | libicu72 `72.1-3+deb12u1` | as C12 | SHA256 `f7f6f99c6d7b025914df2447fc93e11d22c44c0c8bdd8b6f36691c9e7ddcef88`, 9,376,124 bytes | 9,376,124 | `<root>/deps/` |

The full Swift download, key import, signature check and extraction commands are in [debian12.md §2](debian12.md#2-authenticate-and-extract-swift). Extract to `<root>/swift-distribution/swift-6.4.1-RELEASE-debian12` with `--strip-components` semantics kept from that section, and keep the whole `usr` tree.

C12 to C14 come from the bookworm `Packages` record, after `InRelease` is authenticated with `gpgv` and the Debian keyring. Extract each with `dpkg-deb --extract`; run no maintainer script. Common alternative: install the same three packages with the host package manager, then record their paths. Swift on Linux needs the full `LD_LIBRARY_PATH` from the record; Foundation also needs `CFFIXED_USER_HOME` because it ignores `HOME`.

### xtool and the Darwin SDK

| ID | Component and version | Official URL | Integrity | Bytes | Install path |
|---|---|---|---|---|---|
| C15 | xtool `1.22.2` | `https://github.com/xtool-org/xtool/releases/download/1.22.2/xtool-x86_64.AppImage`; release record `https://api.github.com/repos/xtool-org/xtool/releases/tags/1.22.2` | SHA256 `e3176cdf861f58b7f135c755c7bfaec92d0568ef826027b4e5e3d82b3219ddfe` (GitHub release API); no publisher signature | 56,646,136 | `<root>/xtool-distribution/squashfs-root/` |
| C16 | xtool `2.0.0-beta.1` (prerelease) | `https://github.com/xtool-org/xtool/releases/download/2.0.0-beta.1/xtool-x86_64.AppImage` | SHA256 `0361a2570e46a7734e8bafa71715ca8a72cf218e0e7a945eef0e4d71733b19e3` | 67,799,544 | `<root>/xtool2-distribution/squashfs-root/` |
| C17 | Xcode 27 XIP (Darwin SDK input) | `https://developer.apple.com/download/all/` under the user's Apple account and license | SHA256 recorded at first download; it is an identity hash, not an Apple authentication. `Xcode_27.xip` used 2026-11-24: `6a270c53a5a0c5e0ac78125342d44c3cfff2716ec390373cd5e30834d80a67c3` | 2,014,229,334 (1,920.9 MiB) for that input, computed locally 2026-11-24 | `<root>/xdg/config/swiftpm/swift-sdks/darwin.artifactbundle` via `XDG_CONFIG_HOME` |
| C18 | Darwin tools `1.1.0`, OpenAppleMacros `1.3.0` | `https://github.com/xtool-org/darwin-tools-linux-llvm/releases/tag/v1.1.0`, `https://github.com/xtool-org/OpenAppleMacros/releases/tag/v1.3.0` | Fetched by `xtool sdk install` without a separate check. Release API digests, computed locally 2026-11-24: `toolset-x86_64.tar.gz` `a5166f2d56ac45707e5ef2f3c20a41a94af8ef0c0456354224dd08656e874188` (not compared: xtool keeps no archive); `OpenAppleMacrosServer-x86_64` `bc804ac517a4f1df270bacb655c9f7f57635bb4484dd536740b2516ae7a7b441`, equal to the installed bundle-root `OpenAppleMacrosServer`. `sdk status` reports `epoch=3,darwinTools=1.1.0,oam=1.3.0` | 46,205,054 toolset archive; 69,433,888 server | inside the C17 bundle |

```sh
chmod u+x <root>/downloads/xtool-1.22.2-x86_64.AppImage
mkdir -p <root>/xtool-distribution && cd <root>/xtool-distribution
<root>/downloads/xtool-1.22.2-x86_64.AppImage --appimage-extract
env PATH=<root>/swift-distribution/swift-6.4.1-RELEASE-debian12/usr/bin:<root>/xtool-distribution/squashfs-root/usr/bin:/usr/bin:/bin <root>/xtool-distribution/squashfs-root/AppRun --version
```

Install C16 the same way into `<root>/xtool2-distribution`; it needs no FUSE.

```sh
bash scripts/install-sdk.sh <path-to-Xcode_27.xip>
```

`install-sdk.sh` hashes the XIP, runs `<xtool> sdk install <xip> --slim` with `HOME=<root>/xtool-home` and `XDG_CONFIG_HOME=<root>/xdg/config`, reads the real `Path:` from `sdk status`, and writes `KMP_IOS_SDK`. One SDK serves every project on the machine.

An SDK made by xtool 1.x is rejected by 2.x (`Darwin SDK is out of date`), and a slim SDK cannot be updated in place. On that message reinstall with the 2.x xtool; do not patch the bundle. xtool keeps any saved login token in `$HOME/.config/xtool/data/`, so the shared `HOME` must stay free of a token, and no secret is written under the root.

### Signing, packaging, project generator and device tools

| ID | Component and version | Official URL | Integrity | Bytes | Install path |
|---|---|---|---|---|---|
| C19 | zsign `v1.1.3` (community signer, not an Apple tool) | `https://github.com/zhlynn/zsign/releases/download/v1.1.3/zsign-linux-x86_64.tar.gz`; release API `https://api.github.com/repos/zhlynn/zsign/releases/tags/v1.1.3` and the release's `SHA256SUMS.txt` | SHA256 `e384af9432a86d72262436f6df32c39d4193a31fcde5349f1ac6c3c293c8b8b2` (release API `digest` and `SHA256SUMS.txt` agree); no publisher signature | 248,839 archive; one member `zsign`, 539,016 bytes | `<root>/zsign/zsign`, recorded as `ZSIGN`, with a `zsign` shim on `PATH` |
| C20 | Debian `zip` `3.0-13` | bookworm `main` index at `https://deb.debian.org/debian/` | SHA256 `8877a360e455c7b9b6d448503eeaacc6b9a1325b548f3fb7eef69a87ab558b96` from the authenticated `Packages` record, computed locally 2026-11-24; the bookworm indexes also hold `3.0-13+deb12u1` | 229,532 | `<root>/packaging-tools/root/usr/bin/zip` |
| C21 | Trixie device set: libimobiledevice-utils `1.3.0+git20250228-2`, ideviceinstaller `1.1.1+git20240518-1+b1`, and their libraries | `https://deb.debian.org/debian` and `https://deb.debian.org/debian-security`, suites `trixie`, `trixie-updates`, `trixie-security` | `InRelease` authenticated with `sqv` on Trixie (`gpgv` may be absent), then `Packages.xz` and each `.deb` checked against it; values in the C21 table below | 443,088 for the 8 packages | `<root>/devtools/root/`, wrappers in `<root>/devtools/bin/` |
| C22 | host `usbmuxd`, `socat` | distribution packages | package manager signature | Unknown | host paths; recorded, not copied |
| C23 | XcodeGen `2.47.0` (built from source) | `https://github.com/yonaskolb/XcodeGen` tag `2.47.0`, commit `8f1f80bb912df5fa1c732f96dadbdff14005056e` | commit pin; no digest | Unknown | `<root>/bin/xcodegen` |

```sh
swift build -c release --product xcodegen --build-system native
```

Build C23 with Swift from the record and `LD_LIBRARY_PATH` from the record. The default Swift Build system drops that variable in its link step, and `swiftc` then cannot load `libncurses.so.6` from `<root>/deps`.

zsign `v1.1.3` accepts `-k` (unencrypted PEM key), `-c` (PEM or DER certificate), `-m` (profile), `-e` (entitlements), `-o`, `-t`; its password option exposes the password in argv. The `-C` flag prints certificate and OCSP data and does not verify a signed archive. Record `Unknown` rather than inventing an asset name, size or digest.

C12 to C14, C20 and C21 in a read-only container: `scripts/fetch-debs.py` authenticates each suite's `InRelease` with `sqv`, rejects a one-byte-tampered copy as a control, checks `Packages.xz` and every `.deb`, follows `Depends` with `--closure` for packages the host lacks, and extracts with `dpkg-deb --extract`:

```sh
uv run --no-project python -I scripts/fetch-debs.py --release bookworm --keyring /usr/share/keyrings/debian-archive-keyring.pgp --work <root>/downloads/debian-bookworm --dest <root>/deps libncurses6=6.4-4 libxml2=2.9.14+dfsg-1.3~deb12u6 libicu72=72.1-3+deb12u1
uv run --no-project python -I scripts/fetch-debs.py --release bookworm --keyring /usr/share/keyrings/debian-archive-keyring.pgp --work <root>/downloads/debian-bookworm-zip --dest <root>/packaging-tools/root zip=3.0-13
uv run --no-project python -I scripts/fetch-debs.py --release trixie --closure --keyring /usr/share/keyrings/debian-archive-keyring.pgp --work <root>/downloads/debian-trixie-devtools --dest <root>/devtools/root libimobiledevice-utils ideviceinstaller
```

Then wrap each binary in `<root>/devtools/bin/` with `LD_LIBRARY_PATH` to `<root>/devtools/root/usr/lib/x86_64-linux-gnu`, and require no `not found` from `ldd` in that environment.

C21 closure on a Debian 13 host, resolved 2026-11-24 (`.deb` bytes and SHA256 from the authenticated index, computed locally):

| Package | Version | Bytes | SHA256 |
|---|---|---|---|
| libimobiledevice-utils | 1.3.0+git20250228-2 | 112,608 | `b8e830fc0c2455976c12091061690dac9207a2c8d3e5369556ecc6a87d7b97f3` |
| ideviceinstaller | 1.1.1+git20240518-1+b1 | 19,720 | `130fdaca60b8c71bc72486e01a933b850363bf9ce645e88b9361bdd132ba3c46` |
| libimobiledevice-1.0-6 | 1.3.0+git20250228-2 | 134,628 | `92424711dc32b9f537d744efe813e21079134b0a89899bd2c0ba44ed0e0f529c` |
| libimobiledevice-glue-1.0-0 | 1.3.1-1 | 31,048 | `f8741f861fcf9d84c31cfa1c0b9fb6dee2d03ebb8948b846ea3e640f395f41c3` |
| libplist-2.0-4 | 2.6.0-2+b1 | 49,524 | `eb9408867f4813013dc8ec748d532892f22d2c4b34255d7d13d0bb97d6318793` |
| libtatsu0 | 1.0.3-1+b1 | 15,900 | `e12e1e6292dffe5abc598855a82ac6040b1194ad3651f9c5bd72652f7a0049f7` |
| libusbmuxd-2.0-7 | 2.1.0-1+b1 | 17,048 | `95ac08e68a327fbc1790e29faff315fb1448862f12c4e92e7d0f5e0a603a5375` |
| libzip5 | 1.11.3-2 | 62,612 | `efaa26f7a0fd7575427f44cd97d8b72eadd7e0852f0621e29a22685da487c204` |

The bookworm baseline is `ideviceinstaller 1.1.1-1` with options (`--list-apps`, `--install`); Trixie uses subcommands (`list`, `install`). Inspect `--help` and record which form the installed binary takes.

### Helper runtimes and project-side downloads

| ID | Component and version | Source | Integrity | Install path |
|---|---|---|---|---|
| C25 | Python 3 and Pillow | distribution, or `uv` | pin both; record the interpreter path and the Pillow version. 2026-11-24: host Python `3.13.5` in a venv made with `uv venv --python /usr/bin/python3 <root>/python`, then `uv pip install --python <root>/python/bin/python pillow==13.0.0` (set `UV_CACHE_DIR=<root>/cache/uv`) | `<root>/python/bin/python`, recorded as `KMP_IOS_PYTHON` |
| C26 | Node.js `18` or later | distribution | record the version; `v26.13.1` on 2026-11-24 | host path; needs `node` on `PATH` for the archive inspector |
| C08 | JDK `17` or later (Temurin `25.0.4.1+1-LTS` used) | `https://adoptium.net/` or distribution | Unknown for the recorded build; record the JDK path and version. 2026-11-24: preinstalled Temurin `25.0.5.1+2-LTS` at `/opt/temurin-25`, source and digest Unknown | `/opt/temurin-25` or the project JDK |
| C09 | Gradle `9.6.0` wrapper distribution | the project's own wrapper | Unknown; record the distribution digest on first use | project `gradle-home/` |
| C10 | Android SDK | distribution or SDK manager | read only; record the path and version. 2026-11-24: platform-tools `37.0.1`, cmdline-tools `23.0`, build-tools `36.0.0` and `37.0.0`, platforms `android-36` and `android-37.0` | `/opt/android-sdk` |
| C24 | SQLCipher.xcframework `4.20.0` | `https://github.com/sqlcipher/SQLCipher.swift/releases/download/4.20.0/SQLCipher.xcframework.zip` | Fetched by SwiftPM at build time. Release API digest `1505174fe7f8a0fe81d6ebf87a64b17701b500c12a445ef6b68b9159f012d747`, 50,874,674 bytes, computed locally 2026-11-24; not compared with a SwiftPM download | SwiftPM cache |

The agent build needs `javac --release 17` only, so any JDK 17 or later compiles it; the KMP build itself needs the project's JDK. No Gradle command runs during setup: C09 and C24 are preconditions recorded for the build skill.

## 5. Values marked Unknown

These are the unresolved values. Do not guess one; resolve it at first download and record what you saw.

Still Unknown:

1. JDK `25.0.4.1` download source and digest (C08); the preinstalled `25.0.5.1+2` JDK has the same gap. Gradle `9.6.0` distribution digest (C09); setup runs no Gradle.
2. Host `usbmuxd` and `socat` package versions (C22); a container cannot read the host's package database.
3. The Darwin tools archive that `xtool sdk install` fetched (C18): xtool keeps no copy, so it is not compared with the release digest.
4. A SwiftPM download of `SQLCipher.xcframework.zip` (C24) compared with its release digest; setup fetches none.

Resolved on 2026-11-24, computed locally (values in the rows above):

1. zsign `v1.1.3` (C19): asset `zsign-linux-x86_64.tar.gz`, 248,839 bytes, SHA256 from the release API and `SHA256SUMS.txt`; prebuilt, so no build dependencies; dynamic `libcrypto.so.3`, `libstdc++.so.6`, `libz.so.1`, `libzstd.so.1`, glibc symbols up to `GLIBC_2.34`.
2. Trixie device package sizes and SHA256 values (C21).
3. Debian `zip 3.0-13` SHA256 and size (C20).
4. Pillow `13.0.0` (C25); Node.js `v26.13.1` (C26).
5. Xcode XIP exact bytes (C17).
6. Darwin tools `1.1.0` and OpenAppleMacros `1.3.0` release digests (C18); the installed server matches its digest.
7. Android SDK versions (C10); `SQLCipher.xcframework.zip` release digest (C24).

## 6. Components rebuilt from this skill

These cannot be downloaded. They are source in `../scripts/port/`, and they are what makes stock Linux able to produce Apple final binaries.

| Component | Source | Build or install | Result |
|---|---|---|---|
| HostManager Java agent (C05) | `port/agent/ProbeAgent.java`, `ProbeBridge.java`, `IsolatedLoaderCheck.java`, `manifest.mf` | `bash scripts/port/agent/build-agent.sh --konan <KONAN_HOME> --out <root>/agent` | `probe-agent.jar`, `probe-bootstrap.jar` |
| libtool adapter (C06) | `port/libtool-adapter` | `bash scripts/port/install-port.sh` | `<root>/linux-toolchain/bin/libtool` |
| Fat-archive adapter (C07) | `port/inspect-archive.cjs` (248-line gate3 version) and `port/select-slice.cjs` | same command | `<root>/port/inspect-archive.cjs`, `<root>/port/select-slice.cjs` |

The agent inserts one callback before `HostManager()` returns, in JVM memory only: it adds `IOS_ARM64` to the real `LINUX_X64` host map and installs the Xcode override with the Linux tool directory and the empty sysroot. It does not change `os.name` and does not modify compiler jars. The two-jar split keeps Kotlin types out of `premain` and out of Gradle's system classpath; the bootstrap jar is the agent argument.

Build reference sizes on JDK 25 with Kotlin/Native `2.4.20`: `probe-agent.jar` 367,580 bytes, `probe-bootstrap.jar` 3,581 bytes. Temurin `25.0.5.1+2` gave 367,657 and 3,583 bytes with 159 and 3 `jar tf` members on 2026-11-24; jar bytes change with the JDK build and entry timestamps, so the member check is the gate. The build fails when `ProbeAgent.class`, `META-INF/MANIFEST.MF` or the ASM classes are absent.

Qualify the port with the minimal framework probe (SKILL.md step 5). It runs `konanc` only, never Gradle or the application:

```sh
bash scripts/port/probe-framework.sh
```

It writes `<root>/cache/framework-probe/Probe.framework` from one exported Kotlin class and one top-level function, and requires: a regular `!<arch>` binary, one `llvm-ar --format=darwin rcsD` line from the libtool adapter, both methods in `Headers/Probe.h`, the framework module in `Modules/module.modulemap`, `iPhoneOS` in `Info.plist`, and the `inspect-archive.cjs` PASS line. Kotlin/Native `2.4.20` on Linux needs `-Xbinary=enableDebugTransparentStepping=false` for an Apple target: without it the compiler aborts with `DebugInfoC.cpp:96 ... Assertion 'false' failed` (exit 134), with or without `-opt`. A Gradle KMP build needs the same binary option and two more port settings; `kmp-ios-build-linux/references/build.md` section "Gradle settings for the Linux port" lists all three, verified with a Gradle `linkReleaseFrameworkIosArm64` build on 2026-11-24.

`IsolatedLoaderCheck` is the agent control. Compile it with `javac --release 17`, then run it with the compiler jar twice: without the agent and `false` (expect `iosEnabled=false`), and with the agent JVM options and `true` (expect `iosEnabled=true; Apple targets=1`).

Wire the agent into the compiler JVM. Every path starts with `-Dprobe.root=<root>`, and `ProbeAgent` and `ProbeBridge` reject a path outside it:

```sh
JAVA_TOOL_OPTIONS="-XX:-UsePerfData -Djava.io.tmpdir=<root>/tmp -Duser.home=<root>/tmp/home -Dprobe.root=<root> -Dprobe.toolchain=<root>/linux-toolchain -Dprobe.sysroot=<root>/empty-sysroot -javaagent:<root>/agent/probe-agent.jar=<root>/agent/probe-bootstrap.jar"
```

The libtool adapter accepts only the static-archive shape the linker emits: `libtool -D -static -o <out> <inputs> -arch_only arm64`, with optional `-filelist`. It checks every member with `inspect-archive.cjs`, reduces a universal (`FAT_MAGIC`) archive to its baseline ARM64 subtype-0 slice, and runs `llvm-ar --format=darwin rcsD`. That replaces Apple `lipo` and Apple `libtool` together.

Point the compiler at the adapter, and keep the Linux host identity:

```sh
-Xoverride-konan-properties=targetToolchain.linux_x64-ios_arm64=<root>/linux-toolchain;additionalToolsDir.linux_x64=<root>/linux-toolchain
```

`IsolatedLoaderCheck.java` is the control: it builds `HostManager` in a fresh class loader twice and fails if the host is spoofed, if a second Apple target appears, or if the per-loader Xcode override is missing. The run commands are under the probe above.

## 7. Blockers and their fixes

Anticipate each of these before the install that would hit it. Report the blocker as `BLOCK <what>: <reason>; fix: <action>` — never continue silently with a wrong location.

| Blocker | Symptom | Fix |
|---|---|---|
| Root not writable | `mkdir`, `tar` or `install` returns permission denied; root owned by another user or mode 555 | `setup-toolchain-root.sh` reports it and takes the next fallback root. Fix the mode or owner when the existing root is intended; otherwise keep the fallback and record its path. |
| Disk full | `No space left on device` during an extraction of Swift, Kotlin/Native or the SDK | Free space, or pass `--root` to a larger disk-backed path. `--min-free-gib` (default 20) refuses a root before a transfer starts. |
| tmpfs or `/tmp` root | A toolchain vanishes after a reboot; extraction fails near 1 GB | Never select `/tmp`, `/dev/shm` or another tmpfs. Use `${XDG_DATA_HOME:-$HOME/.local/share}` or `$HOME`. The script rejects these paths and reports why. |
| Tool not on `PATH` | `konanc`/`swift`/`xtool`/`zsign` "command not found" in the next project | Re-run `setup-toolchain-root.sh`; it resolves the shim directory, writes the shims, and reports `BLOCK` with the fix when it must add `~/.local/bin` to the profile files. |
| No writable `PATH` directory | Every `PATH` entry is root-owned | The script creates `~/.local/bin`, adds one guarded line to `~/.profile` and `~/.bashrc`, and exports it for the current shell when sourced. |
| Missing Apple input | No `.xip`, or an expired Apple session | Ask the human for the authorized Xcode 27 download from `https://developer.apple.com/download/all/`; record the XIP SHA256. Do not substitute a source or a prebuilt SDK. |
| Unknown checksum | A publisher supplies no digest (zsign, C18, C20, C24) | Record `computed locally:<sha256>` on first download and say so in the handoff; never present it as a publisher check. |
| xtool/SDK version skew | `Darwin SDK is out of date` | Reinstall the shared SDK with the 2.x xtool; keep one SDK per xtool major version. |
| Agent path rejected | `Bounded bootstrap helper jar required` or `Missing bounded path` | Pass `-Dprobe.root=<root>` and keep the agent, toolchain and sysroot inside that root. |
| Archiver input rejected | `Must be a regular native ar archive` or `unsupported universal archive` | Run `install-port.sh` so the adapter and inspector are current, then retry the link; a FAT input is flattened, not passed through. |

## Sources

- Kotlin releases: `https://github.com/JetBrains/kotlin/releases/tag/v2.4.20`
- Kotlin/Native LLVM assets: `https://download.jetbrains.com/kotlin/native/resources/llvm/`
- Swift Linux installation: `https://www.swift.org/install/linux/`
- xtool releases: `https://github.com/xtool-org/xtool/releases`
- Darwin tools: `https://github.com/xtool-org/darwin-tools-linux-llvm/releases/tag/v1.1.0`
- OpenAppleMacros: `https://github.com/xtool-org/OpenAppleMacros/releases/tag/v1.3.0`
- zsign: `https://github.com/zhlynn/zsign/releases/tag/v1.1.3`
- XcodeGen: `https://github.com/yonaskolb/XcodeGen`
- Debian packages: `https://packages.debian.org/bookworm/`, `https://packages.debian.org/trixie/`
