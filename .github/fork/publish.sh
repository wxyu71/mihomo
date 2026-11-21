#!/usr/bin/env bash
set -euo pipefail

git fetch "$RUNNER_TEMP/candidate.bundle" HEAD
git merge-base --is-ancestor "$UPSTREAM_SHA" "$CANDIDATE"

if [[ $1 == conflict ]]; then
  git diff --exit-code "$BASE_SHA" "$CANDIDATE" -- .github/workflows
  head="upstream-sync/$TAG"
  existing_pr=$(gh api --method GET "repos/$GITHUB_REPOSITORY/pulls" \
    -f base=Meta -f "head=${GITHUB_REPOSITORY%%/*}:$head" -f state=all --jq '.[0].html_url // empty')
  if [[ -n $existing_pr ]]; then
    echo "Conflict PR: $existing_pr"
    exit 0
  fi
  remote_head=$(git ls-remote --heads origin "refs/heads/$head")
  if [[ -z $remote_head ]]; then
    git push origin "$CANDIDATE:refs/heads/$head"
  else
    git fetch --no-tags origin "refs/heads/$head"
    git merge-base --is-ancestor "$UPSTREAM_SHA" FETCH_HEAD
  fi
  {
    printf 'Upstream release: https://github.com/MetaCubeX/mihomo/releases/tag/%s\n\n' "$TAG"
    printf 'The automatic merge into `Meta` found conflicts in:\n\n'
    sed 's/.*/- `&`/' "$RUNNER_TEMP/conflicts.txt"
    printf '\nResolve the conflicts against `Meta` on this PR branch and merge with a merge commit to preserve upstream ancestry. The next sync will test and publish the resolved commit.\n\n'
    printf 'Actions run: %s/%s/actions/runs/%s\n' "$GITHUB_SERVER_URL" "$GITHUB_REPOSITORY" "$GITHUB_RUN_ID"
  } > "$RUNNER_TEMP/conflict.md"
  gh pr create --repo "$GITHUB_REPOSITORY" --base Meta --head "$head" \
    --title "Resolve upstream $TAG conflicts" --body-file "$RUNNER_TEMP/conflict.md"
  exit 0
fi

git merge-base --is-ancestor "$BASE_SHA" "$CANDIDATE" ||
  git merge-base --is-ancestor "$CANDIDATE" "$BASE_SHA"
git diff --exit-code "$BASE_SHA" "$CANDIDATE" -- .github/workflows

artifact_dir=$RUNNER_TEMP/release
cd "$artifact_dir"
assets=(
  "mihomo-linux-amd64-v1-$TAG.gz" "mihomo-linux-arm64-$TAG.gz"
  "mihomo-windows-amd64-v1-$TAG.zip" "mihomo-windows-amd64-v3-$TAG.zip"
)
for asset in "${assets[@]}"; do
  [[ -s $asset ]]
done
jq -n --arg tag "$TAG" --arg upstream "$UPSTREAM_SHA" --arg commit "$CANDIDATE" \
  --arg run "$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID" \
  '{upstreamTag:$tag, upstreamCommit:$upstream, forkCommit:$commit, actionsRun:$run}' > build-info.json
sha256sum "${assets[@]}" build-info.json > checksums.txt
sha256sum -c checksums.txt
cd "$GITHUB_WORKSPACE"

remote_tag=$(git ls-remote --refs origin "refs/tags/$TAG" | cut -f1)
if [[ -z $remote_tag ]]; then
  [[ $(git ls-remote --heads origin refs/heads/Meta | cut -f1) == "$BASE_SHA" ]]
  git merge-base --is-ancestor "$BASE_SHA" "$CANDIDATE"
  git push --atomic origin "$CANDIDATE:refs/heads/Meta" "$CANDIDATE:refs/tags/$TAG"
else
  [[ $remote_tag == "$CANDIDATE" ]]
fi

state=$(gh api --paginate "repos/$GITHUB_REPOSITORY/releases?per_page=100" |
  jq -rs --arg tag "$TAG" '.[][] | select(.tag_name == $tag) | if .draft then "draft" elif .prerelease then "prerelease" else "published" end')
case $state in
  '')
    {
      printf 'Custom build of [Mihomo %s](https://github.com/MetaCubeX/mihomo/releases/tag/%s).\n\n' "$TAG" "$TAG"
      printf 'Includes the local Tailscale UDP listener fix for `dialer-proxy`.\n\n'
      printf 'Upstream commit: `%s`\n\nFork commit: `%s`\n' "$UPSTREAM_SHA" "$CANDIDATE"
    } > "$RUNNER_TEMP/release.md"
    gh release create "$TAG" --repo "$GITHUB_REPOSITORY" --verify-tag --draft \
      --title "Mihomo $TAG (wxyu71)" --notes-file "$RUNNER_TEMP/release.md"
    ;;
  draft) ;;
  published) exit 0 ;;
  *) echo "Unexpected existing release state: $state" >&2; exit 1 ;;
esac
cd "$artifact_dir"
gh release upload "$TAG" --repo "$GITHUB_REPOSITORY" --clobber "${assets[@]}" build-info.json checksums.txt
gh release edit "$TAG" --repo "$GITHUB_REPOSITORY" --draft=false --prerelease=false --latest
