# Isolated OpenChamber

Isolated OpenChamber runs OpenChamber and OpenCode in a restricted Docker container. The container uses a read-only root filesystem and limited Linux permissions.

## Features

- Runs OpenChamber and OpenCode in one container.
- Uses a read-only root filesystem.
- Drops all Linux capabilities.
- Prevents privilege escalation.
- Limits CPU, memory, and process use.
- Keeps the workspace, home directory, configuration, and application data outside the image.

## Requirements

Install these tools:

- Docker Engine
- Docker Compose

Use a Linux host for the documented user-namespace procedure.

The image supports `linux/amd64` only. The build rejects other architectures before tool downloads. Full Android SDK support on `linux/arm64` is unverified.

## Quick Start

Clone the repository. Then enter the project directory.

Create the bind-mount directories:

```bash
mkdir -p cache config data workspace
```

Create the local environment file:

```bash
cp .env.example .env
```

Set a strong `OPENCHAMBER_UI_PASSWORD` value in `.env`. Git ignores this file.

Build the image:

```bash
docker compose build
```

Complete the UID/GID setup before you start the container.

## UID/GID Mapping Setup

Docker user-namespace remapping changes how container user IDs map to host user IDs. A host directory can appear as `root:root` in the container even when your host user owns it.

Inspect the container user and the namespace maps:

```bash
docker compose run --rm --entrypoint sh opencode -lc \
  'id; echo UID_MAP; cat /proc/self/uid_map; echo GID_MAP; cat /proc/self/gid_map'
```

Example output:

```text
uid=1000(node) gid=1000(node)
         0       1000          1
         1     100000      65536
```

Use this calculation for the example container UID:

```text
host UID = host range start + container UID - container range start
host UID = 100000 + 1000 - 1
host UID = 100999
```

Use the same calculation for the GID. Set the bind-mount ownership with the calculated values:

```bash
sudo chown -R 100999:100999 cache config data workspace
```

Inspect the mapping on each Docker host. Do not assume that all hosts use `100999`.

## Run the Container

Use this direct startup path only on hosts without the optional [ADB bind policy](adb-bind-policy/README.md). After adoption, use only the root systemd `openchamber-managed.service` to start or restart the container.

Set `OPENCHAMBER_UI_PASSWORD` in `.env`. Then run the service:

```bash
docker compose up
```

Do not use `OPENCHAMBER_ALLOW_UNAUTHENTICATED_LAN=true` on an untrusted network.

## Optional systemd User Service

Use this user service only on hosts without the optional ADB bind policy. Do not run the user service and the managed root service as two controllers of the same container.

The example user service starts Docker Compose and a Cloudflare tunnel. It does not require a root system service.

Copy the example:

```bash
mkdir -p ~/.config/systemd/user
cp openchamber.service.example ~/.config/systemd/user/openchamber.service
```

Edit `~/.config/systemd/user/openchamber.service`. Set `WorkingDirectory` to this repository when it is not at `%h/Projects/openchamber-isolated`. Replace `replace-with-your-tunnel-id` with your Cloudflare tunnel ID.

Reload systemd and start the service:

```bash
systemctl --user daemon-reload
systemctl --user enable --now openchamber.service
```

Inspect the service:

```bash
systemctl --user status openchamber.service
docker compose ps
```

Remove the optional service:

```bash
systemctl --user disable --now openchamber.service
rm ~/.config/systemd/user/openchamber.service
systemctl --user daemon-reload
```

## Optional Host ADB Bind Policy

Compose uses host networking. Reserve host TCP port `5037` for the host ADB server; the container must not bind that port.

The approved [ADB bind policy](adb-bind-policy/README.md) uses cgroup BPF, a kernel program attached to a process group, to reject container binds to port `5037` while allowing outbound ADB connections. This optional startup path is specific to host user `syamsudotdev`, UID `1000`, and checkout `/home/syamsudotdev/Projects/openchamber-isolated`. A separate checkout at `/workspace/openchamber-isolated` does not change those host settings.

Before adoption, stop and disable the old user Compose service if it is enabled. Do not stop an already protected container merely to repeat setup. Avoid two startup controllers. After adoption, start or restart only through the root systemd `openchamber-managed.service`; direct Docker Compose or user-service startup bypasses policy attachment.

