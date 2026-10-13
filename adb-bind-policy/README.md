# Host ADB bind policy

These artifacts target the verified Arch Linux amd64 host, systemd 262, UID 1000
(`syamsudotdev`), rootless Docker with the systemd cgroup v2 driver, and Compose
5.6. Install them on the host, not in the OpenChamber container.

The root-owned BPF programs deny explicit TCP binds to port 5037 for descendants
of `/user.slice/user-1000.slice/user@1000.service/openchamber.slice`.
Both IPv4 and IPv6 are covered. UDP, other TCP ports, outbound connections, and
host ADB outside this slice are unchanged. A denied bind returns `EPERM`.
There is no custom command-guard message. Port-zero allocation is not filtered.
This is not a security boundary against host root or a user who can move/start
containers outside this slice. Existing sockets are not revoked.

## Before installation

Stop any old proxy and remove its independent startup configuration, if present.
The prior inspection found no automatic startup source. Confirm that result.
Keep these artifacts outside the container so that container recreation cannot
remove them. Run the Docker commands below as `syamsudotdev` on the host.

```sh
export XDG_RUNTIME_DIR=/run/user/1000
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
docker context show
docker context inspect
docker info --format '{{.CgroupDriver}} {{.CgroupVersion}}'
docker compose -f /home/syamsudotdev/Projects/openchamber-isolated/compose.yaml config --services
docker compose -f /home/syamsudotdev/Projects/openchamber-isolated/compose.yaml config --volumes
docker compose -f /home/syamsudotdev/Projects/openchamber-isolated/compose.yaml ps -q opencode
# Substitute the existing container ID. These commands do not print environment secrets.
docker inspect --format '{{index .Config.Labels "com.docker.compose.project"}} {{index .Config.Labels "com.docker.compose.project.working_dir"}} {{index .Config.Labels "com.docker.compose.project.config_files"}}' CONTAINER_ID
docker inspect --format '{{range .Mounts}}{{println .Type .Name .Source .Destination}}{{end}}' CONTAINER_ID
systemctl --user show docker.service -p Environment
env | grep '^DOCKER_' || true
```

Confirm `systemd 2`. Confirm that the persisted Docker context reaches the same
rootless daemon without shell-only `DOCKER_HOST` or `DOCKER_CONTEXT` settings.
The managed service deliberately does not assume a Docker socket location.
If environment-only settings are required, stop here and adapt the service to
the verified endpoint before installation. Confirm that `docker.service` is the
installed rootless Docker user unit. If the daemon uses another unit, stop and
adapt the managed unit before installation. Confirm the image
`opencode-local:latest` contains Node.js. Confirm the base service has no other
startup controller, restart policy, or conflicting cgroup setting.
Record the Compose project label and each volume name or bind mount source.
Compare them with the intended base Compose configuration. The managed command
uses the same base file first, with the override second. Confirm that its project
name and mounts match the existing container. Do not recreate with a different
project name or different volumes. Resolve any project-name override before
adoption. Do not print or publish a resolved configuration containing secrets.

The installer refuses existing destinations. It does not edit the base Compose
file, `.env`, Docker context, or existing user configuration. It installs the
slice in `/etc/systemd/user`, owned by root. Only UID 1000 receives enforcement.
Resolve existing destinations by inspection; do not overwrite them blindly.
Check that `/sys/fs/bpf` is mounted as bpffs. If it is not mounted, configure a
persistent host bpffs mount before proceeding. The helper refuses an absent
mount; it does not mount filesystems itself.

## Install dormant artifacts, then record the baseline

Read the scripts, then install the dormant artifacts. The installer does not
enable or start either unit. It reloads unit definitions but leaves the existing
container unchanged. Do not enable the units until the baseline is recorded.

```sh
sudo bash ./adb-bind-policy/install.sh
```

Record the initial container ID, cgroup path, restart policy, host `adb devices`,
and test output. Start the host ADB server outside `openchamber.slice`.
Run the baseline after dormant installation but before policy activation.
The installed slice definition is now available. Confirm that no bind-policy
hooks are attached before the baseline. The disposable test joins the slice
but does not modify the managed container.

```sh
adb start-server
adb devices
systemctl --user start openchamber.slice
sudo bpftool cgroup show /sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/openchamber.slice
docker run --rm --network host --cgroupns=host --cgroup-parent=openchamber.slice \
  -v "$PWD/adb-bind-policy/verify.mjs:/verify.mjs:ro" \
  --entrypoint node opencode-local:latest /verify.mjs baseline
```

Expected baseline: each explicit bind returns `SUCCESS` or `EADDRINUSE`, not
`EPERM`; port-zero binds succeed; outbound ADB returns `OKAY`. An unavailable
IPv6 stack is a failed prerequisite, not a skipped IPv6 enforcement test.
While the policy is absent, run the same command with `enforced` in place of
`baseline`. Record its nonzero exit and non-`EPERM` bind output. This is the
representative missing-hook fault. The enforced test must expose this defect.
Do not perform temporary detachments with a live managed container.

## Enable and adopt (interrupts the existing container)

Enable the units only after baseline and missing-hook defect detection succeed.

```sh
# Optional: permits the user manager and rootless Docker to run without login.
sudo loginctl enable-linger syamsudotdev
sudo systemctl enable openchamber-bind-policy.service openchamber-managed.service
sudo systemctl start openchamber-bind-policy.service
sudo systemctl start openchamber-managed.service
```

