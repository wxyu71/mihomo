# Mihomo fork maintenance

`Meta` tracks the latest published stable `vX.Y.Z` GitHub Release from
`MetaCubeX/mihomo`. The sync runs hourly at minute 23 UTC. It is also available
in Actions under **Sync and release stable Mihomo**. The workflow verifies that
the upstream tag is on upstream `Meta` before attempting a merge.

Linux and Windows CI run on the candidate commit. After CI passes, the same
commit is built with `with_gvisor` for Windows AMD64 v1 and v3, Linux AMD64 v1,
and Linux ARM64. The workflow then advances `Meta`, tags the tested commit,
and publishes the ZIP and gzip archives, `checksums.txt`, and `build-info.json`
as a stable GitHub Release. Binary versions include `+wxyu71`. The workflow
uses its repository token, with write access scoped to the publish and conflict
jobs.

When incoming source changes conflict, the workflow opens a pull request on
`upstream-sync/vX.Y.Z`. Resolve the conflict against `Meta` on the PR branch and
complete the PR with a **merge commit** so the upstream tag remains in the
history. The next run tests and publishes the resolved revision. The fork owns
its workflows, so changes under upstream `.github/workflows` are reviewed
separately when adapting the build.

The local Tailscale patch binds the UDP socket locally while keeping control
and DERP on `dialer-proxy`. The isolated regression test requires no Tailnet
credentials. The release workflow publishes artifacts. Installing them into
Clash Verge and testing the live Tailnet is handled by Mihomo GitOps on the host.
