#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if ! command -v ruby >/dev/null 2>&1; then
  echo "ruby is required to parse workflow YAML files." >&2
  exit 1
fi

ruby -e 'require "yaml"; Dir[File.join(ARGV[0], ".github/workflows/*.yml")].sort.each { |f| YAML.load_file(f) }; puts "Workflow YAML parse passed."' "$REPO_ROOT"
