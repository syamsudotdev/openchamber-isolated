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

# An exact value carries the release version, for example 25.0.5+8.
temurin_version=${TEMURIN_VERSION:-latest}
versions_file=${IMAGE_VERSIONS_FILE:-/usr/local/share/image-versions.txt}
repository=https://dl.google.com/android/repository

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
trap 'exit 1' HUP INT TERM

download() {
  curl --fail --location --retry 3 --retry-max-time 600 \
    --connect-timeout 15 --max-time 180 --output "$scratch/$1" "$2"
}

# The API returns both the download link and its SHA256.
if [ "$temurin_version" = latest ]; then
  temurin_api='https://api.adoptium.net/v3/assets/latest/25/hotspot?architecture=x64&image_type=jdk&os=linux&vendor=eclipse'
else
  # The release-name endpoint takes the URL-encoded release name.
  temurin_release_name="jdk-$temurin_version"
  temurin_encoded=$(printf '%s' "$temurin_release_name" | sed 's/+/%2B/g')
  temurin_api="https://api.adoptium.net/v3/assets/release_name/eclipse/$temurin_encoded?architecture=x64&image_type=jdk&os=linux&vendor=eclipse"
fi
download temurin.json "$temurin_api"
temurin_fields=$(jq -er '
  [ if type == "array" then .[] | .binary.package else .binaries[] | .package end ]
  | map(select(.link != null and .checksum != null))
  | if length == 1 then .[0] else empty end
  | [.link, .checksum] | @tsv
' "$scratch/temurin.json") || {
  printf 'Unexpected Adoptium API response for Temurin %s\n' "$temurin_version" >&2
  exit 1
}
tab=$(printf '\t')
temurin_url=${temurin_fields%%"$tab"*}
temurin_sha256=${temurin_fields#*"$tab"}
temurin_release=$(jq -er '
  (if type == "array" then .[0] else . end)
  | .release_name
  | select(type == "string" and length > 0)
' "$scratch/temurin.json") || {
  printf 'Adoptium API response has no release name for Temurin %s\n' "$temurin_version" >&2
  exit 1
}

# The repository XML names the latest stable Linux archive and its SHA1.
download repository2-3.xml "$repository/repository2-3.xml"
if ! uv run --no-project python -I - "$scratch/repository2-3.xml" > "$scratch/android-archives" <<'PY'
import sys
import xml.etree.ElementTree as ET

wanted = {"cmdline-tools;latest": "cmdline-tools", "platform-tools": "platform-tools"}
found = {kind: [] for kind in wanted.values()}

try:
    root = ET.parse(sys.argv[1]).getroot()
except (OSError, ET.ParseError) as error:
    sys.exit(f"cannot parse the Android repository XML: {error}")

for package in root.findall("remotePackage"):
    kind = wanted.get(package.get("path", ""))
    if kind is None or package.get("obsolete") == "true":
        continue
    channel = package.find("channelRef")
    if channel is None or channel.get("ref") != "channel-0":
        continue
    revision = package.find("revision")
    parts = []
    for field in ("major", "minor", "micro"):
        value = revision.find(field) if revision is not None else None
        if value is not None and value.text:
            parts.append(value.text)
    version = ".".join(parts)
    for archive in package.findall("archives/archive"):
        host_os = archive.find("host-os")
        if host_os is None or host_os.text != "linux":
            continue
        host_arch = archive.find("host-arch")
        if host_arch is not None and host_arch.text != "x64":
            continue
        complete = archive.find("complete")
        if complete is None:
            continue
        url = complete.find("url")
        checksum = complete.find("checksum")
        if url is None or not url.text or checksum is None or not checksum.text:
            sys.exit(f"entry {package.get('path')} has no Linux URL or checksum")
        if checksum.get("type") != "sha1":
            sys.exit(f"entry {package.get('path')} has no SHA1 checksum")
        found[kind].append((url.text, checksum.text, version))

for kind in ("cmdline-tools", "platform-tools"):
    entries = found[kind]
    if len(entries) != 1:
        sys.exit(f"expected one Linux {kind} archive on channel-0, found {len(entries)}")
    url, checksum, version = entries[0]
    name = url.rsplit("/", 1)[-1] if kind == "cmdline-tools" else version
    if not name:
        sys.exit(f"entry {kind} has no archive name or revision")
    print(f"{kind}\t{url}\t{checksum}\t{name}")
PY
then
  printf '%s\n' 'Cannot resolve the Android SDK packages from repository2-3.xml' >&2
  exit 1
fi

cmdline_url=''
platform_url=''
while IFS= read -r line; do
  kind=${line%%"$tab"*}
  rest=${line#*"$tab"}
  url=${rest%%"$tab"*}
  rest=${rest#*"$tab"}
  checksum=${rest%%"$tab"*}
  name=${rest#*"$tab"}
  case "$kind" in
    cmdline-tools) cmdline_url=$url cmdline_sha1=$checksum cmdline_name=$name ;;
    platform-tools) platform_url=$url platform_sha1=$checksum platform_version=$name ;;
  esac
done < "$scratch/android-archives"
[ -n "${cmdline_url:-}" ] && [ -n "${platform_url:-}" ] || {
  printf '%s\n' 'Android repository XML has no Linux cmdline-tools or platform-tools archive' >&2
  exit 1
}

download jdk.tar.gz "$temurin_url"
printf '%s  %s\n' "$temurin_sha256" "$scratch/jdk.tar.gz" | sha256sum --check --status
download cmdline.zip "$repository/$cmdline_url"
printf '%s  %s\n' "$cmdline_sha1" "$scratch/cmdline.zip" | sha1sum --check --status
download platform.zip "$repository/$platform_url"
printf '%s  %s\n' "$platform_sha1" "$scratch/platform.zip" | sha1sum --check --status

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

# SDK package executables must also be available to the runtime node user.
chmod -R a+rX "$ANDROID_HOME"

mkdir -p "$(dirname "$versions_file")"
{
  printf 'temurin %s\n' "$temurin_release"
  printf 'cmdline-tools %s\n' "$cmdline_name"
  printf 'platform-tools %s\n' "$platform_version"
} >> "$versions_file"

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
