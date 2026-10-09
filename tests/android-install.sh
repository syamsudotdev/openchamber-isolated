#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
installer=${ANDROID_INSTALLER:-$root/install-android.sh}
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
trap 'exit 1' HUP INT TERM
mkdir "$temporary/bin"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
export EVENTS="$temporary/events"
export EXPECTED_JAVA="$temporary/jdk"
export EXPECTED_SDK="$temporary/sdk"
export EXPECTED_CLI="$temporary/cli/bin/android"
export SDK_FIXTURE="$temporary/sdkmanager-fixture"
export SMOKE_FIXTURE="$temporary/smoke-fixture"
export TMPDIR="$temporary/scratch"
export EXPECTED_URLS="$temporary/urls"

# These fixed examples are independent of installer constants.
cat > "$EXPECTED_URLS" <<'EOF'
jdk.tar.gz https://github.com/adoptium/temurin25-binaries/releases/download/jdk-25.0.4.1%2B1/OpenJDK25U-jdk_x64_linux_hotspot_25.0.4.1_1.tar.gz
cmdline.zip https://dl.google.com/android/repository/commandlinetools-linux-16111833_latest.zip
platform.zip https://dl.google.com/android/repository/platform-tools_r37.0.1-linux.zip
android https://dl.google.com/android/cli/latest/linux_x86_64/android
EOF
cat > "$temporary/bin/curl" <<'SH'
#!/bin/sh
set -eu
[ "$1" = --fail ] && [ "$2" = --location ] && [ "$3" = --retry ] && [ "$4" = 3 ] || exit 1
[ "$5" = --retry-max-time ] && [ "$6" = 600 ] && [ "$7" = --connect-timeout ] && [ "$8" = 15 ] || exit 1
[ "$9" = --max-time ] && [ "${10}" = 180 ] && [ "${11}" = --output ] || exit 1
file=${12}; name=${file##*/}
grep -Fx "$name ${13}" "$EXPECTED_URLS" >/dev/null
printf 'curl %s\n' "$name" >> "$EVENTS"
if [ "$name" = android ]; then
  cp "$SMOKE_FIXTURE" "$file"
else
  printf 'fixed artifact: %s\n' "$name" > "$file"
fi
[ "${FAIL_DOWNLOAD:-}" != "$name" ] || exit 22
SH
cat > "$temporary/bin/checksum" <<'SH'
#!/bin/sh
set -eu
[ "$1" = --check ] && [ "$2" = --status ] || exit 1
read -r hash file
name=${file##*/}
case "${0##*/}:$name:$hash" in
  sha256sum:jdk.tar.gz:dbb698396d478e7fa2b1e50f4103324b2a99b90569ee27c33f2261f9215cf41e) ;;
  sha1sum:cmdline.zip:e025545c62a8e64c7559119566a569fb1dec5f60) ;;
  sha1sum:platform.zip:477254aa5f903c15cf51001717bdf347fb6b53e0) ;;
  *) exit 1 ;;
esac
[ "$(cat "$file")" = "fixed artifact: $name" ]
printf 'checksum %s\n' "$name" >> "$EVENTS"
[ "${FAIL_CHECKSUM:-}" != "$name" ] || exit 1
SH
cp "$temporary/bin/checksum" "$temporary/bin/sha256sum"
cp "$temporary/bin/checksum" "$temporary/bin/sha1sum"
cat > "$temporary/bin/tar" <<'SH'
#!/bin/sh
set -eu
[ "$(grep -c '^checksum ' "$EVENTS")" = 3 ]
[ "$1" = -xzf ] && [ "${2##*/}" = jdk.tar.gz ] && [ "$3" = -C ] || exit 1
[ "$4" = "$EXPECTED_JAVA" ] && [ "$5" = --strip-components=1 ] || exit 1
mkdir -p "$4/bin"
cp "$SMOKE_FIXTURE" "$4/bin/java"
cp "$SMOKE_FIXTURE" "$4/bin/javac"
chmod +x "$4/bin/java" "$4/bin/javac"
printf '%s\n' tar >> "$EVENTS"
if [ "${FAIL_EXTRACTION:-}" = tar ]; then
  printf '%s\n' 'failure tar' >> "$EVENTS"
  exit 23
