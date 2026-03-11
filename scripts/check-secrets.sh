#!/usr/bin/env bash
set -euo pipefail

if ! command -v gitleaks >/dev/null 2>&1; then
  echo "gitleaks is not installed. Install it to run secret scans." >&2
  echo "macOS (brew): brew install gitleaks" >&2
  echo "Other: https://github.com/gitleaks/gitleaks#installation" >&2
  exit 1
fi

is_ci="false"
if [ "${CI+x}" = "x" ] && [ "$CI" = "true" ]; then
  is_ci="true"
fi

is_github_actions="false"
if [ "${GITHUB_ACTIONS+x}" = "x" ] && [ "$GITHUB_ACTIONS" = "true" ]; then
  is_github_actions="true"
fi

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

  # Staged scan runs through stdin (--pipe), which has no path context.
  # Exclude local env files up front so they are allowed consistently
  # with CI full-repo scans and repository gitleaks allowlist.
  staged_paths="$(
    git diff --cached --name-only \
      | rg -v '(^|/)docker/\.env\..*\.local(\..*)?$|(^|/)\.env\..*\.local(\..*)?$' \
      || true
  )"

  if [ -z "$staged_paths" ]; then
    echo "Only local env files are staged; skipping gitleaks staged scan."
    exit 0
  fi

  # Scan staged blob content from the git index (not working-tree files).
  # This avoids false behavior for deleted files that may still exist locally.
  printf '%s\n' "$staged_paths" \
    | xargs -I {} sh -c 'git show ":$1" 2>/dev/null || true' _ {} \
    | gitleaks detect --pipe --redact --no-banner
else
  gitleaks detect --source . --redact --no-banner
fi

echo "Secret scan passed."