The installer is dormant: it does not enable the managed service. Follow the policy README to run the tests, then explicitly enable the service after verification. Host checks confirmed `EPERM` for explicit IPv4 and IPv6 binds to `5037`, `SUCCESS` for other binds, outbound ADB `OKAY`, and protection after container recreation. Reboot behavior remains untested.

## Directory Layout

```text
cache/        Persistent OpenCode plugin and package cache
config/       OpenCode configuration
data/         Persistent OpenCode data
workspace/                    OpenCode workspace
Dockerfile                    Container image definition
compose.yaml                  Container runtime configuration
entrypoint.sh                 Container startup script
bootstrap/opencode/           Bundled agents, skills, and nested assets
opencode.jsonc                Bundled OpenCode configuration
install-android.sh            Java and Android tool installer
tests/bootstrap.sh            Isolated bootstrap tests
tests/android-install.sh      Isolated Android installer tests
tests/android-runtime.sh      Disposable Android runtime checks
openchamber.service.example   Optional systemd user service
adb-bind-policy/              Optional host ADB bind policy and managed service
```

## Writable Home Storage

Docker mounts the `opencode-home` named volume at `/home/node`. The complete container home directory is writable and persists across container replacement.

Docker stores this volume in Docker-managed disk storage. It does not modify your host home directory. Its default size limit is the available space on the filesystem that contains the Docker data directory.

Inspect the volume:

```bash
docker volume inspect openchamber-isolated_opencode-home
```

The nested `cache/`, `config/`, and `data/` bind mounts continue to use the project directories. They override the related paths in the named volume.

This command permanently removes the named home and Android SDK volumes, including runtime-installed SDK packages:

```bash
docker compose down -v
```

## Configuration

The image defines these main paths:

- `OPENCODE_CONFIG_DIR=/home/node/.config/opencode`
- `OPENCODE_DATA_DIR=/home/node/.local/share/opencode`
- `OPENCHAMBER_DATA_DIR=/home/node/.config/openchamber`
- `XDG_CACHE_HOME=/home/node/.cache`

You can set these Compose variables in `.env`:

- `OPENCHAMBER_UI_PASSWORD` (required)
- `FIGMA_API_KEY` (optional; add it to `.env` for the Figma integration; defaults to an empty value)
- `OPENCODE_CACHE`
- `OPENCODE_WORKSPACE`
- `OPENCODE_CONFIG`
- `OPENCODE_DATA`
- `OPENCODE_PIDS_LIMIT`
- `OPENCODE_MEMORY`
- `OPENCODE_CPUS`
- `OPENCODE_TMP_SIZE`
- `OPENCODE_RUN_SIZE`

Do not store credentials in this repository.

### Bundled OpenCode Configuration

The image bundles root `opencode.jsonc` and the files in `bootstrap/opencode/`. The bundle includes agents, skills, and their nested assets. Startup copies missing files recursively into `OPENCODE_CONFIG_DIR`.

The bundled `opencode.jsonc` adds the remote Atlassian MCP server and the local Figma MCP server (`figma-developer-mcp@0.13.2` through `npx`, with `FIGMA_API_KEY`). The Atlassian server asks for sign-in at runtime. The bundled `oh-my-opencode-slim.json` selects the `claude` preset by default and keeps the `openai` preset.

Startup preserves every existing destination. It does not replace user files, directories, or file symlinks, including dangling symlinks. A directory symlink or a file that blocks a required directory stops startup with an error. Startup does not follow destination directory symlinks. Do not change configuration paths concurrently with startup.

Rebuilding changes the image bundle. It does not replace existing files in mounted configuration. New bundled files are added on the next startup. To adopt an updated bundled file, back up the mounted file and remove only that file before startup. The next startup copies the image version.

`OPENCODE_BOOTSTRAP_DIR` can override the source directory for isolated tests. Its default is `/opt/bootstrap/opencode`. Use only a trusted source directory. Bundled symlinks and special files are not supported.

The bundle excludes secrets and provider authentication state. Configure provider authentication in persistent application storage at runtime. Do not copy host credentials into the image. The bundled skills are a snapshot, not proof of their original authorship, license, or current upstream version. Verify uncertain provenance and license terms before redistribution.

The bundled `rtk` skill wraps the `RTK.md` instructions that `rtk init -g` generates in RTK OSS 1.0.0. RTK does not install an OpenCode skill itself; for OpenCode it installs only the plugin.

