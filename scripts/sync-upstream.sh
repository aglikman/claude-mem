#!/usr/bin/env bash
# Sync this fork with upstream thedotmack/claude-mem.
#
# Usage:
#   scripts/sync-upstream.sh            # merge upstream/main into main, push to origin
#   scripts/sync-upstream.sh --no-push  # merge locally only
#   scripts/sync-upstream.sh --dry-run  # show incoming commits, change nothing
#
# Env overrides: UPSTREAM_URL, UPSTREAM_BRANCH (default main), LOCAL_BRANCH (default main).
# Fast-forwards when possible; otherwise creates a merge commit. Stops on conflicts.

set -euo pipefail

UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/thedotmack/claude-mem.git}"
UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-main}"
LOCAL_BRANCH="${LOCAL_BRANCH:-main}"
PUSH=1
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --no-push) PUSH=0 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

cd "$(git rev-parse --show-toplevel)"

# 1. Ensure the upstream remote exists and points at the right URL.
if git remote get-url upstream >/dev/null 2>&1; then
  current="$(git remote get-url upstream)"
  if [ "$current" != "$UPSTREAM_URL" ]; then
    echo "Updating upstream remote: $current -> $UPSTREAM_URL"
    git remote set-url upstream "$UPSTREAM_URL"
  fi
else
  echo "Adding upstream remote: $UPSTREAM_URL"
  git remote add upstream "$UPSTREAM_URL"
fi

# 2. Fetch upstream.
git fetch upstream "$UPSTREAM_BRANCH"
target="upstream/$UPSTREAM_BRANCH"

incoming="$(git rev-list --count "$LOCAL_BRANCH..$target")"
local_only="$(git rev-list --count "$target..$LOCAL_BRANCH")"
echo "$LOCAL_BRANCH: $incoming commit(s) behind $target, $local_only fork-only commit(s)."

if [ "$incoming" -eq 0 ]; then
  echo "Already up to date."
  exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
  git --no-pager log -n 50 --oneline --no-decorate "$LOCAL_BRANCH..$target"
  if [ "$incoming" -gt 50 ]; then echo "... and $((incoming - 50)) more"; fi
  exit 0
fi

# 3. Refuse to run over uncommitted work.
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "Working tree has uncommitted changes. Commit or stash them first." >&2
  exit 1
fi

start_branch="$(git symbolic-ref --quiet --short HEAD || git rev-parse HEAD)"
if [ "$start_branch" != "$LOCAL_BRANCH" ]; then git checkout --quiet "$LOCAL_BRANCH"; fi

# 4. Merge: fast-forward if the fork has no own commits, merge commit otherwise.
if ! git merge --no-edit "$target" -m "Merge $target into $LOCAL_BRANCH"; then
  echo "Merge conflict. You are on $LOCAL_BRANCH. Resolve, commit, then push: git push origin $LOCAL_BRANCH" >&2
  echo "Or abandon the sync: git merge --abort" >&2
  exit 1
fi

# 5. Push to the fork.
if [ "$PUSH" -eq 1 ]; then
  git push origin "$LOCAL_BRANCH"
fi

if [ "$start_branch" != "$LOCAL_BRANCH" ]; then git checkout --quiet "$start_branch"; fi
echo "Synced $LOCAL_BRANCH with $target."
