#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="/Users/openclaw/Projects/VPStudio"
cd "$REPO_DIR"

# Only commit tracked file changes; ignore untracked files (like crash logs, editor caches, temporary artifacts).
CHANGED_TRACKED="$(git status --short --untracked-files=no | awk '{print $2}')"

if [[ -z "$CHANGED_TRACKED" ]]; then
  echo "[auto-commit] No tracked changes to commit."
  exit 0
fi

# Stage and commit all tracked changes in the workspace to keep history clean and replayable.
git add -A

if ! git diff --cached --quiet; then
  TS="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  git commit -m "chore(vpstudio): auto commit from bugscan maintenance (${TS})"
  echo "[auto-commit] Created commit: $(git rev-parse --short HEAD)"
else
  echo "[auto-commit] Nothing staged after add; skipping."
fi
