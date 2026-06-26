#!/usr/bin/env bash
# ponytail: conventional-commit guard backing the semantic-release pipeline.
# Allowed types mirror .releaserc (release-bearing) plus the standard
# conventional types that produce no release (chore/docs/build/ci/test/...).
set -euo pipefail

re='^(feat|feature|fix|perf|performance|compat|compatibility|balance|graphics|sound|gui|info|locale|translate|control|other|chore|docs|build|ci|test|style|refactor|revert)(\([^)]+\))?!?: .+'

first=$(head -n1 "$1")
# Merge commits are created by git, not the author; semantic-release ignores them.
case "$first" in
  "Merge "*|"Revert "*) exit 0 ;;
esac
if [[ ! $first =~ $re ]]; then
  echo "Commit message must follow conventional commits: type(scope)!: subject" >&2
  echo "  types: feat fix perf compat balance graphics sound gui info locale translate control other" >&2
  echo "         chore docs build ci test style refactor revert" >&2
  echo "  got: $first" >&2
  exit 1
fi
