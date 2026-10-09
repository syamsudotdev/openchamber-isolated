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

Set `OPENCHAMBER_UI_PASSWORD` in `.env`. Then run the service:

```bash
docker compose up
```

Do not use `OPENCHAMBER_ALLOW_UNAUTHENTICATED_LAN=true` on an untrusted network.

## Optional systemd User Service

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
```

## Writable Home Storage

Docker mounts the `opencode-home` named volume at `/home/node`. The complete container home directory is writable and persists across container replacement.

Docker stores this volume in Docker-managed disk storage. It does not modify your host home directory. Its default size limit is the available space on the filesystem that contains the Docker data directory.

Inspect the volume:

```bash
docker volume inspect openchamber-isolated_opencode-home
```

The nested `cache/`, `config/`, and `data/` bind mounts continue to use the project directories. They override the related paths in the named volume.

This command permanently removes the named home volume:

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

Startup preserves every existing destination. It does not replace user files, directories, or file symlinks, including dangling symlinks. A directory symlink or a file that blocks a required directory stops startup with an error. Startup does not follow destination directory symlinks. Do not change configuration paths concurrently with startup.

Rebuilding changes the image bundle. It does not replace existing files in mounted configuration. New bundled files are added on the next startup. To adopt an updated bundled file, back up the mounted file and remove only that file before startup. The next startup copies the image version.

`OPENCODE_BOOTSTRAP_DIR` can override the source directory for isolated tests. Its default is `/opt/bootstrap/opencode`. Use only a trusted source directory. Bundled symlinks and special files are not supported.

The bundle excludes secrets and provider authentication state. Configure provider authentication in persistent application storage at runtime. Do not copy host credentials into the image. The bundled skills are a snapshot, not proof of their original authorship, license, or current upstream version. Verify uncertain provenance and license terms before redistribution.

Known snapshot limitations remain. Bundled `AGENTS.md` requires an `rtk` skill, but no approved source was found. Installing the RTK executable does not provide that skill. The vendored codemap script mishandles `.gitignore` negation rules. This preexisting snapshot issue is not fixed here.

### Bundled Command-Line Tools

The image installs `uv` and `uvx` 0.12.19, RTK 0.23.0, and `fff-mcp` 0.11.0 in `/usr/local/bin`. `install-tools.sh` supports release assets for Docker `TARGETARCH=amd64` or `arm64`, but the complete image accepts only `amd64` because of the Android SDK. The installer verifies fixed SHA256 checksums before extraction or installation. To update a tool, update its release URL and both architecture checksums together.

The release URLs and checksums came from the respective GitHub release APIs. `uv` 0.12.19 matches the verified host version. RTK 0.23.0 meets the plugin minimum; RTK was absent on the inspected host. `fff-mcp` 0.11.0 is a new pinned baseline, not a verified match to the host binary.

The bundled configuration pins `oh-my-opencode-slim@2.2.25`. OpenCode still downloads the plugin at runtime. The image does not contain an offline plugin bundle. Plugin transitive dependencies and other runtime downloads can change and require network access. Other optional tools mentioned by skills are not installed unless listed here. Plannotator is not installed.

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

The SDK packages stay on the read-only image filesystem. Compose mounts only `/opt/android-sdk/.sdk` as writable temporary state with `rw,nosuid,nodev,uid=1000,gid=1000,mode=0755`. The Android CLI needs this directory for its SDK lock and state files. This state does not persist across container replacement. Change the installer and rebuild the image to update Java or SDK packages. Do not install SDK updates into `/opt/android-sdk` at runtime. Emulator, NDK, CMake, AVD configuration, and device authentication data are not bundled.

The official Android CLI download is a binary downloader. This image does not initialize its payload during installation. The first launch with a fresh writable home downloads the payload and requires network access. The tools are not fully preinstalled for offline use. A user-confirmed runtime check passed as `node` with a writable home, a read-only root filesystem, and the writable `.sdk` temporary filesystem. The CLI cannot update an immutable read-only installation path in place.

Image construction runs `java -version`, `javac -version`, `android -V`, `sdkmanager --sdk_root=/opt/android-sdk --version`, `adb version`, and `aapt2 version`. It also checks that `avdmanager` is executable. These checks fail the build when a command fails. The `android -V` check is not proof that the CLI works as `node` with mounted home storage and a read-only root filesystem. Disposable image testing is still required.

Java 25 requires a compatible Gradle wrapper and Android build configuration. Do not assume that every Android project can run with this Java version.

Compose sets `ADB_SERVER_SOCKET=tcp:host.docker.internal:5037` for the existing remote ADB server. The bundled `adb` client uses that endpoint. The image does not start or configure the host ADB server. Device access depends on that server's connectivity and authorization. This feature does not change Compose bindings or the endpoint.

## Security Model

The Compose service keeps these controls:

```yaml
read_only: true
cap_drop:
  - ALL
security_opt:
  - no-new-privileges:true
```

The root filesystem remains read-only. A Docker named volume makes `/home/node` writable. The container uses temporary filesystems for `/tmp`, `/run`, and Android SDK state at `/opt/android-sdk/.sdk`. SDK packages remain read-only. It uses bind mounts for the plugin cache, workspace, OpenCode configuration, and OpenCode data. The plugin cache permits downloaded plugin code to run.

## Update Versions

Change these build arguments in `Dockerfile`:

```dockerfile
ARG OPENCODE_VERSION=2.0.25
ARG OPENCHAMBER_VERSION=2.1.1
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
```

The tests use temporary configuration, data, and cache directories. They use a stub `openchamber` command and fixed example contents. They do not validate Docker builds or the running applications.

The installer tests use download, checksum, extraction, and installation stubs. They check fixed release URLs and checksums, unsupported architectures, checksum rejection, and failed-download cleanup. They do not download or execute release binaries or write to live `/usr/local/bin`.

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

The runtime test uses host networking, a read-only root filesystem, user `node`, dropped capabilities, and the writable `.sdk` state exception. It checks Java, Android CLI startup twice, SDK target listing, ADB and build-tool versions, API 36 files, build-tools 37.0.0, and `android --sdk="$ANDROID_HOME" sdk list`. Each run uses a fresh anonymous `/home/node` volume. Docker removes the volume with `--rm`. The first CLI launch downloads its payload and needs network access. The test does not install SDK packages, start OpenChamber, or check ADB server connectivity.

Open a shell without the normal entry point:

```bash
docker compose run --rm --entrypoint sh opencode
```

## License

This project uses the MIT License.

## Acknowledgements

This project uses OpenChamber and OpenCode.