Known snapshot limitations remain. The vendored codemap script mishandles `.gitignore` negation rules. This preexisting snapshot issue is not fixed here.

### Bundled Command-Line Tools

The image pins OpenChamber 2.5.3 and OpenCode 2.2.1. The build requires Node >=24.14.0 before npm installation. The image installs `uv` and `uvx` 0.12.19, RTK OSS 1.0.0, `fff-mcp` 0.11.0, and GitHub CLI `gh` 2.103.3 in `/usr/local/bin`. `install-tools.sh` supports release assets for Docker `TARGETARCH=amd64` or `arm64`, but the complete image accepts only `amd64` because of the Android SDK. The installer verifies fixed SHA256 checksums before extraction or installation. To update a tool, update its release URL and both architecture checksums together.

The release URLs and checksums came from the respective GitHub release APIs. `uv` 0.12.19 matches the verified host version. RTK uses the `rtk-oss` release assets under the Apache License 2.0, not the commercial edition. The image retains the archive's `LICENSE` at `/usr/local/share/licenses/rtk/LICENSE` with mode `0644`. The build checks that `rtk hook opencode --help` succeeds. This help check does not install a hook or modify user configuration. `fff-mcp` 0.11.0 is a new pinned baseline, not a verified match to the host binary. The `gh` checksums come from the release's `checksums.txt`. The image retains the `gh` archive's `LICENSE` at `/usr/local/share/licenses/gh/LICENSE` with mode `0644`. The image does not contain GitHub authentication. Run `gh auth login` at runtime; `gh` stores its state in `/home/node/.config/gh` in the home volume.

The image installs the Playwright 1.64.1 command-line tool through npm and the Chromium system libraries through `playwright install-deps chromium`. The image does not contain a browser build. A project downloads the browser build for its own Playwright version, such as with `npx playwright install chromium`, into `/home/node/.cache/ms-playwright`. To update the tool, change `ARG PLAYWRIGHT_VERSION` in the `Dockerfile`.

The bundled `bootstrap/opencode/plugins/rtk.ts` uses the official released RTK OpenCode V2 plugin. Startup preserves an existing mounted `plugins/rtk.ts`; rebuilding alone does not replace it. On the host, back up that mounted file before you explicitly replace it with the bundled version, or remove only that file to let startup copy the bundled version. Then restart through the existing startup controller. If the ADB bind policy is active, follow its managed restart procedure and use only `openchamber-managed.service`. Do not bypass the policy with a direct Compose restart. The upgrade does not automatically overwrite the plugin or modify user configuration. No RTK-specific Compose change is required.

The bundled configuration loads `oh-my-opencode-slim` without a version pin, so each fresh download can get a newer release. It pins the `@openchamber/opencode-claude@1.6.0` plugin, which provides the `claude` preset's Claude Code models. Compose sets `CLAUDE_CODE_ENTRYPOINT=opencode-claude`; that plugin passes the value to Claude Code. OpenCode still downloads the plugins at runtime. The image does not contain an offline plugin bundle. Plugin transitive dependencies and other runtime downloads can change and require network access. Other optional tools mentioned by skills are not installed unless listed here. Plannotator is not installed.

### Java and Android Tools

The image preinstalls these tools through `install-android.sh`:

| Tool | Version or SDK package | Location |
| --- | --- | --- |
| Eclipse Temurin JDK | `25.0.4.1+1` | `/opt/temurin-25` |
| Official Android CLI | Mutable `latest` | `/opt/android-cli/bin/android` |
| Android command-line tools | `23.0` | `/opt/android-sdk/cmdline-tools/latest` |
| Android platform-tools | `37.0.1` | `/opt/android-sdk/platform-tools` |
| Android API platform | `platforms;android-36` | `/opt/android-sdk/platforms/android-36` |
| Android build-tools | `build-tools;37.0.0` | `/opt/android-sdk/build-tools/37.0.0` |

`JAVA_HOME=/opt/temurin-25`. Both `ANDROID_HOME` and `ANDROID_SDK_ROOT` equal `/opt/android-sdk`. The image prepends these directories to `PATH`, in this order:

```text
/opt/android-cli/bin
/opt/temurin-25/bin
/opt/android-sdk/cmdline-tools/latest/bin
/opt/android-sdk/platform-tools
/opt/android-sdk/build-tools/37.0.0
```

