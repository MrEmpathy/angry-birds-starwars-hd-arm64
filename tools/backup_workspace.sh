#!/usr/bin/env bash
# Point branch `full` at a snapshot of the complete local workspace for the private backup repo:
# the commit at HEAD plus the files in the "local workspace" section of .gitignore (Rovio inputs,
# decoded assets, keystore, release APKs, build outputs). Test and cache output stays out.
# The new commit has HEAD and the previous `full` as parents, so pushing it never needs --force.
# The main index and worktree are not touched.
# Usage: tools/backup_workspace.sh, then: git push full refs/heads/full:main
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "commit the tracked changes first" >&2
  exit 1
fi
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Everything .gitignore excludes, minus the local workspace section, stays out of the backup.
sed '/^# >>> local workspace$/,/^# <<< local workspace$/d' .gitignore > "$work/exclude"
grep -q '^/original/$' "$work/exclude" && { echo "local workspace markers not found in .gitignore" >&2; exit 1; }

export GIT_INDEX_FILE="$work/index"
git read-tree HEAD
git ls-files -z --others --exclude-from="$work/exclude" | git update-index --add -z --stdin
tree="$(git write-tree)"

parents=(-p HEAD)
if prev="$(git rev-parse -q --verify refs/heads/full)"; then parents+=(-p "$prev"); fi
commit="$(git commit-tree "$tree" "${parents[@]}" -m "chore: snapshot the complete local workspace")"
git update-ref refs/heads/full "$commit"
echo "full -> $commit"
git ls-tree -r --name-only "$commit" | awk -F/ '{print $1}' | sort | uniq -c
