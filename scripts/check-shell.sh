#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

count=0
while IFS= read -r file; do
  [ -n "$file" ] || continue
  bash -n "$file"
  count=$((count + 1))
done < <(find "$REPO_ROOT/scripts" -maxdepth 1 -type f -name '*.sh' | sort)

if [ "$count" -eq 0 ]; then
  echo "No shell scripts to lint."
  exit 0
fi

echo "Shell syntax check passed (${count} files)."
