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

The approved [ADB bind policy](adb-bind-policy/README.md) uses cgroup BPF, a kernel program attached to a process group, to reject container binds to port `5037` while allowing outbound ADB connections. This optional startup path is specific to host user `syamsudotdev`, UID `1000`, and checkout `/home/syamsudotdev/Projects/openchamber-isolated`. A separate checkout at `/workspace/personals/openchamber-isolated` does not change those host settings.

Before adoption, stop and disable the old user Compose service if it is enabled. Do not stop an already protected container merely to repeat setup. Avoid two startup controllers. After adoption, start or restart only through the root systemd `openchamber-managed.service`; direct Docker Compose or user-service startup bypasses policy attachment.

The installer is dormant: it does not enable the managed service. Follow the policy README to run the tests, then explicitly enable the service after verification. Host checks confirmed `EPERM` for explicit IPv4 and IPv6 binds to `5037`, `SUCCESS` for other binds, outbound ADB `OKAY`, and protection after container recreation. Reboot behavior remains untested.

## Run in Docker Sandboxes

[Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) runs a workload in a microVM, a small virtual machine with its own kernel. The `sbx` command-line tool controls the sandboxes. The kit descriptor `openchamber-isolated.yaml` replaces Compose for this path. The kit builds the `sandbox` stage of the `Dockerfile`.

