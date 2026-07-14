#!/usr/bin/env bash
#
# Purpose: Build the MkDocs static site using mkdocs.yml.
# Usage:
#   bash scripts/build_mkdocs_site.sh
#
# Optional environment:
#   MKDOCS_CONFIG=path/to/mkdocs.yml

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MKDOCS_CONFIG="${MKDOCS_CONFIG:-${REPO_ROOT}/mkdocs.yml}"

export PATH="${HOME}/.local/bin:${PATH}"
export PYTHONPATH="${REPO_ROOT}/scripts:${PYTHONPATH:-}"

if ! command -v mkdocs >/dev/null 2>&1; then
    echo "ERROR: mkdocs is not installed." >&2
    echo "Run: bash scripts/install_mkdocs_deps.sh" >&2
    exit 1
fi

mkdocs build --strict -f "${MKDOCS_CONFIG}" "$@"

SITE_DIR="$(python3 - "${MKDOCS_CONFIG}" <<'PY'
import sys

site_dir = "site"
with open(sys.argv[1], "r", encoding="utf-8") as f:
    for line in f:
        stripped = line.strip()
        if stripped.startswith("site_dir:"):
            value = stripped.split(":", 1)[1].strip().strip("\"'")
            if value:
                site_dir = value
            break

print(site_dir)
PY
)"

if [[ "${SITE_DIR}" != /* ]]; then
    SITE_DIR="${REPO_ROOT}/${SITE_DIR}"
fi

mkdir -p "${SITE_DIR}"

python3 - "${SITE_DIR}" <<'PY'
import hashlib
import pathlib
import re
import sys

site_dir = pathlib.Path(sys.argv[1])
assets = [
    "assets/stylesheets/mermaid-zoom.css",
    "assets/javascripts/mermaid-zoom.js",
]

replacements = []
for asset in assets:
    path = site_dir / asset
    if not path.exists():
        raise SystemExit(f"ERROR: expected MkDocs asset is missing: {path}")

    digest = hashlib.sha256(path.read_bytes()).hexdigest()[:12]
    replacements.append((asset, f"{asset}?v={digest}"))
    replacements.append((f"/{asset}", f"/{asset}?v={digest}"))

for html in site_dir.rglob("*.html"):
    text = html.read_text(encoding="utf-8")
    next_text = text
    for old, new in replacements:
        next_text = re.sub(
            re.escape(old) + r"(?:\?v=[0-9a-f]+)?",
            new,
            next_text,
        )
    if next_text != text:
        html.write_text(next_text, encoding="utf-8")

for asset, versioned in replacements:
    if not asset.startswith("/"):
        print(f"[mkdocs] cache-bust: {asset} -> {versioned}")
PY

cat > "${SITE_DIR}/index.html" <<'HTML'
<!doctype html>
<html lang="ko">
  <head>
    <meta charset="utf-8">
    <meta http-equiv="refresh" content="0; url=Project_Introduction.html">
    <title>NAND Model Design Specification</title>
  </head>
  <body>
    <p><a href="Project_Introduction.html">Open NAND Model Design Specification</a></p>
  </body>
</html>
HTML

if [[ ! -f "${SITE_DIR}/index.html" ]]; then
    echo "ERROR: failed to generate ${SITE_DIR}/index.html" >&2
    exit 1
fi

echo "[mkdocs] generated root redirect: ${SITE_DIR}/index.html -> Project_Introduction.html"
