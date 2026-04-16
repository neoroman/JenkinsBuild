#!/usr/bin/env bash
# Update JenkinsBuild when used as a git submodule or as a standalone clone.
# Requires: git (2.25+ recommended for --show-superproject-working-tree), python3
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./update.sh [--dry-run]

  When this repo is a git submodule: fetch/pull this repo, then pull the
  superproject and run submodule sync + update --init --remote for this path.

  When standalone: fetch and fast-forward pull for the current branch.

  --dry-run   Print commands instead of executing them.
EOF
}

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Unknown option: $arg" >&2
      usage >&2
      exit 2
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf 'DRY-RUN:'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

git rev-parse --git-dir >/dev/null

superproject="$(git rev-parse --show-superproject-working-tree 2>/dev/null || true)"

pull_ff_this_repo() {
  run git fetch origin
  if git symbolic-ref -q HEAD >/dev/null; then
    if run git pull --ff-only; then
      return 0
    fi
  fi
  local def_branch
  def_branch="$(git symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || true)"
  def_branch="${def_branch:-main}"
  run git pull --ff-only "origin" "$def_branch"
}

if [ -n "$superproject" ]; then
  echo "Submodule checkout detected; superproject: $superproject"
  pull_ff_this_repo

  relpath="$(python3 -c "import os; print(os.path.relpath(os.path.realpath('$SCRIPT_DIR'), os.path.realpath('$superproject')))")"
  (
    cd "$superproject"
    run git fetch origin
    run git pull --ff-only
    run git submodule sync -- "$relpath"
    run git submodule update --init --remote "$relpath"
  )
else
  echo "Standalone clone (no superproject); updating this repository only."
  pull_ff_this_repo
fi

echo "update.sh: done."
