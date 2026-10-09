#!/bin/sh
set -eu

[ "${TARGETARCH:-}" = amd64 ] || {
  printf 'Unsupported Android architecture: %s (requires amd64)\n' "${TARGETARCH:-unset}" >&2
  exit 1
}

export JAVA_HOME=${JAVA_HOME:-/opt/temurin-25}
export ANDROID_HOME=${ANDROID_HOME:-/opt/android-sdk}
export ANDROID_SDK_ROOT=${ANDROID_SDK_ROOT:-$ANDROID_HOME}
android_cli=${ANDROID_CLI_BIN:-/opt/android-cli/bin/android}
[ "$ANDROID_HOME" = "$ANDROID_SDK_ROOT" ] || {
  printf '%s\n' 'ANDROID_HOME and ANDROID_SDK_ROOT must be identical' >&2
  exit 1
}

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
trap 'exit 1' HUP INT TERM

download() {
  curl --fail --location --retry 3 --retry-max-time 600 \
    --connect-timeout 15 --max-time 180 --output "$scratch/$1" "$2"
}

download jdk.tar.gz 'https://github.com/adoptium/temurin25-binaries/releases/download/jdk-25.0.4.1%2B1/OpenJDK25U-jdk_x64_linux_hotspot_25.0.4.1_1.tar.gz'
printf '%s  %s\n' dbb698396d478e7fa2b1e50f4103324b2a99b90569ee27c33f2261f9215cf41e "$scratch/jdk.tar.gz" | sha256sum --check --status
download cmdline.zip 'https://dl.google.com/android/repository/commandlinetools-linux-16111833_latest.zip'
printf '%s  %s\n' e025545c62a8e64c7559119566a569fb1dec5f60 "$scratch/cmdline.zip" | sha1sum --check --status
download platform.zip 'https://dl.google.com/android/repository/platform-tools_r37.0.1-linux.zip'
printf '%s  %s\n' 477254aa5f903c15cf51001717bdf347fb6b53e0 "$scratch/platform.zip" | sha1sum --check --status

# Google publishes no immutable digest for the approved mutable CLI URL.
download android 'https://dl.google.com/android/cli/latest/linux_x86_64/android'

# All fixed archives pass verification before any destination is created.
mkdir -p "$JAVA_HOME" "$ANDROID_HOME/cmdline-tools" "$(dirname "$android_cli")" "$scratch/cmdline"
tar -xzf "$scratch/jdk.tar.gz" -C "$JAVA_HOME" --strip-components=1
unzip -q "$scratch/cmdline.zip" -d "$scratch/cmdline"
mv "$scratch/cmdline/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
unzip -q "$scratch/platform.zip" -d "$ANDROID_HOME"
install -m 0755 "$scratch/android" "$android_cli"

export PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/build-tools/37.0.0:$PATH"
sdkmanager=$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager
# A finite input file avoids masking sdkmanager errors or yes SIGPIPE failures.
i=0
while [ "$i" -lt 1000 ]; do
  printf '%s\n' y
  i=$((i + 1))
done > "$scratch/license-answers"
if ! "$sdkmanager" "--sdk_root=$ANDROID_HOME" --licenses < "$scratch/license-answers"; then
  printf '%s\n' 'Android SDK license acceptance failed' >&2
  exit 1
fi
if ! "$sdkmanager" "--sdk_root=$ANDROID_HOME" --install 'platforms;android-36' 'build-tools;37.0.0'; then
  printf '%s\n' 'Android SDK package installation failed' >&2
  exit 1
fi

# These run only during image construction, not during container startup.
"$JAVA_HOME/bin/java" -version
"$JAVA_HOME/bin/javac" -version
"$android_cli" -V
"$sdkmanager" "--sdk_root=$ANDROID_HOME" --version
[ -x "$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager" ] || {
  printf '%s\n' 'Android avdmanager is not executable' >&2
  exit 1
}
"$ANDROID_HOME/platform-tools/adb" version
"$ANDROID_HOME/build-tools/37.0.0/aapt2" version
