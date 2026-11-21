#!/usr/bin/env bash
set -euo pipefail

upstream=MetaCubeX/mihomo
release=$(gh api "repos/$upstream/releases/latest")
tag=$(jq -er 'select(.draft == false and .prerelease == false and .published_at != null) | .tag_name' <<< "$release")
[[ $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]

fork_releases=$(gh api --paginate "repos/$GITHUB_REPOSITORY/releases?per_page=100")
if jq -es --arg tag "$tag" 'any(.[][]; .tag_name == $tag and .draft == false and .prerelease == false)' \
    <<< "$fork_releases" >/dev/null; then
  echo "$tag is already published in the fork."
  exit 0
fi

git fetch --no-tags origin refs/heads/Meta:refs/remotes/origin/Meta
git fetch --no-tags "https://github.com/$upstream.git" \
  refs/heads/Meta:refs/sync/upstream-meta "refs/tags/$tag:refs/sync/upstream-release"
base=$(git rev-parse refs/remotes/origin/Meta)
source=$(git rev-parse 'refs/sync/upstream-release^{commit}')
git merge-base --is-ancestor "$source" refs/sync/upstream-meta

git checkout --detach "$base"
export GIT_AUTHOR_NAME='github-actions[bot]' GIT_COMMITTER_NAME='github-actions[bot]'
export GIT_AUTHOR_EMAIL='41898282+github-actions[bot]@users.noreply.github.com'
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
# Repeated conflict checks for the same source and workflow tree give the same PR head.
GIT_AUTHOR_DATE=$(git show -s --format=%cI "$source")
export GIT_AUTHOR_DATE GIT_COMMITTER_DATE="$GIT_AUTHOR_DATE"

mode=build
if [[ -n $(git ls-remote --refs origin "refs/tags/$tag") ]]; then
  # Resume a publication interrupted after the atomic branch/tag push.
  git fetch --no-tags origin "refs/tags/$tag:refs/sync/fork-release"
  candidate=$(git rev-parse 'refs/sync/fork-release^{commit}')
  git merge-base --is-ancestor "$source" "$candidate"
  git merge-base --is-ancestor "$candidate" "$base"
  git checkout --detach "$candidate"
elif ! git merge-base --is-ancestor "$source" "$base"; then
  if ! git merge --no-ff --no-commit "$source"; then
    # A failed merge without an index conflict is an infrastructure failure.
    [[ -n $(git ls-files -u) ]]
  fi
  # The fork owns its Actions setup. Merge upstream source and keep the current workflow tree.
  git restore --source=HEAD --staged --worktree -- .github/workflows
  if [[ -n $(git ls-files -u) ]]; then
    git diff --name-only --diff-filter=U > "$RUNNER_TEMP/conflicts.txt"
    git merge --abort
    # Git cannot commit an unmerged index. Use upstream's source tree as the PR head
    # and keep the fork's workflow files so PR creation needs no workflow credential.
    export GIT_INDEX_FILE="$RUNNER_TEMP/upstream.index"
    git read-tree "$source"
    git ls-files -z -- .github/workflows | git update-index --force-remove -z --stdin
    git ls-tree -rz "$base" -- .github/workflows | git update-index -z --index-info
    tree=$(git write-tree)
    unset GIT_INDEX_FILE
    candidate=$(git commit-tree "$tree" -p "$source" -m "Prepare upstream $tag for conflict resolution")
    git checkout --detach "$candidate"
    mode=conflict
  else
    git -c commit.gpgsign=false commit -m "Merge MetaCubeX/mihomo $tag"
  fi
fi

candidate=$(git rev-parse HEAD)
git bundle create "$RUNNER_TEMP/candidate.bundle" HEAD
{
  echo "mode=$mode"
  echo "tag=$tag"
  echo "base=$base"
  echo "upstream=$source"
  echo "candidate=$candidate"
} >> "$GITHUB_OUTPUT"
