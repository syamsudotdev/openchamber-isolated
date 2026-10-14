#!/bin/sh
set -eu

image=${1:-openchamber-verify}
sdk_volume=
cleanup() {
    if [ -n "$sdk_volume" ]; then
        docker volume rm "$sdk_volume" >/dev/null
    fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
sdk_volume=$(docker volume create)

run_checks() {
    docker run --rm --platform linux/amd64 --network host \
    --read-only --user node --cap-drop ALL \
    --security-opt no-new-privileges:true \
    --tmpfs /tmp:rw,exec,nosuid,nodev \
    --tmpfs /run:rw,nosuid,nodev \
    --mount "type=volume,source=$sdk_volume,target=/opt/android-sdk" \
    -v /home/node --entrypoint /bin/sh "$image" -c '
set -eu
test "$(id -un)" = node
test "$JAVA_HOME" = /opt/temurin-25
test "$ANDROID_HOME" = /opt/android-sdk
test "$ANDROID_SDK_ROOT" = /opt/android-sdk
probe=$(mktemp "$ANDROID_HOME/.runtime-write.XXXXXX")
rm "$probe"
probe=$(mktemp /home/node/.runtime-write.XXXXXX)
rm "$probe"
for directory in /opt /opt/bootstrap /opt/temurin-25 /opt/android-cli; do
    if probe=$(mktemp "$directory/.runtime-write.XXXXXX" 2>/dev/null); then
        rm "$probe"
        printf "FAIL: %s must remain read-only\n" "$directory" >&2
        exit 1
    fi
done
java -version
javac -version
android -V
android -V
avdmanager list target -c
adb version
aapt2 version
test -f "$ANDROID_HOME/platforms/android-36/android.jar"
test -d "$ANDROID_HOME/build-tools/37.0.0"
android --sdk="$ANDROID_HOME" sdk list

sdkmanager="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
if [ "$1" = install ]; then
    test ! -e "$ANDROID_HOME/build-tools/36.0.0"
    test ! -e "$ANDROID_HOME/platforms/android-37.0"
    "$sdkmanager" --sdk_root="$ANDROID_HOME" --list > /tmp/sdk-packages.txt
    for package in "build-tools;36.0.0" "platforms;android-37.0"; do
        if ! awk -F "|" -v package="$package" '\''
            /^Available Packages:/ { available = 1; next }
            /^Available Updates:/ { available = 0 }
            available {
                name = $1
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
                if (name == package) found = 1
            }
            END { exit !found }
        '\'' /tmp/sdk-packages.txt; then
            printf "FAIL: exact SDK package unavailable: %s\n" "$package" >&2
            exit 1
        fi
    done
    "$sdkmanager" --sdk_root="$ANDROID_HOME" "build-tools;36.0.0" "platforms;android-37.0"
    printf "%s\n" "android-runtime-persistence" > "$ANDROID_HOME/.runtime-marker"
else
    test "$(cat "$ANDROID_HOME/.runtime-marker")" = android-runtime-persistence
fi
test -x "$ANDROID_HOME/build-tools/36.0.0/aapt2"
test -f "$ANDROID_HOME/build-tools/36.0.0/package.xml"
test -f "$ANDROID_HOME/platforms/android-37.0/android.jar"
test -f "$ANDROID_HOME/platforms/android-37.0/package.xml"
' android-runtime "$1"
}

run_checks install
run_checks verify
printf "%s\n" "PASS: Android writable SDK and container-recreation checks"