Building the image accepts the Android SDK licenses through `sdkmanager`. The user explicitly authorized this acceptance. Review the [Android SDK License Agreement](https://developer.android.com/studio/terms) before building or distributing the image.

The command-line tools and platform-tools archives use fixed release URLs and Google's published SHA1 checksums. The Android CLI uses the official mutable `latest` download and has no official immutable digest for this baseline. `platforms;android-36` selects an API level, not a fixed package revision. Its revision can change between builds. These downloads prevent full reproducibility.

Compose mounts the writable `android-sdk` named volume at `/opt/android-sdk`. Docker copies the image SDK contents into a fresh empty volume on first use. The image assigns the SDK to `node:node`, so the seeded volume permits SDK installation and updates as `node` without world-writable permissions. Both Android environment variables continue to point to `/opt/android-sdk`. SDK packages and SDK lock and state files persist across container replacement.

An existing SDK volume masks the image SDK directory, including SDK changes from later image builds. Rebuilding the image does not refresh that volume. Update packages in the volume with SDK `sdkmanager`, or back up needed data and remove the SDK volume before reseeding it from the new image. Deleting the volume loses runtime-installed packages and SDK state. Java, the Android CLI installation, and other `/opt` tools remain on the read-only root filesystem; change the installer and rebuild the image to update them. Emulator, NDK, CMake, AVD configuration, and device authentication data are not bundled.

The official Android CLI download is a binary downloader. This image does not initialize its payload during installation. The first launch with a fresh writable home downloads the payload and requires network access. The tools are not fully preinstalled for offline use. Runtime verification of the writable SDK volume is still required. The CLI cannot update its own read-only installation path in place.

Image construction runs `java -version`, `javac -version`, `android -V`, `sdkmanager --sdk_root=/opt/android-sdk --version`, `adb version`, and `aapt2 version`. It also checks that `avdmanager` is executable. These checks fail the build when a command fails. The `android -V` check is not proof that the CLI works as `node` with mounted home storage and a read-only root filesystem. Disposable image testing is still required.

Java 25 requires a compatible Gradle wrapper and Android build configuration. Do not assume that every Android project can run with this Java version.

The image does not start or configure the host ADB server. Configure the bundled `adb` client for the existing server as needed. Device access depends on that server's connectivity and authorization. With host networking, reserve port `5037` for the host server. See the [optional host ADB bind policy](adb-bind-policy/README.md) to enforce this reservation for the managed container.

## Security Model

The Compose service keeps these controls:

```yaml
read_only: true
cap_drop:
  - ALL
security_opt:
  - no-new-privileges:true
```

The root filesystem remains read-only. Docker named volumes make `/home/node` and `/opt/android-sdk` writable. The container uses temporary filesystems for `/tmp` and `/run`. Other `/opt` tools remain read-only. It uses bind mounts for the plugin cache, workspace, OpenCode configuration, and OpenCode data. The plugin cache and SDK volume permit downloaded code to run.

## Update Versions

The `Update application versions` workflow checks npm `latest` for exact stable `@opencode/cli` and `@openchamber/web` versions. It rejects downgrades, invalid metadata, and inconsistent pins before it changes files. It updates only the Dockerfile pins and their README references. It does not update other tools.

The schedule runs daily at 20:00 in `America/Los_Angeles`. The script uses the local calendar date and runs updates every second day, with 2026-10-21 as an active date. This calendar calculation preserves parity across month, year, and daylight-saving changes. A manual `workflow_dispatch` run bypasses the date gate. Manual runs must select `main`; other branches cannot run the update job. Checkout always selects `main`.

GitHub runs scheduled workflows only from the default branch. Keep `main` as the default branch. Scheduled runs can be delayed or dropped under load. A delayed run uses its actual local execution date; a missed date is not replayed. GitHub can disable scheduled workflows in public repositories after 60 days without repository activity. Check the Actions page if updates stop. Concurrency prevents overlapping runs; GitHub can replace an older pending run with the latest pending run.

When versions change, the workflow runs all five test commands, builds a `linux/amd64` image, and checks the installed package versions in a disposable container without starting services. It commits only `Dockerfile` and `README.md`, then pushes to `main` with `GITHUB_TOKEN`. Repository rules must permit this push. A no-op creates no commit. Validation, test, build, or branch-movement failures prevent the push. A concurrent change after the final fetch causes a normal non-fast-forward push rejection; the workflow never forces a push.

The commit message records only changed packages, their old and new versions, and official release links. Missing releases or minimal release notes produce a comparison link marked `Release notes unavailable`. The script treats notes with fewer than 80 non-whitespace characters, or placeholder notes, as minimal. It does not summarize breaking changes. GitHub API errors other than a missing release stop the update. The message file stays in runner temporary storage, not in Git.

For a manual pin change, keep both README references consistent with each Dockerfile argument:

Change these build arguments in `Dockerfile`:

```dockerfile
ARG OPENCODE_VERSION=2.2.1
ARG OPENCHAMBER_VERSION=2.5.3
```

Then rebuild the image:

```bash
docker compose build --no-cache
```

These package pins do not make the whole image reproducible. The `node:24-bookworm-slim` tag and apt repositories can change. Package dependencies and runtime downloads can also change. Builds require network access. The host network configuration still controls connectivity and exposure; container restrictions do not make network services private.

## Troubleshooting

### Cache Permission Error

Inspect the cache directory:

```bash
docker compose run --rm --entrypoint sh opencode -lc \
  'id; stat -c "%n uid=%u gid=%g mode=%a" /home/node/.cache'
```

The directory must use container UID/GID `1000:1000`. The host `cache/` directory stores this data.

### Bind-Mount Permission Error

Inspect the bind mounts:

```bash
docker compose run --rm --entrypoint sh opencode -lc \
  'stat -c "%n uid=%u gid=%g mode=%a" /workspace /home/node/.config/opencode /home/node/.local/share/opencode'
```

Repeat the UID/GID mapping procedure if these paths use the wrong owner.

### Effective Compose Configuration

Inspect the resolved configuration:

```bash
docker compose config
```

## Development

Run the narrow startup tests without Docker:

```bash
sh tests/bootstrap.sh
sh tests/install-tools.sh
sh tests/android-install.sh
node --test tests/rtk-plugin.mjs
node --test tests/update-versions.mjs
```

The tests use temporary configuration, data, and cache directories. They use a stub `openchamber` command and fixed example contents. They do not validate Docker builds or the running applications.

The installer tests use download, checksum, extraction, and installation stubs. They check fixed release URLs and checksums, RTK license extraction and installation, license contents and permissions, unsupported architectures, checksum rejection, and failed-download cleanup. They do not download or execute release binaries or write to live `/usr/local`. The plugin tests use a fake RTK process; they do not execute the live RTK binary.

Build the local image:

```bash
docker compose build
```

Build and test a disposable Android runtime image:

```bash
docker build --platform linux/amd64 -t openchamber-verify .
sh tests/android-runtime.sh
```

The Dockerfile defaults `TARGETARCH` to `amd64` for legacy builders. No `--progress` option is required. To test another image, pass its exact name as the first argument:

```bash
sh tests/android-runtime.sh opencode-local:latest
```

The runtime test creates a unique disposable named SDK volume and runs two disposable containers with that shared volume. Docker seeds the volume from the image. Both containers use host networking, a read-only root filesystem, user `node`, dropped capabilities, and `no-new-privileges`. The test checks the Android environment paths, SDK and home writes, rejected writes to other `/opt` tool directories, Java, Android CLI startup twice, SDK target listing, ADB and build-tool versions, API 36 files, build-tools 37.0.0, and `android --sdk="$ANDROID_HOME" sdk list`.

The first container checks that the requested packages are missing and runs `android --sdk="$ANDROID_HOME" sdk install build-tools/36.0.0 platforms/android-37.0` directly, without an availability precheck. If an exact package is unavailable, the test surfaces the Android CLI error and fails; it does not substitute another package. The image already contains accepted SDK licenses. The second container checks both installed package artifacts and a marker retained from the first container. It also checks a new SDK write after recreation. Each container uses a fresh anonymous `/home/node` volume, which Docker removes with `--rm`. The script removes the disposable SDK volume on exit.

The test requires Docker, a built image, network access for CLI and SDK downloads, and sufficient Docker storage. It does not start or recreate the Compose service, start OpenChamber, check ADB server connectivity, or verify the optional host ADB bind policy. It does not validate Gradle builds or emulator use. No Docker runtime check for this SDK-volume change ran in the implementation environment because Docker was unavailable.

Open a shell without the normal entry point:

```bash
docker compose run --rm --entrypoint sh opencode
```

## License

This project uses the MIT License.

## Acknowledgements

This project uses OpenChamber and OpenCode.
