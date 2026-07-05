#!/usr/bin/env bash
#
# Purpose: Install Python packages needed to build the MkDocs static site.
# Usage:
#   bash scripts/install_mkdocs_deps.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQ_FILE="${SCRIPT_DIR}/requirements-docs.txt"

python3 -m pip install --user -r "${REQ_FILE}"

echo "[mkdocs] dependencies installed"