fi
SH
cat > "$temporary/bin/unzip" <<'SH'
#!/bin/sh
set -eu
[ "$(grep -c '^checksum ' "$EVENTS")" = 3 ]
[ "$1" = -q ] && [ "$3" = -d ] || exit 1
case "${2##*/}" in
  cmdline.zip)
    mkdir -p "$4/cmdline-tools/bin"
    cp "$SDK_FIXTURE" "$4/cmdline-tools/bin/sdkmanager"
    cp "$SMOKE_FIXTURE" "$4/cmdline-tools/bin/avdmanager"
    chmod +x "$4/cmdline-tools/bin/"*
    ;;
  platform.zip)
    [ "$4" = "$EXPECTED_SDK" ]
    mkdir -p "$4/platform-tools"
    cp "$SMOKE_FIXTURE" "$4/platform-tools/adb"
    chmod +x "$4/platform-tools/adb"
    ;;
  *) exit 1 ;;
esac
printf 'unzip %s\n' "${2##*/}" >> "$EVENTS"
if [ "${FAIL_EXTRACTION:-}" = "${2##*/}" ]; then
  printf 'failure %s\n' "${2##*/}" >> "$EVENTS"
  exit 24
fi
SH
cat > "$temporary/bin/install" <<'SH'
#!/bin/sh
set -eu
[ "$(grep -c '^checksum ' "$EVENTS")" = 3 ]
[ "$1" = -m ] && [ "$2" = 0755 ] && [ "${3##*/}" = android ] && [ "$4" = "$EXPECTED_CLI" ] || exit 1
cp "$3" "$4"
chmod 0755 "$4"
printf '%s\n' 'install android' >> "$EVENTS"
if [ "${FAIL_INSTALL:-}" = 1 ]; then
  printf '%s\n' 'failure install' >> "$EVENTS"
  exit 25
fi
SH
cat > "$SMOKE_FIXTURE" <<'SH'
#!/bin/sh
set -eu
# Fixed paths and arguments do not come from the production installer.
case "$0:$*" in
  "$EXPECTED_JAVA/bin/java:-version"|"$EXPECTED_JAVA/bin/javac:-version"|"$EXPECTED_CLI:-V"|"$EXPECTED_SDK/platform-tools/adb:version"|"$EXPECTED_SDK/build-tools/37.0.0/aapt2:version") ;;
  *) printf 'Unexpected smoke command: %s %s\n' "$0" "$*" >&2; exit 1 ;;
esac
grep -Fx packages "$EVENTS" >/dev/null
name=${0##*/}
printf 'smoke %s %s\n' "$name" "$*" >> "$EVENTS"
if [ "${FAIL_SMOKE:-}" = "$name" ]; then
  printf 'failure smoke %s\n' "$name" >> "$EVENTS"
  exit 29
fi
SH
cat > "$SDK_FIXTURE" <<'SH'
#!/bin/sh
set -eu
[ "$JAVA_HOME" = "$EXPECTED_JAVA" ]
[ "$ANDROID_HOME" = "$EXPECTED_SDK" ] && [ "$ANDROID_SDK_ROOT" = "$EXPECTED_SDK" ] || exit 1
[ "$1" = "--sdk_root=$EXPECTED_SDK" ]
case "$2" in
  --licenses|--install)
    [ "$(command -v java)" = "$EXPECTED_JAVA/bin/java" ]
    [ "$(command -v javac)" = "$EXPECTED_JAVA/bin/javac" ]
    [ "$(command -v adb)" = "$EXPECTED_SDK/platform-tools/adb" ]
    [ "$(command -v avdmanager)" = "$EXPECTED_SDK/cmdline-tools/latest/bin/avdmanager" ]
    ;;
