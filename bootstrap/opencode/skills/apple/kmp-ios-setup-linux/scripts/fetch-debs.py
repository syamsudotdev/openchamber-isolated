"""Fetch Debian packages through an sqv-authenticated InRelease chain, for a
read-only or non-root container (references/debian12.md section 1).

usage: uv run --no-project python -I scripts/fetch-debs.py --release bookworm|trixie
           --keyring /usr/share/keyrings/debian-archive-keyring.pgp
           --work <root>/downloads/<name> --dest <dir> [--closure] PKG[=VERSION] ...

Steps: InRelease (sqv --cleartext, plus a one-byte tamper control) ->
Packages.xz (SHA256 and size from InRelease) -> .deb (SHA256 and size from
Packages) -> dpkg-deb --extract into --dest. No maintainer script runs.
With --closure, Depends are followed for packages the host has not installed.
"""
import argparse, hashlib, json, lzma, os, subprocess, sys, urllib.request

MIRRORS = lambda rel: [
    ("https://deb.debian.org/debian", rel),
    ("https://deb.debian.org/debian", rel + "-updates"),
    ("https://deb.debian.org/debian-security", rel + "-security"),
]

def fetch(url, out):
    with urllib.request.urlopen(url, timeout=300) as r, open(out, "wb") as f:
        while True:
            b = r.read(1 << 20)
            if not b:
                break
            f.write(b)
    return out

def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()

def sqv(keyring, path, out):
    return subprocess.run(["sqv", "--keyring", keyring, "--output", out, "--cleartext", path],
                          capture_output=True, text=True)

def parse_stanzas(text):
    for block in text.split("\n\n"):
        d, key = {}, None
        for line in block.splitlines():
            if line.startswith((" ", "\t")) and key:
                d[key] += "\n" + line.strip()
            elif ":" in line:
                key, _, v = line.partition(":")
                d[key] = v.strip()
        if d:
            yield d

def vercmp(a, op, b):
    return subprocess.run(["dpkg", "--compare-versions", a, op, b]).returncode == 0

def installed(name):
    r = subprocess.run(["dpkg-query", "-W", "-f=${db:Status-Abbrev}", name], capture_output=True, text=True)
    return r.returncode == 0 and r.stdout.startswith("ii")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--release", required=True)
    ap.add_argument("--keyring", required=True)
    ap.add_argument("--work", required=True)
    ap.add_argument("--dest", required=True)
    ap.add_argument("--closure", action="store_true")
    ap.add_argument("pkgs", nargs="+")
    a = ap.parse_args()
    os.makedirs(a.work, exist_ok=True)
    index = {}  # name -> list of (version, stanza, base, suite)
    for base, suite in MIRRORS(a.release):
        tag = suite.replace("/", "_")
        ir = fetch(f"{base}/dists/{suite}/InRelease", os.path.join(a.work, f"{tag}.InRelease"))
        auth = os.path.join(a.work, f"{tag}.InRelease.auth")
        if os.path.exists(auth):
            os.remove(auth)
        r = sqv(a.keyring, ir, auth)
        if r.returncode != 0:
            sys.exit(f"FAIL sqv {suite}: {r.stderr.strip()}")
        print(f"AUTH {suite} InRelease sqv ok ({r.stderr.strip().splitlines()[-1] if r.stderr.strip() else 'no message'})")
        # Control: one changed byte in the signed text must fail.
        data = bytearray(open(ir, "rb").read())
        pos = data.find(b"Date:") + 6
        data[pos] = ord("X") if data[pos] != ord("X") else ord("Y")
        bad = os.path.join(a.work, f"{tag}.InRelease.tampered")
        open(bad, "wb").write(data)
        badout = bad + ".auth"
        if os.path.exists(badout):
            os.remove(badout)
        rb = sqv(a.keyring, bad, badout)
        if rb.returncode == 0:
            sys.exit(f"FAIL tamper control passed for {suite}")
        print(f"CONTROL {suite} tampered InRelease rejected rc={rb.returncode}")
        text = open(auth, encoding="utf-8").read()
        rel = next(parse_stanzas(text))
        want = "main/binary-amd64/Packages.xz"
        line = [l.split() for l in rel["SHA256"].splitlines() if l.split()[-1:] == [want]]
        if not line:
            sys.exit(f"FAIL {suite}: no {want} in InRelease")
        psha, psize = line[0][0], int(line[0][1])
        px = fetch(f"{base}/dists/{suite}/{want}", os.path.join(a.work, f"{tag}.Packages.xz"))
        if sha256(px) != psha or os.path.getsize(px) != psize:
            sys.exit(f"FAIL {suite} Packages.xz digest/size mismatch")
        print(f"INDEX {suite} Packages.xz sha256 {psha} size {psize} ok")
        for st in parse_stanzas(lzma.open(px).read().decode("utf-8")):
            index.setdefault(st["Package"], []).append((st["Version"], st, base, suite))

    def pick(name, version=None):
        cands = index.get(name, [])
        if version:
            cands = [c for c in cands if c[0] == version]
        if not cands:
            return None
        best = cands[0]
        for c in cands[1:]:
            if vercmp(c[0], "gt", best[0]):
                best = c
        return best

    queue = [p.split("=", 1) if "=" in p else [p, None] for p in a.pkgs]
    done, results = set(), []
    while queue:
        name, ver = queue.pop(0)
        if name in done:
            continue
        done.add(name)
        c = pick(name, ver)
        if c is None:
            sys.exit(f"FAIL {name} {ver or ''} not in the authenticated {a.release} indexes")
        newest = pick(name)
        version, st, base, suite = c
        deb = os.path.join(a.work, os.path.basename(st["Filename"]))
        fetch(f"{base}/{st['Filename']}", deb)
        got, size = sha256(deb), os.path.getsize(deb)
        if got != st["SHA256"] or size != int(st["Size"]):
            sys.exit(f"FAIL {name} deb digest/size mismatch")
        subprocess.run(["dpkg-deb", "--extract", deb, a.dest], check=True)
        results.append({"package": name, "version": version, "suite": suite, "filename": st["Filename"],
                        "size": size, "sha256": got, "newest": newest[0], "depends": st.get("Depends", "")})
        print(f"DEB {name} {version} [{suite}] size {size} sha256 {got} ok; newest in index {newest[0]}")
        if a.closure:
            for dep in st.get("Depends", "").split(","):
                alt = dep.split("|")[0].strip()
                if not alt:
                    continue
                dn = alt.split()[0].split(":")[0]
                if dn in done or installed(dn):
                    continue
                queue.append([dn, None])
    json.dump(results, open(os.path.join(a.work, "result.json"), "w"), indent=1)

if __name__ == "__main__":
    main()
