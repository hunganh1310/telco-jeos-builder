#!/bin/bash
# shellcheck.sh — Lint all Bash scripts in the project
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if ! command -v shellcheck &>/dev/null; then
    echo "ERROR: shellcheck not installed. Install: zypper install ShellCheck"
    exit 1
fi

echo "Running shellcheck on all .sh files..."
ERRORS=0

while IFS= read -r -d '' script; do
    rel="${script#${PROJECT_ROOT}/}"
    if shellcheck -S warning "${script}" 2>/dev/null; then
        echo "  [PASS] ${rel}"
    else
        echo "  [FAIL] ${rel}"
        ((ERRORS++))
    fi
done < <(find "${PROJECT_ROOT}" -name "*.sh" -not -path "*/.git/*" -not -path "*/build/*" -print0)

echo ""
if [[ "${ERRORS}" -eq 0 ]]; then
    echo "All scripts passed shellcheck!"
    exit 0
else
    echo "${ERRORS} script(s) had issues."
    exit 1
fi
