#!/usr/bin/bash
set -euo pipefail
[[ $EUID == 0 ]] || { echo 'Run this installer as root.' >&2; exit 1; }
src=$(cd -- "$(dirname -- "$0")" && pwd)
dest=/etc/openchamber-bind-policy
for path in "$dest" /usr/local/libexec/openchamber-bind-policy \
    /etc/systemd/user/openchamber.slice \
    /etc/systemd/system/openchamber-bind-policy.service \
    /etc/systemd/system/openchamber-managed.service; do
    [[ ! -e $path && ! -L $path ]] || { echo "Refusing existing destination: $path" >&2; exit 1; }
done
[[ $(id -u syamsudotdev) == 1000 ]]
command -v clang >/dev/null
command -v bpftool >/dev/null
# Compile before creating installation destinations. Arch provides /usr/include/asm.
build=$(mktemp -d)
trap 'rm -f "$build/deny5037.o"; rmdir "$build"' EXIT
clang -O2 -g -target bpf -I/usr/include -c "$src/deny5037.c" -o "$build/deny5037.o"
install -d -o root -g root -m 0755 "$dest" /usr/local/libexec /etc/systemd/user
install -o root -g root -m 0644 "$build/deny5037.o" "$dest/deny5037.o"
install -o root -g root -m 0644 "$src/compose.override.yaml" "$dest/compose.override.yaml"
install -o root -g root -m 0755 "$src/policy.sh" /usr/local/libexec/openchamber-bind-policy
install -o root -g root -m 0644 "$src/openchamber.slice" /etc/systemd/user/openchamber.slice
for unit in openchamber-bind-policy.service openchamber-managed.service; do
    install -o root -g root -m 0644 "$src/$unit" "/etc/systemd/system/$unit"
done
systemctl daemon-reload
runuser -u syamsudotdev -- env XDG_RUNTIME_DIR=/run/user/1000 \
    DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus systemctl --user daemon-reload
echo 'Installed dormant units. No unit was enabled, and no container was started or restarted. Follow README.md for baseline verification and adoption.'