Status: no step in this section ran on a host with `sbx`. Test each step on your own machine first. The [unverified statements](#unverified-statements) list the open points.

### Sandbox Requirements

- `sbx` 0.47.0 or later. The kit uses the `long-running@1` capability.
- A Linux x86-64 host (Ubuntu 24.04 or later, KVM on, your user in the `kvm` group) or a Windows 11 x64 host. See [Install Docker Sandboxes](https://docs.docker.com/ai/sandboxes/install/).
- A Docker account for `sbx login`.

macOS on Apple silicon is not supported. `sbx` builds the kit for the host platform, and the image accepts only `linux/amd64`.

### Differences from Compose

| Compose setting | Sandbox equivalent |
| --- | --- |
| `read_only`, `cap_drop`, `no-new-privileges`, `pids_limit` | None. The microVM boundary protects the host instead. |
| `cpus`, `mem_limit` | Kit request of 8 CPUs and 16 GB. `sbx create --cpus` and `--memory` override it. |
| `network_mode: host`, port `3000` | Kit port `3000`. The host side binds `127.0.0.1` on a port that `sbx` selects. |
| `./config`, `./data` bind mounts | Sandbox volumes at `~/.config/opencode`, `~/.config/openchamber`, and `~/.local/share/opencode`. They remain after `sbx rm`. |
| `opencode-home` and `android-sdk` volumes, `./cache` | The sandbox disk. It remains after `sbx stop` and is deleted by `sbx rm`. |
| `./workspace` | An optional workspace path. `sbx` mounts it at the same absolute path. |
| `ios-signing`, `ios-artifacts`, `ios_p12_password` secret | Files that you copy with `sbx cp`. |
| usbmux relay, host ADB server, ADB bind policy | Not available. |

The user is `agent` with home `/home/agent`, because Docker Sandboxes requires that account. The link `/home/node` points to `/home/agent`, so the bundled configuration paths stay valid.

### Install and Sign In

1. Install `sbx` on Linux:
   ```bash
   curl -fsSL https://get.docker.com | sudo REPO_ONLY=1 sh && sudo apt install docker-sbx
   ```
   On Windows, run `winget install -h Docker.sbx`.
2. Sign in:
   ```bash
   sbx login
   ```
3. Set the network preset. This command works only before a preset is set:
   ```bash
   sbx policy init balanced
   ```

### Create the Sandbox

1. Enter the repository directory.
2. Put the UI password in the shell environment:
   ```bash
   read -rs OPENCHAMBER_UI_PASSWORD && export OPENCHAMBER_UI_PASSWORD
   ```
3. Create the sandbox. Replace `~/Projects/my-app` with your project, or remove it for a sandbox without a workspace:
   ```bash
   sbx create --name openchamber -e OPENCHAMBER_UI_PASSWORD "$PWD" ~/Projects/my-app
   ```
   The first creation builds the image in the `sbx-kit-builder` sandbox. Build downloads use the network of that builder, not the kit network rules. Expect a duration similar to `docker compose build`.
4. Add `--cpus <count>` and `--memory <size>`, such as `--memory 12g`, when the host cannot give 8 CPUs and 16 GB. The default root disk is 20 GB. To make it larger, set `DOCKER_SANDBOXES_ROOT_SIZE=40g` before `sbx create`.
5. Start the sandbox:
   ```bash
   sbx start openchamber
   ```

A startup hook seeds the bundled configuration and starts OpenChamber at each boot. Its output goes to `/home/agent/.cache/openchamber.log`.

The sandbox can read the password value. Do not use a password that you use elsewhere.

### Open the User Interface

1. Find the host port:
   ```bash
   sbx port ls openchamber
   ```
2. Open `http://127.0.0.1:<host-port>` in a browser on the same host.
3. If the page does not load, read the log:
   ```bash
   sbx exec openchamber -- tail -n 50 /home/agent/.cache/openchamber.log
   ```

To open a shell in the sandbox, run `sbx run --name openchamber`. Use this shell for steps such as `claude auth login` and `gh auth login`.

### Allow Network Hosts

The kit allows these hosts at run time: `opencode.ai`, `models.dev`, `registry.npmjs.org`, `api.anthropic.com`, `mcp.atlassian.com`, `github.com`, and `api.github.com`. The `balanced` preset allows more hosts.

1. Show the blocked requests:
   ```bash
   sbx policy log
   ```
2. Allow a host for this sandbox only:
   ```bash
   sbx policy allow network --sandbox openchamber <host>
   ```

### Copy iOS Signing Files

Do these steps only if you sign iOS apps in the sandbox. Run them from the repository directory on the host.

1. Create the directories:
   ```bash
   sbx exec openchamber -- install -d -m 700 /home/agent/ios-signing /home/agent/ios-artifacts
   ```
2. Copy each file. Use one command for each file:
   ```bash
   sbx cp ios-signing/p12-password openchamber:/home/agent/ios-signing/p12-password
   sbx cp ios-signing/<name>.p12 openchamber:/home/agent/ios-signing/<name>.p12
   sbx cp ios-signing/<name>.mobileprovision openchamber:/home/agent/ios-signing/<name>.mobileprovision
   ```
3. Set the file modes:
   ```bash
   sbx exec openchamber -- sh -c 'chmod 600 /home/agent/ios-signing/*'
   ```

`sbx cp` keeps the numeric owner of the host file on Linux and macOS. The `agent` user has UID 1000. If your host UID is not 1000, step 3 fails and the agent cannot read the files. Files copied from Windows belong to `root`.

In the sandbox, read the password as `-passin file:/home/agent/ios-signing/p12-password`. The sandbox has no `/run/secrets/ios_p12_password` file.

Copy a result to the host:

```bash
sbx cp openchamber:/home/agent/ios-artifacts/<name>.ipa ./ios-artifacts/
```

The sandbox cannot install an app on a device, because it has no usbmux relay.

### Stop, Update, and Remove

```bash
sbx stop openchamber
sbx start openchamber
```

`sbx start` runs the startup hook again, so OpenChamber starts again.

To use a changed `Dockerfile`, remove the sandbox and create it again with the same name and kit path. The three volumes attach again when the sandbox name, the kit source, and the volume path match:

```bash
sbx rm openchamber
```

`sbx rm` deletes the sandbox disk, including the Android SDK changes, the Gradle cache, and the iOS files. To delete the volumes too, find them with `sbx volume ls`.

### Unverified Statements

1. The kit lookup in a directory that also contains `compose.yaml`. The descriptor uses the name of the repository directory, `openchamber-isolated`. If your checkout uses another directory name, the lookup can fail.
2. Java trust of the sandbox proxy certificate authority. The image points Node.js, curl, and Python to `/etc/ssl/certs/ca-certificates.crt`. Java uses its own trust store, so Gradle and `sdkmanager` downloads can fail.
3. The ownership of new volume roots. A startup hook gives them to `agent`.
4. The hosts that OpenCode providers and the `claude` login need beyond the kit list.

## Directory Layout

```text
cache/        Persistent OpenCode plugin and package cache
config/       OpenCode configuration
data/         Persistent OpenCode data
ios-signing/                  iOS signing inputs (not tracked)
ios-artifacts/                Signed IPAs and build evidence (not tracked)
workspace/                    OpenCode workspace
Dockerfile                    Container image definition
compose.yaml                  Container runtime configuration
openchamber-isolated.yaml     Docker Sandboxes kit descriptor
entrypoint.sh                 Container startup script
bootstrap/opencode/           Bundled agents, skills, and nested assets
bootstrap/gradle/             Bundled Gradle user settings and init scripts
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
- `OPENCHAMBER_PORT` (default `3000`; set a different port for each instance on the same host, because Compose uses host networking)
- `FIGMA_API_KEY` (optional; add it to `.env` for the Figma integration; defaults to an empty value)
- `ALIBABA99_BASE_URL` (optional; the OpenAI-compatible endpoint of the `alibaba99` provider in `opencode.jsonc`; defaults to an empty value)
- `OPENCODE_CACHE`
- `OPENCODE_WORKSPACE`
- `OPENCODE_CONFIG`
- `OPENCODE_DATA`
- `OPENCODE_PIDS_LIMIT`
- `OPENCODE_MEMORY`
- `OPENCODE_CPUS`
- `OPENCODE_TMP_SIZE`
- `OPENCODE_RUN_SIZE`
- `IOS_SIGNING_DIR` (default `./ios-signing`)
- `IOS_ARTIFACTS_DIR` (default `./ios-artifacts`)
- `IOS_P12_PASSWORD_FILE` (default `./ios-signing/p12-password`)

Do not store credentials in this repository.

### iOS Signing and Device Access

Compose mounts the host usbmux relay directory `~/.local/share/usbmux-relay` at `/run/usbmux-relay` and sets `USBMUXD_SOCKET_ADDRESS=UNIX:/run/usbmux-relay/usbmuxd`. The host must provide the relay socket in that directory.

Compose also mounts these host directories. They persist across container replacement and `docker compose down -v`. Git ignores them, and they stay outside `/workspace`:

- `IOS_SIGNING_DIR` at `/home/node/ios-signing`, read-only: the `.p12`, the provisioning profiles, and the password file.
- `IOS_ARTIFACTS_DIR` at `/home/node/ios-artifacts`, writable: signed IPAs and build evidence.

Compose provides the `.p12` password as the file secret `/run/secrets/ios_p12_password` from `IOS_P12_PASSWORD_FILE`. The container does not start when this file is missing. Without Swarm, Compose bind-mounts the host file read-only and ignores the long-syntax `uid`, `gid`, and `mode` options. Give each path the container `node` owner from the [UID/GID mapping](#uidgid-mapping-setup) calculation. The commands use the example value `100999`:

```bash
sudo install -d -o 100999 -g 100999 -m 700 ios-signing ios-artifacts
sudo install -o 100999 -g 100999 -m 600 /dev/null ios-signing/p12-password
read -rs PW && printf '%s' "$PW" | sudo tee ios-signing/p12-password >/dev/null; unset PW
```

`tee` writes into the existing file, so the file never has a wider mode.

Put the `.p12` and the profiles in `ios-signing/` with the same owner and mode `600`. Then recreate the container.

Read the password only as `openssl … -passin file:/run/secrets/ios_p12_password`. Do not put it in an environment variable, `.env`, or `-passin env:`, because every process inherits the environment and `docker inspect` shows it. The agent user `node` can read the password file. The file only removes the need to supply the password for each session; an OpenChamber secret card remains a fallback. Keep the decrypted key on the `/tmp` `tmpfs`, inside the one guarded signing command.

### Bundled OpenCode Configuration

The image bundles root `opencode.jsonc` and the files in `bootstrap/opencode/`. The bundle includes agents, skills, and their nested assets. Startup copies missing files recursively into `OPENCODE_CONFIG_DIR`.

The bundled `opencode.jsonc` adds the remote Atlassian MCP server and the local Figma MCP server (`figma-developer-mcp@0.13.2` through `npx`, with `FIGMA_API_KEY`). The Atlassian server asks for sign-in at runtime. It also loads the `agent-formal-verify@0.4.12` plugin and defines the OpenAI-compatible `alibaba99` provider, whose `baseURL` comes from `ALIBABA99_BASE_URL`. Connect the provider key at runtime. The bundled `oh-my-opencode-slim.json` selects the `claude` preset by default and keeps the `openai` preset.

The bundled skills are grouped in context folders under `skills/`: `agent-workflow`, `android`, `apple`, `code-quality`, `formal-methods`, `kotlin-footguns`, `ui-design`, and `writing`. OpenCode 2.4.1 finds a skill in any folder up to six levels below `skills/` and uses the name of the folder that holds `SKILL.md` as the skill name, so the group folder does not change a skill name. A group folder must not contain its own `SKILL.md`. Keep each `*-footguns` skill in the same folder as `footgun-scan`, because `footgun-scan/scripts/scan.py` finds trap files in its sibling folders.

Startup preserves every existing destination. It does not replace user files, directories, or file symlinks, including dangling symlinks. A directory symlink or a file that blocks a required directory stops startup with an error. Startup does not follow destination directory symlinks. Do not change configuration paths concurrently with startup.

Rebuilding changes the image bundle. It does not replace existing files in mounted configuration. New bundled files are added on the next startup. To adopt an updated bundled file, back up the mounted file and remove only that file before startup. The next startup copies the image version.

Edits to the live skills in `config/skills/` do not return to `bootstrap/opencode/skills/`. To track a changed skill, compare and copy it on the host, then review and commit the result:

```bash
diff -ru bootstrap/opencode/skills/<group>/<name> config/skills/<group>/<name>
cp -R config/skills/<group>/<name>/. bootstrap/opencode/skills/<group>/<name>/
```

A configuration volume from an image before the grouped layout keeps its flat `skills/<name>/` folders, and the next startup adds the grouped copies next to them. Two folders then give the same skill name. Before the first startup with the grouped layout, back up `config/skills/` on the host and remove its flat skill folders. Keep the group folders and any skill that you added yourself:

```bash
cp -a config/skills config/skills.backup
for d in config/skills/*/; do n=$(basename "$d"); [ -f "$d/SKILL.md" ] && [ -n "$(find bootstrap/opencode/skills -mindepth 2 -maxdepth 2 -type d -name "$n")" ] && rm -rf -- "$d"; done
```

The loop keeps flat skill folders that the bundle no longer contains, such as the removed Matt Pocock and `ponytail` skills. Remove them by hand if you do not use them. Also update absolute paths in local files that point to a flat skill folder, such as `skills/footgun-scan/` in `agents/reviewer.md`. The bundled `agents/reviewer.md` uses `skills/kotlin-footguns/footgun-scan/`.

`OPENCODE_BOOTSTRAP_DIR` can override the source directory for isolated tests. Its default is `/opt/bootstrap/opencode`. Use only a trusted source directory. Bundled symlinks and special files are not supported.

Startup also copies missing files from `bootstrap/gradle/` into the Gradle user home, `GRADLE_USER_HOME` or `/home/node/.gradle` by default, with the same preservation rules. `GRADLE_BOOTSTRAP_DIR` overrides the source directory; its default is `/opt/bootstrap/gradle`. The bundled `gradle.properties` limits the Gradle daemon to 10 GB of heap, the Kotlin daemon to 4 GB, and Gradle to two workers, within the default 20 GB Compose memory limit. It sets `java.io.tmpdir` to `/home/node/.cache/opencode-runtime/tmp`, because `/tmp` is a 1 GB `tmpfs`; startup creates that directory. The bundled `init.d/test-forks.gradle` runs tests in up to two forks at a time and restarts each fork after every 20 test classes. Adjust or remove the files in the Gradle user home to change these limits.

The image sets `LANG=C.UTF-8` and `LC_ALL=C.UTF-8`.

The bundle excludes secrets and provider authentication state. Configure provider authentication in persistent application storage at runtime. Do not copy host credentials into the image. The bundled skills are a snapshot, not proof of their original authorship, license, or current upstream version. Verify uncertain provenance and license terms before redistribution.

The bundled `rtk` skill wraps the `RTK.md` instructions that `rtk init -g` generates in RTK OSS 1.0.0. RTK does not install an OpenCode skill itself; for OpenCode it installs only the plugin.

Known snapshot limitations remain. The vendored codemap script mishandles `.gitignore` negation rules. This preexisting snapshot issue is not fixed here.

### Bundled Command-Line Tools

The image uses Node.js 26 LTS on Debian 13 (trixie) through `node:26-trixie-slim`. The tag names the Debian release, so a later Debian release does not change the base without an edit. The image pins OpenChamber 2.8.0 (`@openchamber/web`) and OpenCode 2.4.1 (`@opencode/cli`). Each build installs the latest npm releases of Playwright and Quint (`@informalsystems/quint`). The build arguments `PLAYWRIGHT_VERSION` and `QUINT_VERSION` default to `latest`; an exact value in `--build-arg QUINT_VERSION=<version>` selects that version. npm verifies each package against the registry integrity hash. The build records each installed version in `/usr/local/share/image-versions.txt` and prints that file. The build requires Node >=24.14.0 before npm installation. The npm install allows the install scripts of `@opencode/cli` and `node-pty` explicitly through `--allow-scripts`.

The system Python is 3.13 on Debian 13. A virtual environment created with the Debian 12 system Python 3.11, such as a `uv tool` environment, does not work after an upgrade from a Debian 12 image. Recreate it, for example with `uv tool install --reinstall <tool>`. Libraries that were extracted from Debian 12 packages into the home volume can also fail; install the matching Debian 13 package instead. The image installs the latest releases of `uv` and `uvx`, RTK OSS, `fff-mcp`, GitHub CLI `gh`, `gitleaks`, Claude Code `claude`, `actionlint`, `sops`, `cosign`, and Maestro in `/usr/local/bin`. Maestro uses `/opt/maestro` and the link `/usr/local/bin/maestro`. The image also installs the Debian packages `age`, `shellcheck`, and `librsvg2-bin`, which provides `rsvg-convert`. `install-tools.sh` supports release assets for Docker `TARGETARCH=amd64` or `arm64`, but the complete image accepts only `amd64` because of the Android SDK. The variables `UV_VERSION`, `RTK_VERSION`, `FFF_VERSION`, `GH_VERSION`, `GITLEAKS_VERSION`, `CLAUDE_VERSION`, `ACTIONLINT_VERSION`, `SOPS_VERSION`, `COSIGN_VERSION`, and `MAESTRO_VERSION` default to `latest`; an exact value without a leading `v` selects that release.

The installer resolves `latest` through the `https://github.com/<repository>/releases/latest` redirect, not the rate-limited GitHub API. Claude Code has no GitHub release; the installer reads the version from `https://downloads.claude.ai/claude-code-releases/latest`. The installer downloads the checksum data that each release publishes: `uv-<target>.tar.gz.sha256`, RTK `checksums.txt`, `fff-mcp-<target>.sha256`, the `gh` and `gitleaks` `*_checksums.txt` files, the Claude Code `manifest.json`, the `actionlint`, `sops`, and `cosign` checksum files, and the Maestro `checksums_sha256.txt`. It verifies every download against the line or manifest value for its exact asset name before extraction or installation. A missing checksum file, a missing or duplicate line, or a mismatch stops the build. The checksum files come from the same release as the downloads, so they detect damaged downloads but not a compromised release. The installer appends each resolved version to `/usr/local/share/image-versions.txt`. Debian records the `age`, `shellcheck`, and `librsvg2-bin` package versions in that file. RTK uses the `rtk-oss` release assets under the Apache License 2.0, not the commercial edition. The image retains the archive's `LICENSE` at `/usr/local/share/licenses/rtk/LICENSE` with mode `0644`. The build checks that `rtk hook opencode --help` succeeds. This help check does not install a hook or modify user configuration. The bundled `rtk` skill and `plugins/rtk.ts` come from RTK OSS 1.0.0 and do not change when a build installs a newer RTK. The image retains the `gh` archive's `LICENSE` at `/usr/local/share/licenses/gh/LICENSE` with mode `0644`. The image does not contain GitHub authentication. Run `gh auth login` at runtime; `gh` stores its state in `/home/node/.config/gh` in the home volume. The image retains the `gitleaks` archive's `LICENSE` at `/usr/local/share/licenses/gitleaks/LICENSE` with mode `0644`. It retains the `actionlint` archive's `LICENSE.txt` at `/usr/local/share/licenses/actionlint/LICENSE.txt` with mode `0644`. The `sops` and `cosign` downloads are raw binaries with no license file in the release asset, like `fff-mcp`. Claude Code is proprietary and has no license file. The Maestro archive has no license file. The image sets `DISABLE_AUTOUPDATER=1`, because `/usr/local` is read-only at runtime and the installed Claude Code cannot replace itself. Maestro needs Java 17 or later; the image installs Temurin 25 later in the build.

The image installs the Playwright command-line tool through npm. The build runs `playwright install --with-deps chromium`, which installs the Chromium system libraries and the Chromium, Chromium headless shell, and FFmpeg builds of that Playwright version (approximately 680 MB for Playwright 1.64.1) into `PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright`. `/usr/local/bin/chromium` links to that Chromium, and `CHROME_PATH` names the link. `image-versions.txt` records the Chromium version. The root file system is read-only at runtime, so `playwright install` cannot add browser builds. A project must use the Playwright version in `image-versions.txt` to find a browser build. A project with another Playwright version must pass `executablePath: process.env.CHROME_PATH` when it launches Chromium. Chromium in the container needs `--no-sandbox`; Playwright adds it by default. The system libraries make an `LD_LIBRARY_PATH` setting unnecessary. A rebuild installs the latest Playwright and its browser build.

The image installs the Quint command-line tool `quint` through npm in `/usr/local/bin`. The build does not allow the install script of its `protobufjs` dependency; `quint typecheck` and `quint run` work without it. On first use, `quint run` downloads the Quint Rust evaluator and `quint verify` downloads Apalache into `/home/node/.quint` in the home volume. These downloads require network access. Apalache uses the bundled Java.

The bundled `bootstrap/opencode/plugins/rtk.ts` uses the official released RTK OpenCode V2 plugin. Startup preserves an existing mounted `plugins/rtk.ts`; rebuilding alone does not replace it. On the host, back up that mounted file before you explicitly replace it with the bundled version, or remove only that file to let startup copy the bundled version. Then restart through the existing startup controller. If the ADB bind policy is active, follow its managed restart procedure and use only `openchamber-managed.service`. Do not bypass the policy with a direct Compose restart. The upgrade does not automatically overwrite the plugin or modify user configuration. No RTK-specific Compose change is required.

The bundled configuration loads `oh-my-opencode-slim` without a version pin, so each fresh download can get a newer release. The `claude` preset uses the `claude-agent/opus` and `claude-agent/sonnet` models of OpenCode's built-in Claude Agent provider. Its `explorer` and `fixer` use `opencode-go/deepseek-v4.1-flash`, which requires the OpenCode Go provider. The Claude Agent provider runs the `claude` CLI with its own login: run `claude auth login`, then connect **Claude Agent** under Providers. These model IDs are Claude Code aliases, so they move to a newer model when Claude Code updates. The image sets `CLAUDE_CODE_ENTRYPOINT=opencode-claude`, because the Agent SDK otherwise sends `sdk-ts`, and `sdk-*` labels use the 5-hour limit faster ([anthropics/claude-code#97074](https://github.com/anthropics/claude-code/issues/97074)). Compose also sets that value. Startup does not replace an existing `opencode.jsonc` or `oh-my-opencode-slim.json`; remove an old `/opt/opencode-claude` `plugins` entry and change old `claude-code/` models by hand. OpenCode still downloads `oh-my-opencode-slim` at runtime. Plugin transitive dependencies and other runtime downloads can change and require network access. Other optional tools mentioned by skills are not installed unless listed here. Plannotator is not installed.

### Java and Android Tools

The image preinstalls these tools through `install-android.sh`:

| Tool | Version or SDK package | Location |
| --- | --- | --- |
| Eclipse Temurin JDK | Latest Java 25 release, or `TEMURIN_VERSION` | `/opt/temurin-25` |
| Official Android CLI | Mutable `latest` | `/opt/android-cli/bin/android` |
| Android command-line tools | Latest stable | `/opt/android-sdk/cmdline-tools/latest` |
| Android platform-tools | Latest stable | `/opt/android-sdk/platform-tools` |
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

The installer reads Temurin's download link and SHA256 from the Adoptium API: `assets/latest/25/hotspot` for `latest`, or `assets/release_name/eclipse/jdk-<TEMURIN_VERSION>` for an exact value such as `25.0.5+8`. It reads the URLs and SHA1 checksums of the latest stable (`channel-0`) Linux command-line tools and platform-tools from Google's `repository2-3.xml`. It verifies each archive before it creates any destination, and it appends the resolved versions to `/usr/local/share/image-versions.txt`. The Android CLI uses the official mutable `latest` download and has no official immutable digest for this baseline. `platforms;android-36` selects an API level, not a fixed package revision. Its revision can change between builds. These downloads prevent full reproducibility.

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

`init: true` runs Docker's init process as PID 1. It reaps ended child processes, so zombie processes do not fill `pids_limit`.

The root filesystem remains read-only. Docker named volumes make `/home/node` and `/opt/android-sdk` writable. The container uses temporary filesystems for `/tmp` and `/run`. Other `/opt` tools remain read-only. It uses bind mounts for the plugin cache, workspace, OpenCode configuration, and OpenCode data. The plugin cache and SDK volume permit downloaded code to run.

## Update Versions

The `Dockerfile` pins OpenCode and OpenChamber to exact versions:

```dockerfile
ARG OPENCODE_VERSION=2.4.1
ARG OPENCHAMBER_VERSION=2.8.0
```

Each build installs the latest release of each other tool. A cached Docker layer keeps the versions of an earlier build, and the `node:26-trixie-slim` tag can move to a newer base. Rebuild without the cache and with the newest base:

```bash
docker compose build --pull --no-cache
```

To select an exact version of one tool, pass its build argument, for example `docker compose build --no-cache --build-arg UV_VERSION=0.13.8`. Each of these arguments defaults to `latest`:

| Build argument | Tool |
| --- | --- |
| `PLAYWRIGHT_VERSION` | Playwright and its Chromium build |
| `QUINT_VERSION` | `@informalsystems/quint` |
| `UV_VERSION` | `uv` and `uvx` |
| `RTK_VERSION` | RTK OSS |
| `FFF_VERSION` | `fff-mcp` |
| `GH_VERSION` | GitHub CLI `gh` |
| `GITLEAKS_VERSION` | `gitleaks` |
| `CLAUDE_VERSION` | Claude Code `claude` |
| `ACTIONLINT_VERSION` | `actionlint` |
| `SOPS_VERSION` | `sops` |
| `COSIGN_VERSION` | `cosign` |
| `MAESTRO_VERSION` | Maestro |
| `TEMURIN_VERSION` | Eclipse Temurin 25 JDK, such as `25.0.5+8` |

The Android command-line tools and platform-tools always use the latest stable entries of Google's SDK repository. `platforms;android-36` and `build-tools;37.0.0` stay fixed, because they are a project SDK choice. The build records every resolved version in `/usr/local/share/image-versions.txt`.

Builds are not fully reproducible: two builds on different days can install different versions of the tools that use `latest`. A new release can also break the build or the runtime. Builds require network access. The host network configuration still controls connectivity and exposure; container restrictions do not make network services private.

The `Update versions` workflow runs daily at 20:00 in `America/Los_Angeles` and on a manual `workflow_dispatch` run from `main`. Each run does these steps in this order:

1. `scripts/update-versions.mjs` checks npm `latest` for exact stable `@opencode/cli` and `@openchamber/web` versions. It rejects downgrades, invalid metadata, and inconsistent pins before it changes files. It changes only the two `Dockerfile` pins and their README references.
2. The workflow builds a `linux/amd64` image with `--pull --no-cache`. Every run builds the image, also when no pin changes, so the run also checks the tools that use `latest`.
3. The workflow writes `image-versions.txt` to the job summary.
4. The workflow compares the installed `@opencode/cli` and `@openchamber/web` versions with the `Dockerfile` pins.
5. The workflow runs `tests/android-runtime.sh` against the image.
6. If a pin changed, the workflow commits only `Dockerfile` and `README.md` and pushes to `main` with `GITHUB_TOKEN`. Repository rules must permit this push.

A run without a pin change creates no commit. A failure in any step prevents the push. A concurrent change to `main` after the final fetch causes a normal non-fast-forward push rejection; the workflow never forces a push. The commit message records the changed packages, their old and new versions, and official release links. Missing or minimal release notes produce a comparison link marked `Release notes unavailable`. GitHub API errors other than a missing release stop the update.

GitHub runs scheduled workflows only from the default branch. Keep `main` as the default branch. Scheduled runs can be delayed or dropped under load. GitHub can disable scheduled workflows in public repositories after 60 days without repository activity. Check the Actions page if the runs stop.

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
```

The tests use temporary configuration, data, and cache directories. They use a stub `openchamber` command and fixed example contents. They do not validate Docker builds or the running applications.

The installer tests use download, checksum, extraction, and installation stubs. They check fixed release URLs and checksums for both architectures, RTK and `actionlint` license extraction and installation, license contents and permissions, unsupported architectures, checksum rejection, the Claude Code version and manifest lookup, Maestro archive extraction and linking, latest and exact version selection, and failed-download cleanup. They do not download or execute release binaries or write to live `/usr/local`. The plugin tests use a fake RTK process; they do not execute the live RTK binary.

Build the local image:

```bash
docker compose build
```

Build and test a disposable Android runtime image:

```bash
docker build --platform linux/amd64 --target openchamber -t openchamber-verify .
sh tests/android-runtime.sh
```

The last `Dockerfile` stage, `sandbox`, is for Docker Sandboxes. Pass `--target openchamber` to every direct `docker build` of the Compose image. Compose and the `Update versions` workflow select that target. The Dockerfile defaults `TARGETARCH` to `amd64` for legacy builders. No `--progress` option is required. To test another image, pass its exact name as the first argument:

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