Enabling linger changes user-manager lifetime. Record its prior state so rollback
can restore it. The managed unit starts the verified rootless Docker user unit
before Compose runs. If the user manager or Docker cannot start, startup fails
closed. Resolve that failure before starting the managed unit again.
Each managed start activates the slice and verifies both attachments before
Compose runs. It checks the current cgroup, not only a saved inode. Root policy
shutdown stops the managed unit first. User-manager shutdown stops both units.
The helper also requires `populated 0` in the dedicated slice's `cgroup.events`
before cleanup or partial-start rollback. If containers remain, or inspection
fails, it refuses to detach and retains its pins and identity state. A failed
Compose start can leave containers running even when the managed unit is failed.
Inspect the containers and stop them with the same Compose files before retrying
cleanup. Do not treat unit stop ordering as proof that the slice is empty.
The policy has no watcher. The managed unit owns container startup after adoption.
Do not use direct base Compose starts, `docker start`, or another supervisor.
Keep Docker restart policies disabled. Those paths bypass the startup check.
A rootless Docker daemon outage does not automatically restart this oneshot
unit; use `systemctl restart openchamber-managed.service` after daemon recovery.

## Verify and recreate

Repeat the disposable command with `enforced`. Record each exact `EPERM`, both
successful port-zero binds, and the complete outbound ADB `OKAY` response.
Run `adb devices` on the host and compare it with the baseline.

```sh
sudo bpftool cgroup show /sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/openchamber.slice
docker compose -f /home/syamsudotdev/Projects/openchamber-isolated/compose.yaml \
  -f /etc/openchamber-bind-policy/compose.override.yaml ps -q opencode
# Substitute the returned ID below. Confirm restart policy "no" and the slice.
docker inspect --format '{{.HostConfig.RestartPolicy.Name}} {{.HostConfig.CgroupParent}}' CONTAINER_ID
docker exec CONTAINER_ID cat /proc/self/cgroup
sudo systemctl restart openchamber-managed.service
```

Record the new container ID and cgroup path. Repeat the enforced test and host
`adb devices`. To test the actual managed container, copy `verify.mjs` through
`docker exec -i CONTAINER_ID sh -c 'cat > /tmp/verify-bind-policy.mjs' < ./adb-bind-policy/verify.mjs`,
then run `docker exec CONTAINER_ID node /tmp/verify-bind-policy.mjs enforced`.
Remove that file after the test. Repeat after a planned host reboot. Failure
means any missing attachment, wrong slice, unchanged recreation ID, non-`EPERM`
5037 bind, failed unrelated bind, failed ADB response, or unexpected device loss.
Record actual outputs; a successful unit state alone is not enforcement evidence.

## Rollback

Stop the managed container before detaching the policy. Stop commands use the
same override and do not remove volumes. Inspect outputs before continuing.

```sh
sudo systemctl disable --now openchamber-managed.service
sudo systemctl disable --now openchamber-bind-policy.service
sudo bpftool cgroup show /sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/openchamber.slice
```

The helper detaches only the two pinned program IDs it owns. It removes only
their pins and its state file. It refuses to delete unknown bpffs entries.
The root-owned state records the path, inode, and both loaded program IDs before
attachment. Subsequent starts require matching pins and recorded IDs. Unrecorded
pins, lookup errors, and detach errors require inspection; they are not absence.
After an initial load failure, unrecorded pins remain for manual root recovery.
Do not delete or adopt them without establishing their origin and checking that
the slice is empty. If the cgroup has disappeared, cleanup refuses to proceed.
Restore the installed slice with `systemctl --user start openchamber.slice`,
confirm it is empty, then retry `/usr/local/libexec/openchamber-bind-policy stop`
as root. Cleanup inspects the current cgroup for the recorded IDs even if its
inode differs, so a failed start on a recreated slice can still be cleaned safely.
Confirm no owned bind hooks remain. If `ExecStop` failed, do not restart the
original container until you inspect and resolve that failure.
Remove only these installed files after successful shutdown:

```sh
sudo rm /etc/systemd/system/openchamber-managed.service \
  /etc/systemd/system/openchamber-bind-policy.service \
  /etc/systemd/user/openchamber.slice \
  /usr/local/libexec/openchamber-bind-policy \
  /etc/openchamber-bind-policy/deny5037.o \
  /etc/openchamber-bind-policy/compose.override.yaml
sudo rmdir /etc/openchamber-bind-policy
sudo systemctl daemon-reload
systemctl --user daemon-reload
systemctl --user stop openchamber.slice
# Only if rollback must undo the optional linger change:
sudo loginctl disable-linger syamsudotdev
docker compose -f /home/syamsudotdev/Projects/openchamber-isolated/compose.yaml \
  up -d --force-recreate opencode
adb devices
```

Recreation without the override restores the original cgroup placement. Do not
restore the prior proxy. No installation, host attachment, container restart,
or host behavior test was performed while preparing these artifacts.

## Local safety checks

Run `node ./adb-bind-policy/mock-policy-tests.mjs` for the narrow mocked helper
checks. The checks expose representative missing-gate, lookup-error, and identity
faults before testing the restored source. They also test unreadable events,
populated partial-start rollback, and detach failure. They do not establish host
ownership, bpftool compatibility, attachment behavior, or systemd lifecycle
behavior. Host verification remains required.
