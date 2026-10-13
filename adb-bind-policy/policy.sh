#!/usr/bin/bash
set -euo pipefail
shopt -s nullglob dotglob

readonly expected=/user.slice/user-1000.slice/user@1000.service/openchamber.slice
readonly cg=/sys/fs/cgroup$expected
readonly pins=/sys/fs/bpf/openchamber-bind-policy
readonly state=/run/openchamber-bind-policy.state
readonly object=/etc/openchamber-bind-policy/deny5037.o

die() { printf '%s\n' "$*" >&2; exit 1; }
userctl() {
    runuser -u syamsudotdev -- env XDG_RUNTIME_DIR=/run/user/1000 \
        DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
        systemctl --user "$@"
}
root_only_writable() {
    local path=$1 mode
    [[ -e $path && ! -L $path && $(stat -c %u "$path") == 0 ]] || return 1
    mode=$(stat -c %a "$path") || return 1
    (( (8#$mode & 0022) == 0 ))
}
program_id() {
    local first rest listing
    listing=$(bpftool prog show pinned "$pins/$1") || return 2
    read -r first rest <<< "$listing"
    [[ $first =~ ^[1-9][0-9]*:$ ]] || return 2
    printf '%s\n' "${first%:}"
}
attached() {
    local wanted=$1 kind=$2 id type rest listing found=no header=no
    listing=$(bpftool cgroup show "$cg") || return 2
    [[ -z ${listing//[[:space:]]/} ]] && return 1
    while read -r id type rest; do
        if [[ $id == ID && $type == AttachType && $header == no ]]; then
            header=yes
            continue
        fi
        [[ -z $id ]] && continue
        [[ $header == yes && $id =~ ^[1-9][0-9]*$ && -n $type ]] || return 2
        if [[ $id == "$wanted" ]]; then
            if [[ $type == "$kind" ||
                  ( $kind == bind4 && $type == cgroup_inet4_bind ) ||
                  ( $kind == bind6 && $type == cgroup_inet6_bind ) ]]; then
                found=yes
            fi
        fi
    done <<< "$listing"
    [[ $header == yes ]] || return 2
    [[ $found == yes ]] && return 0
    return 1
}
check_cgroup() {
    [[ -d $cg && ! -L $cg && $(readlink -f "$cg") == "$cg" ]]
}
empty_slice() {
    local line key value extra populated=unknown
    local -a events
    check_cgroup || { echo 'Cannot inspect the dedicated cgroup.' >&2; return 1; }
    mapfile -t events < "$cg/cgroup.events" || { echo 'Cannot read cgroup.events.' >&2; return 1; }
    for line in "${events[@]}"; do
        read -r key value extra <<< "$line"
        if [[ $key == populated ]]; then
            [[ $populated == unknown && -z $extra && $value =~ ^[01]$ ]] || return 1
            populated=$value
        fi
    done
    [[ $populated == 0 ]] || { echo 'Slice is populated or its populated state is unknown; retaining protection and records.' >&2; return 1; }
}
check_pins() {
    local entry
    root_only_writable "$pins" && [[ -d $pins && $(stat -c %a "$pins") == 700 ]] || die 'Invalid pin directory.'
    for entry in "$pins"/*; do
        [[ $entry == "$pins/deny_bind4" || $entry == "$pins/deny_bind6" ]] || die 'Unknown pin directory entry; retaining all records.'
        root_only_writable "$entry" || die 'Invalid program pin ownership or permissions.'
    done
}
read_identity() {
    local -a saved
    root_only_writable "$state" && [[ -f $state && $(stat -c %a "$state") == 600 ]] || die 'Missing or invalid identity state; refusing existing pins.'
    mapfile -t saved < "$state"
    [[ ${#saved[@]} == 4 && ${saved[0]} == "$expected" &&
       ${saved[1]} =~ ^[1-9][0-9]*$ && ${saved[2]} =~ ^[1-9][0-9]*$ &&
       ${saved[3]} =~ ^[1-9][0-9]*$ && ${saved[2]} != "${saved[3]}" ]] || die 'Invalid identity state.'
    saved_inode=${saved[1]}
    id4=${saved[2]}
    id6=${saved[3]}
    check_pins
    [[ $(program_id deny_bind4) == "$id4" && $(program_id deny_bind6) == "$id6" ]] || die 'Pinned IDs differ from the recorded IDs; retaining all records.'
}
write_identity() {
    local inode=$1 temporary
    umask 077
    temporary=$(mktemp /run/openchamber-bind-policy.state.XXXXXX)
    printf '%s\n%s\n%s\n%s\n' "$expected" "$inode" "$id4" "$id6" > "$temporary"
    mv -T -- "$temporary" "$state"
}
attach_if_absent() {
    local id=$1 kind=$2 status
    if attached "$id" "$kind"; then return 0; else status=$?; fi
    [[ $status == 1 ]] || die "Cannot inspect $kind attachments; refusing startup."
    bpftool cgroup attach "$cg" "$kind" pinned "$pins/deny_$kind" multi
    if [[ $kind == bind4 ]]; then new4=yes; else new6=yes; fi
}
detach_if_present() {
    local id=$1 kind=$2 status
    if attached "$id" "$kind"; then
        empty_slice || return 1
        bpftool cgroup detach "$cg" "$kind" pinned "$pins/deny_$kind" || return 1
    else
        status=$?
        [[ $status == 1 ]] || { echo "Cannot inspect $kind attachments; retaining records." >&2; return 1; }
    fi
}
rollback_new() {
    empty_slice || return 1
    [[ $(stat -c %i "$cg") == "$current_inode" ]] || return 1
    if [[ $new6 == yes ]]; then detach_if_present "$id6" bind6 || return 1; fi
    if [[ $new4 == yes ]]; then detach_if_present "$id4" bind4 || return 1; fi
}
rollback() {
    local code=$?
    trap - EXIT
    if (( code != 0 )) && [[ $new4 == yes || $new6 == yes ]]; then
        if ! rollback_new; then
            echo 'Partial-start rollback failed or was unsafe. Protection, pins, and identity state are retained. Stop all slice containers before recovery.' >&2
        fi
    fi
    exit "$code"
}

[[ $EUID == 0 ]] || die 'Run this helper as root.'
[[ $(id -u syamsudotdev) == 1000 ]] || die 'Unexpected host user UID.'
[[ $(stat -f -c %T /sys/fs/cgroup) == cgroup2fs ]] || die 'cgroup v2 is required.'
[[ $(stat -f -c %T /sys/fs/bpf) == bpf_fs ]] || die 'Mount bpffs at /sys/fs/bpf first.'
for parent in /sys /sys/fs /sys/fs/bpf /run; do
    root_only_writable "$parent" || die "Unsafe parent ownership or permissions: $parent"
done

case ${1:-} in
start)
    userctl start openchamber.slice
    actual=$(userctl show openchamber.slice -p ControlGroup --value)
    [[ $actual == "$expected" ]] && check_cgroup || die 'Unexpected slice cgroup.'
    current_inode=$(stat -c %i "$cg")
    for path in /etc /etc/openchamber-bind-policy "$object"; do
        root_only_writable "$path" || die "Unsafe object ownership or permissions: $path"
    done
    [[ -f $object ]] || die 'BPF object is missing.'
    if [[ -e $pins || -L $pins || -e $state || -L $state ]]; then
        read_identity
    else
        umask 077
        mkdir -m 0700 "$pins"
        # A failed load can leave pins whose identity is not established. Keep
        # them for root inspection; never adopt or delete them automatically.
        bpftool prog loadall "$object" "$pins" || die 'BPF load failed. Unrecorded pins are retained; manual root recovery is required.'
        check_pins
        id4=$(program_id deny_bind4) || die 'Cannot identify loaded bind4 program; retaining pins.'
        id6=$(program_id deny_bind6) || die 'Cannot identify loaded bind6 program; retaining pins.'
        [[ $id4 != "$id6" ]] || die 'Loaded program IDs are not distinct.'
        # Persist identity before the first attachment, including failed starts.
        write_identity "$current_inode"
    fi
    new4=no
    new6=no
    trap rollback EXIT
    attach_if_absent "$id4" bind4
    attach_if_absent "$id6" bind6
    attached "$id4" bind4 && attached "$id6" bind6 || die 'Cannot verify both bind hooks.'
    write_identity "$current_inode"
    trap - EXIT
    ;;
stop)
    # Ordering alone cannot prove that Compose stopped every slice process.
    # Even an absent cgroup is an inspection failure, not permission to clean.
    empty_slice || die 'Cleanup refused; all pins and state are retained.'
    if [[ ! -e $pins && ! -L $pins && ! -e $state && ! -L $state ]]; then exit 0; fi
    read_identity
    # Inspect the current inode even if a failed restart retained an older inode
    # in the state. The recorded IDs, not inode equality, identify owned hooks.
    detach_if_present "$id4" bind4 || die 'bind4 cleanup failed; retaining pins and identity state.'
    empty_slice || die 'bind6 cleanup refused; retaining pins and identity state.'
    detach_if_present "$id6" bind6 || die 'bind6 cleanup failed; retaining pins and identity state.'
    # Recheck before pin removal. Unknown directory entries were rejected above.
    empty_slice || die 'Pin cleanup refused; retaining pins and identity state.'
    rm -- "$pins/deny_bind4" "$pins/deny_bind6"
    rmdir -- "$pins"
    rm -- "$state"
    ;;
*) die 'Usage: openchamber-bind-policy start|stop' ;;
esac
