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

## Security Model

The Compose service keeps these controls:

```yaml
read_only: true
cap_drop:
  - ALL
security_opt:
  - no-new-privileges:true
```

The root filesystem remains read-only. A Docker named volume makes `/home/node` writable. The container uses temporary filesystems for `/tmp` and `/run`. It uses bind mounts for the plugin cache, workspace, OpenCode configuration, and OpenCode data. The plugin cache permits downloaded plugin code to run.

## Update Versions

Change these build arguments in `Dockerfile`:

```dockerfile
ARG OPENCODE_VERSION=2.0.18
ARG OPENCHAMBER_VERSION=2.0.3
```

Then rebuild the image:

```bash
docker compose build --no-cache
```

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

Build the local image:

```bash
docker compose build
```

Open a shell without the normal entry point:

```bash
docker compose run --rm --entrypoint sh opencode
```

## License

This project uses the MIT License.

## Acknowledgements

This project uses OpenChamber and OpenCode.
