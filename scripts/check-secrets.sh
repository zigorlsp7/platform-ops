#!/usr/bin/env bash
set -euo pipefail

if ! command -v gitleaks >/dev/null 2>&1; then
  echo "gitleaks is not installed. Install it to run secret scans." >&2
  echo "macOS (brew): brew install gitleaks" >&2
  echo "Other: https://github.com/gitleaks/gitleaks#installation" >&2
  exit 1
fi

is_ci="${CI:-false}"
is_github_actions="${GITHUB_ACTIONS:-false}"

# In CI (including GitHub Actions), scan repository files directly.
# There is no staged area in workflow runners, so staged-only scans are bypassed.
if [ "$is_ci" = "true" ] || [ "$is_github_actions" = "true" ]; then
  gitleaks detect --source . --no-git --redact --no-banner
  echo "Secret scan passed (CI full-repo mode)."
  exit 0
fi

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if [ -z "$(git diff --cached --name-only)" ]; then
    echo "No staged files; skipping gitleaks staged scan."
    exit 0
  fi

  # Scan staged blob content from the git index (not working-tree files).
  # This avoids false behavior for deleted files that may still exist locally.
  git diff --cached --name-only -z \
    | xargs -0 -I {} sh -c 'git show ":$1" 2>/dev/null || true' _ {} \
    | gitleaks detect --pipe --redact --no-banner
else
  gitleaks detect --source . --redact --no-banner
fi

echo "Secret scan passed."