esac
case "$2" in
  --licenses)
    [ "$#" = 2 ]
    # Three fixed approvals expose an installer that supplies only one answer.
    for approval in 1 2 3; do
      read -r answer || {
        printf 'Missing license approval: %s\n' "$approval" >&2
        exit 9
      }
      [ "$answer" = y ]
      printf 'approval %s\n' "$approval" >> "$EVENTS"
    done
    printf '%s\n' licenses >> "$EVENTS"
    [ "${FAIL_LICENSE:-}" != 1 ] || exit 7
    ;;
  --install)
    [ "$#" = 4 ] && [ "$3" = 'platforms;android-36' ] && [ "$4" = 'build-tools;37.0.0' ] || exit 1
    grep -Fx licenses "$EVENTS" >/dev/null
    printf '%s\n' packages >> "$EVENTS"
    [ "${FAIL_PACKAGES:-}" != 1 ] || exit 8
    mkdir -p "$EXPECTED_SDK/platforms/android-36" "$EXPECTED_SDK/build-tools/37.0.0"
    printf '%s\n' 'fixed API36 platform' > "$EXPECTED_SDK/platforms/android-36/android.jar"
    cp "$SMOKE_FIXTURE" "$EXPECTED_SDK/build-tools/37.0.0/aapt2"
    # Reproduce the SDK package's owner-only execute permission.
    chmod 0744 "$EXPECTED_SDK/build-tools/37.0.0/aapt2"
    # Remove a fixed fixture path to test an actual missing executable.
    case "${MISSING_SMOKE:-}" in
      java|javac) rm "$EXPECTED_JAVA/bin/$MISSING_SMOKE" ;;
      android) rm "$EXPECTED_CLI" ;;
      sdkmanager|avdmanager) rm "$EXPECTED_SDK/cmdline-tools/latest/bin/$MISSING_SMOKE" ;;
      adb) rm "$EXPECTED_SDK/platform-tools/adb" ;;
      aapt2) rm "$EXPECTED_SDK/build-tools/37.0.0/aapt2" ;;
      '') ;;
      *) exit 1 ;;
    esac
    ;;
  --version)
    [ "$#" = 2 ]
    grep -Fx packages "$EVENTS" >/dev/null
    printf 'smoke sdkmanager %s\n' "$*" >> "$EVENTS"
    if [ "${FAIL_SMOKE:-}" = sdkmanager ]; then
      printf '%s\n' 'failure smoke sdkmanager' >> "$EVENTS"
      exit 29
    fi
    ;;
  *) exit 1 ;;
esac
SH
chmod +x "$temporary/bin/"*
export PATH="$temporary/bin:$PATH"
export TARGETARCH=amd64 JAVA_HOME="$EXPECTED_JAVA" ANDROID_HOME="$EXPECTED_SDK" ANDROID_SDK_ROOT="$EXPECTED_SDK" ANDROID_CLI_BIN="$EXPECTED_CLI"

reset_case() {
  rm -rf "$EXPECTED_JAVA" "$EXPECTED_SDK" "$temporary/cli" "$TMPDIR"
  mkdir "$TMPDIR"
  : > "$EVENTS"
  unset FAIL_DOWNLOAD FAIL_CHECKSUM FAIL_LICENSE FAIL_PACKAGES FAIL_EXTRACTION FAIL_INSTALL FAIL_SMOKE MISSING_SMOKE
}
check_cleanup() { [ "$(ls -A "$TMPDIR")" = '' ] || fail 'scratch files remain'; }
check_no_install() {
  [ ! -e "$EXPECTED_JAVA" ] && [ ! -e "$EXPECTED_SDK" ] && [ ! -e "$EXPECTED_CLI" ] || fail 'installed before verification'
}
expect_failure() {
  if sh "$installer" > "$temporary/error" 2>&1; then fail 'expected installer failure'; fi
  check_cleanup
}

reset_case
sh "$installer"
for executable in "$JAVA_HOME/bin/java" "$JAVA_HOME/bin/javac" "$EXPECTED_CLI" "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" "$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager" "$ANDROID_HOME/platform-tools/adb" "$ANDROID_HOME/build-tools/37.0.0/aapt2"; do
  [ -x "$executable" ] || fail "missing executable: $executable"
