#!/bin/sh
set -eu

image=${1:-openchamber-verify}

docker run --rm --platform linux/amd64 --network host \
    --read-only --user node --cap-drop ALL \
    --security-opt no-new-privileges:true \
    --tmpfs /tmp:rw,exec,nosuid,nodev \
    --tmpfs /run:rw,nosuid,nodev \
    --tmpfs /opt/android-sdk/.sdk:rw,nosuid,nodev,uid=1000,gid=1000,mode=0755 \
    -v /home/node --entrypoint /bin/sh "$image" -c '
set -eu
test "$(id -un)" = node
test "$JAVA_HOME" = /opt/temurin-25
test "$ANDROID_HOME" = /opt/android-sdk
test "$ANDROID_SDK_ROOT" = /opt/android-sdk
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
printf "%s\n" "PASS: Android read-only runtime checks"
'
