"""Make the signing entitlements for one configuration and check them against the profile.

Usage: uv run python -I entitlements.py ENTS XCCONFIG TEAM_ID BUNDLE_ID PROFILE OUTPUT

- Replaces each $(NAME) in ENTS: AppIdentifierPrefix and TeamIdentifierPrefix are
  "<TEAM_ID>.", PRODUCT_BUNDLE_IDENTIFIER is BUNDLE_ID, any other name comes from
  XCCONFIG (`NAME = value` lines, `#include` followed).
- Adds application-identifier, com.apple.developer.team-identifier and get-task-allow.
- Every value must be allowed by the profile's Entitlements (`*` wildcards as Apple
  uses them). Exit 1 lists each value that is not; nothing is dropped silently.
Prints macro names and entitlement keys only: an xcconfig can hold API keys.
"""
import fnmatch
import os
import plistlib
import re
import subprocess
import sys


def read_xcconfig(path, seen=None):
    seen = seen if seen is not None else set()
    values = {}
    path = os.path.realpath(path)
    if path in seen:
        return values
    seen.add(path)
    for line in open(path, encoding="utf-8"):
        line = line.split("//", 1)[0].strip()  # "//" starts a comment in an xcconfig
        include = re.match(r'#include\??\s+"([^"]+)"', line)
        if include:
            child = os.path.join(os.path.dirname(path), include.group(1))
            if os.path.exists(child):
                values.update(read_xcconfig(child, seen))
            continue
        match = re.match(r"([A-Za-z_][A-Za-z0-9_]*)(\[[^\]]*\])?\s*=\s*(.*)$", line)
        if match and not match.group(2):
            values[match.group(1)] = match.group(3).strip()
    return values


def profile_entitlements(path):
    decoded = subprocess.run(
        ["openssl", "cms", "-verify", "-noverify", "-inform", "DER", "-in", path],
        capture_output=True, check=True, env={"PATH": "/usr/bin:/bin"},
    ).stdout
    return plistlib.loads(decoded)["Entitlements"]


def allowed(value, permitted):
    options = permitted if isinstance(permitted, list) else [permitted]
    for option in options:
        if value == option:
            return True
        if isinstance(value, str) and isinstance(option, str) and fnmatch.fnmatchcase(value, option):
            return True
    return False


def main():
    ents, xcconfig, team, bundle, profile, output = sys.argv[1:]
    known = {"AppIdentifierPrefix": f"{team}.", "TeamIdentifierPrefix": f"{team}.",
             "PRODUCT_BUNDLE_IDENTIFIER": bundle}
    settings = read_xcconfig(xcconfig)
    text = open(ents, encoding="utf-8").read()
    used = sorted(set(re.findall(r"\$\(([A-Za-z_][A-Za-z0-9_]*)\)", text)))
    missing = [name for name in used if name not in known and name not in settings]
    if missing:
        sys.exit(f"unresolved macros: {', '.join(missing)}")
    for name in used:
        text = text.replace(f"$({name})", known.get(name, settings.get(name, "")))
    print("resolved macros:", ", ".join(used) or "none")

    entitlements = plistlib.loads(text.encode())
    entitlements["application-identifier"] = f"{team}.{bundle}"
    entitlements["com.apple.developer.team-identifier"] = team
    entitlements["get-task-allow"] = True

    permitted = profile_entitlements(profile)
    problems = []
    for key, value in entitlements.items():
        if key not in permitted:
            problems.append(f"{key}: not in the profile")
            continue
        for item in value if isinstance(value, list) else [value]:
            if not allowed(item, permitted[key]):
                problems.append(f"{key}: a value is not allowed by the profile")
    if problems:
        sys.exit("not allowed by the profile:\n  " + "\n  ".join(problems))
    with open(output, "wb") as handle:
        plistlib.dump(entitlements, handle)
    print(f"entitlements: {len(entitlements)} keys, all allowed by the profile ->", output)


if __name__ == "__main__":
    main()