done
[ "$(stat -c %a "$ANDROID_HOME/build-tools/37.0.0/aapt2")" = 755 ] || fail 'aapt2 must be executable by non-owner users without added write permission'
[ -z "$(find "$ANDROID_HOME" -type d ! -perm -0005 -print)" ] || fail 'SDK directories must be readable and traversable by non-owner users'
[ -z "$(find "$ANDROID_HOME" -type f ! -perm -0004 -print)" ] || fail 'SDK files must be readable by non-owner users'
[ -z "$(find "$ANDROID_HOME" -perm -0002 -print)" ] || fail 'SDK must not be writable by other users'
cmp "$JAVA_HOME/bin/java" "$SMOKE_FIXTURE" || fail 'wrong JDK layout'
cmp "$EXPECTED_CLI" "$SMOKE_FIXTURE" || fail 'wrong CLI artifact'
[ "$(cat "$ANDROID_HOME/platforms/android-36/android.jar")" = 'fixed API36 platform' ] || fail 'wrong platform'
[ "$(grep -c '^curl ' "$EVENTS")" = 4 ] || fail 'wrong artifact count'
[ "$(grep -c '^packages$' "$EVENTS")" = 1 ] || fail 'missing packages'
[ "$(grep -c '^approval ' "$EVENTS")" = 3 ] || fail 'missing license approvals'
cat > "$temporary/expected-smoke" <<EOF
smoke java -version
smoke javac -version
smoke android -V
smoke sdkmanager --sdk_root=$EXPECTED_SDK --version
smoke adb version
smoke aapt2 version
EOF
grep '^smoke ' "$EVENTS" > "$temporary/actual-smoke" || fail 'missing executable smoke checks'
cmp "$temporary/expected-smoke" "$temporary/actual-smoke" || fail 'wrong executable smoke checks'
check_cleanup

for command in java javac android sdkmanager adb aapt2; do
  reset_case
  export FAIL_SMOKE="$command"
  expect_failure
  [ "$(tail -n 1 "$EVENTS")" = "failure smoke $command" ] || fail 'continued after failed smoke command'
done
for command in java javac android sdkmanager avdmanager adb aapt2; do
  reset_case
  export MISSING_SMOKE="$command"
  expect_failure
done

for asset in jdk.tar.gz cmdline.zip platform.zip; do
  reset_case
  export FAIL_CHECKSUM="$asset"
  expect_failure
  check_no_install
done
for asset in jdk.tar.gz android; do
  reset_case
  export FAIL_DOWNLOAD="$asset"
  expect_failure
  check_no_install
done

for extraction in tar cmdline.zip platform.zip; do
  reset_case
  export FAIL_EXTRACTION="$extraction"
  expect_failure
  grep -Fx "failure $extraction" "$EVENTS" >/dev/null || fail 'extraction failure mode not reached'
  if grep -Fx licenses "$EVENTS" >/dev/null; then fail 'accepted licenses after extraction failure'; fi
done

reset_case
export FAIL_INSTALL=1
expect_failure
grep -Fx 'failure install' "$EVENTS" >/dev/null || fail 'installation failure mode not reached'
if grep -Fx licenses "$EVENTS" >/dev/null; then fail 'accepted licenses after installation failure'; fi

reset_case
export FAIL_LICENSE=1
expect_failure
grep -F 'Android SDK license acceptance failed' "$temporary/error" >/dev/null || fail 'missing license failure message'
if grep -Fx packages "$EVENTS" >/dev/null; then fail 'installed packages after license failure'; fi

reset_case
export FAIL_PACKAGES=1
expect_failure
grep -F 'Android SDK package installation failed' "$temporary/error" >/dev/null || fail 'missing package failure message'

reset_case
export TARGETARCH=arm64
expect_failure
grep -F 'Unsupported Android architecture: arm64' "$temporary/error" >/dev/null || fail 'missing architecture error'
[ ! -s "$EVENTS" ] || fail 'unsupported architecture reached network'
check_no_install

reset_case
export TARGETARCH=amd64 ANDROID_SDK_ROOT="$temporary/different-sdk"
expect_failure
grep -F 'ANDROID_HOME and ANDROID_SDK_ROOT must be identical' "$temporary/error" >/dev/null || fail 'missing SDK root error'
[ ! -s "$EVENTS" ] || fail 'mismatched SDK roots reached network'
check_no_install

printf '%s\n' 'PASS: Android installer tests'
