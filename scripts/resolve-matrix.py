#!/usr/bin/env python3
"""Resolve the distribution matrix of the build, so the workflow never needs
editing when a distribution is released:

  - Debian:  the latest stable release
  - Ubuntu:  the latest LTS and the previous LTS
  - Fedora:  the latest release and the previous one

Releases come from endoflife.date and only count once their release date has
passed and their container image exists (checked with `docker manifest
inspect`), so a release announced but not yet on the registry is skipped and
the previous ones are used instead.

Every distribution gets two targets: x86_64 and aarch64.

Environment (all optional, for testing):
  EOL_API              base URL of the API (file:// works), default https://endoflife.date/api
  TODAY                YYYY-MM-DD, default today (UTC)
  SKIP_IMAGE_CHECK=1   do not query the registry

Writes `matrix` (JSON for fromJSON) and `distros` (text for release notes) to
$GITHUB_OUTPUT when set, and always prints the result to stderr.
"""
import json
import os
import subprocess
import sys
import time
import urllib.request
from datetime import date, datetime, timezone

API = os.environ.get("EOL_API", "https://endoflife.date/api").rstrip("/")
TODAY = (date.fromisoformat(os.environ["TODAY"]) if os.environ.get("TODAY")
         else datetime.now(timezone.utc).date())

RUNNER_X86 = "ubuntu-latest"
RUNNER_ARM = "ubuntu-24.04-arm"


def fetch(product):
    last = None
    for attempt in range(5):
        try:
            with urllib.request.urlopen(f"{API}/{product}.json", timeout=30) as r:
                return json.load(r)
        except Exception as exc:  # network hiccup: retry, then fail loudly
            last = exc
            time.sleep(2 ** attempt)
    sys.exit(f"resolve-matrix: cannot read {API}/{product}.json: {last}")


def version_key(cycle):
    return tuple(int(p) for p in cycle.split("."))


def released(entries):
    out = []
    for e in entries:
        rd, cycle = e.get("releaseDate"), str(e.get("cycle", ""))
        if not isinstance(rd, str) or not cycle.replace(".", "").isdigit():
            continue
        if date.fromisoformat(rd) <= TODAY:
            out.append(e)
    return sorted(out, key=lambda e: version_key(str(e["cycle"])), reverse=True)


def image_exists(image):
    if os.environ.get("SKIP_IMAGE_CHECK") == "1":
        return True
    return subprocess.run(["docker", "manifest", "inspect", image],
                          stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL).returncode == 0


def pick(entries, count, image_of):
    chosen = []
    for e in entries:
        if len(chosen) == count:
            break
        if image_of(e) is None or image_exists(image_of(e)):
            chosen.append(e)
        else:
            print(f"resolve-matrix: skipping {image_of(e)} (no image yet)", file=sys.stderr)
    if len(chosen) < count:
        sys.exit(f"resolve-matrix: found only {len(chosen)} of {count} releases")
    return chosen


def targets(slug, image, kind):
    glob = "*.deb" if kind == "deb" else "*.rpm"
    return [
        {"name": f"{slug}-x86_64", "image": image, "kind": kind,
         "microarch": "baseline", "runner": RUNNER_X86, "glob": glob},
        {"name": f"{slug}-aarch64", "image": image, "kind": kind,
         "microarch": "baseline", "runner": RUNNER_ARM, "glob": glob},
    ]


def main():
    include, labels = [], []

    debian = pick(released(fetch("debian")), 1,
                  lambda e: f"debian:{str(e['codename']).lower()}")
    for e in debian:
        include += targets(f"debian-{e['cycle']}", f"debian:{str(e['codename']).lower()}", "deb")
    labels.append("Debian " + ", ".join(str(e["cycle"]) for e in debian))

    ubuntu = pick([e for e in released(fetch("ubuntu")) if e.get("lts") is True], 2,
                  lambda e: f"ubuntu:{e['cycle']}")
    for e in ubuntu:
        include += targets(f"ubuntu-{e['cycle']}", f"ubuntu:{e['cycle']}", "deb")
    labels.append("Ubuntu " + " / ".join(str(e["cycle"]) for e in reversed(ubuntu)))

    fedora = pick(released(fetch("fedora")), 2, lambda e: f"fedora:{e['cycle']}")
    for e in fedora:
        include += targets(f"fedora-{e['cycle']}", f"fedora:{e['cycle']}", "rpm")
    labels.append("Fedora " + " / ".join(str(e["cycle"]) for e in reversed(fedora)))

    matrix = json.dumps({"include": include}, separators=(",", ":"))
    distros = ", ".join(labels)
    print(f"resolve-matrix: {distros} ({len(include)} jobs)", file=sys.stderr)
    out = os.environ.get("GITHUB_OUTPUT")
    if out:
        with open(out, "a", encoding="utf-8") as fh:
            fh.write(f"matrix={matrix}\ndistros={distros}\n")
    else:
        print(matrix)


if __name__ == "__main__":
    main()
