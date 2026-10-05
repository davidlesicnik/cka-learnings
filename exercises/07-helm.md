# Exercise: Helm — Install, Upgrade, Rollback

## Task

Add the Helm repository `podinfo` from `https://stefanprodan.github.io/podinfo`. Install chart `podinfo/podinfo` as release `web` in a new namespace `shop` with `replicaCount=2` set on the command line. Upgrade the release to 3 replicas, then roll back to revision 1 and confirm replica count is 2 again. List all releases in all namespaces.

---

## Reference Solution

```bash
# Add repo and verify
helm repo add podinfo https://stefanprodan.github.io/podinfo
helm search repo podinfo

# Check default values before installing
helm show values podinfo/podinfo | grep -i replica

# Install
helm install web podinfo/podinfo -n shop --create-namespace --set replicaCount=2

# Upgrade to 3 replicas (creates revision 2)
helm upgrade web podinfo/podinfo -n shop --set replicaCount=3

# Confirm current revision
helm history -n shop web

# Roll back to revision 1 (creates revision 3)
helm rollback web 1 -n shop

# Verify replica count is back to 2
kubectl get deployment -n shop

# List all releases across all namespaces
helm list -A
```

After rollback, `helm list -A` shows `REVISION: 3` — that's expected. Rollback creates a new revision with the old values. The replica count from revision 1 is restored.

---

## Tips

**`--help` is faster than the docs for Helm.** `helm install --help`, `helm upgrade --help`, `helm rollback --help` all give the exact flags and syntax. The Kubernetes docs don't cover Helm well.

**`--set` is case-sensitive.** Match the exact key from `helm show values`. `replicaCount` works; `ReplicaCount` silently creates an ignored override.

**`helm show values <chart>` before installing.** Confirms the key names you'll override with `--set`. One grep command saves a typo.

**Rollback increments the revision counter.** After install (1) → upgrade (2) → rollback to 1 (3), `helm list` shows revision 3. This is correct — rollback is a new event, not a rewind. Use `helm history -n <ns> <release>` to see the full audit trail.

**`--create-namespace` skips the manual `kubectl create ns`.** Always use it when installing into a new namespace.

---

## Run Notes

### Run 1 — 6 minutes

No prior Helm workflow knowledge. Navigated entirely via `--help` on each subcommand.

Typo'd `--set ReplicaCount=2` (capital R) — Helm accepted it silently but ignored it, pod count stayed at 1. Found correct casing with `helm show values`.
