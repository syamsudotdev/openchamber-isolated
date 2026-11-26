#!/usr/bin/env bash
# Make the arm64 slice of libGoogleConversionTracking.a linkable with ld64.lld: its
# "private external" l<digits> symbols become local. Output: <gate>/gen/.
# Usage: bash localize-act.sh <GATE> <LLVM bin folder> <APP_SOURCES>
set -euo pipefail
G=${1:?gate}; B=${2:?llvm bin}; APP=${3:?app source folder}
A="$G/src/$APP/Common/Third Parties/ACTReporter/libGoogleConversionTracking.a"
T=$G/tmp/act; rm -rf "$T"; mkdir -p "$T/m" "$G/gen"
python3 -I - "$A" "$T/arm64.a" <<'EOF'
import struct, sys
src, out = sys.argv[1:]
b = open(src, "rb").read()
magic, n = struct.unpack(">II", b[:8])
assert magic == 0xCAFEBABE, "not a fat archive"
for i in range(n):
    c, s, off, size, _ = struct.unpack(">iiIII", b[8 + 20 * i : 28 + 20 * i])
    if c & 0xFFFFFFFF == 0x0100000C and s & 0xFFFFFF == 0:
        open(out, "wb").write(b[off : off + size])
        break
else:
    raise SystemExit("no arm64 slice")
EOF
cd "$T/m"
"$B/llvm-ar" t ../arm64.a > ../order.txt
"$B/llvm-ar" x ../arm64.a
while IFS= read -r o; do "$B/llvm-objcopy" --wildcard --localize-symbol='l[0-9]*' "$o"; done < ../order.txt
rm -f "$G/gen/libGoogleConversionTracking.a"
xargs -d '\n' "$B/llvm-ar" rcs "$G/gen/libGoogleConversionTracking.a" < ../order.txt
left=$("$B/llvm-nm" -m "$G/gen/libGoogleConversionTracking.a" | grep -cE 'private external l[0-9]+$' || true)
[ "$left" -eq 0 ] || { echo "private-external l-symbols left: $left" >&2; exit 1; }
sha256sum "$G/gen/libGoogleConversionTracking.a"
