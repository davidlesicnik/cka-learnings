# Exercise: etcd Backup and Restore

## Task

Take a snapshot of etcd on the control plane node and save it to `/opt/backup/etcd-snapshot.db`. Restore it to a new data directory `/var/lib/etcd-restored` and update the cluster so it uses the restored data. Verify the cluster is healthy afterwards.

---

## Reference Solution

### 1. Find cert paths (don't memorize — read from the manifest)

```bash
grep -E 'cert-file|key-file|trusted-ca-file|listen-client' /etc/kubernetes/manifests/etcd.yaml
```

This gives you the exact flags etcd was started with. Use those values directly.

### 2. Backup

```bash
mkdir -p /opt/backup

ETCDCTL_API=3 etcdctl \
  --endpoints https://localhost:2379 \
  --cert /etc/kubernetes/pki/etcd/server.crt \
  --key /etc/kubernetes/pki/etcd/server.key \
  --cacert /etc/kubernetes/pki/etcd/ca.crt \
  snapshot save /opt/backup/etcd-snapshot.db
```

### 3. Verify snapshot

```bash
etcdutl snapshot status /opt/backup/etcd-snapshot.db -w table
```

Check TOTAL KEYS is non-zero and HASH looks valid. If this errors, snapshot is corrupt — don't proceed.

### 4. Stop etcd

```bash
mv /etc/kubernetes/manifests/etcd.yaml /tmp/etcd.yaml
# Wait for etcd container to stop
crictl ps | grep etcd  # should return empty
```

### 5. Get restore flag values from the etcd manifest

Before restoring, read the values you need directly from the running etcd config:

```bash
grep -E '\-\-name|initial-cluster|initial-advertise-peer-urls' /etc/kubernetes/manifests/etcd.yaml
```

Example output:

```
- --name=k8s-cp1
- --initial-cluster=k8s-cp1=https://192.168.252.2:2380
- --initial-advertise-peer-urls=https://192.168.252.2:2380
```

Use those values directly in the restore command. The token can be any static string — it just needs to differ from the original cluster token to prevent cross-cluster communication.

`etcdutl snapshot restore --help` lists all flags. The ones you actually need for this exercise:

| Flag | Why |
|------|-----|
| `--data-dir` | Where to write restored data |
| `--name` | This node's etcd member name |
| `--initial-cluster` | All members + their peer URLs |
| `--initial-cluster-token` | Unique token to isolate the restored cluster |
| `--initial-advertise-peer-urls` | This node's peer URL |

Everything else (`--bump-revision`, `--mark-compacted`, `--wal-dir`, etc.) is for edge cases — ignore on the exam.

### 6. Restore to new directory

```bash
etcdutl snapshot restore /opt/backup/etcd-snapshot.db \
  --name k8s-cp1 \
  --initial-cluster k8s-cp1=https://192.168.252.2:2380 \
  --initial-cluster-token etcd-restore-1 \
  --initial-advertise-peer-urls https://192.168.252.2:2380 \
  --data-dir /var/lib/etcd-restored
```

`etcdutl` creates the directory — no need to `mkdir` first.

### 7. Point etcd at the new directory

Edit the etcd manifest and change the `hostPath.path` under the `etcd-data` volume:

```bash
vi /tmp/etcd.yaml
```

Find this block:

```yaml
volumes:
- hostPath:
    path: /var/lib/etcd        # change this
    type: DirectoryOrCreate
  name: etcd-data
```

Change to:

```yaml
    path: /var/lib/etcd-restored
```

> **Why this matters:** The `hostPath` is what etcd actually reads from on disk. The `--data-dir` flag in the etcd container command is the in-container path — it maps to this `hostPath`. If you only restore the files but don't update `hostPath`, etcd starts up reading the original (unreplaced) data directory.

### 8. Restart etcd

```bash
mv /tmp/etcd.yaml /etc/kubernetes/manifests/etcd.yaml
```

Wait ~60 seconds for etcd and the API server to reconnect.

### 9. Verify

```bash
kubectl get nodes
ETCDCTL_API=3 etcdctl \
  --endpoints https://localhost:2379 \
  --cert /etc/kubernetes/pki/etcd/server.crt \
  --key /etc/kubernetes/pki/etcd/server.key \
  --cacert /etc/kubernetes/pki/etcd/ca.crt \
  endpoint health
```

---

## Tips

**`ETCDCTL_API=3` is mandatory.** Without it, `etcdctl` uses the v2 API which has a different data model. The snapshot command silently does the wrong thing. Run this once at the start of any etcd task:

```bash
export ETCDCTL_API=3
```

All subsequent `etcdctl` calls in that shell session will use v3 — no need to prefix every command.

**Cert flags aren't in the k8s docs snapshot example.** The docs show a minimal command. Use `etcdctl snapshot --help` to find the `GLOBAL OPTIONS` section — the three TLS flags are there. Or just read them off the etcd manifest.

**`etcdutl` vs `etcdctl`:** `etcdctl snapshot save` hits a live server. `etcdutl snapshot restore` works on a file — no server needed, which is why it works even when etcd is stopped. Don't mix them up.

**API server comes back slowly.** After moving the manifest back, it can take 60-90 seconds for etcd to start and the API server to reconnect. `kubectl get nodes` timing out doesn't mean something is wrong — wait it out, then check again.

**`etcdctl` endpoint port is `2379`, not `2380`.** The docs near the backup section show `2380` — that's the peer port (etcd-to-etcd replication). The client port is `2379`. Always use `--endpoints=https://127.0.0.1:2379`.

**`cd /etc/kubernetes/pki/etcd` before running `etcdctl`.** Then use `--cacert=ca.crt --cert=server.crt --key=server.key` — no full paths needed.

---

## Run Notes

### Run 1 — >20 minutes

Took too long remembering `etcdctl` cert flags. Found them via `etcdctl snapshot --help` → Global Options — good approach, use this on the exam.

Restore itself was straightforward but hit a critical mistake: restored to `/var/lib/etcd-restored` but didn't update the `hostPath` in `etcd.yaml`. Result: cluster came back but showed empty state (no nodes, no pods) because etcd was still reading from the original `/var/lib/etcd` directory.

```
kubectl get nodes
No resources found

kubectl get all -A
NAMESPACE   NAME                 TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
default     service/kubernetes   ClusterIP   10.96.0.1    <none>        443/TCP   3m10s
```

Snapshot verified healthy (796 keys, 24MB) and restore files existed — so the restore worked. The bug was etcd reading the wrong path.

Fix: updated `hostPath.path` in `etcd.yaml` from `/var/lib/etcd` → `/var/lib/etcd-restored`. Cluster came back fully healthy.

**Key lesson from this run:** Restoring the data is half the job. Pointing etcd at it is the other half. After restore, always check the `etcd-data` volume `hostPath` in the manifest before restarting.

Also tried `etcdutl --data-dir . snapshot restore` initially — wrong syntax. Correct form is `etcdutl snapshot restore <file> --data-dir <path>`.


### Run 2 — 7m40s (~1 min unnecessary troubleshooting)

Improvements over run 1:
- Exported `ETCDCTL_API=3` upfront — no friction on the snapshot command
- `cd /etc/kubernetes/pki/etcd` first — avoided spelling out full cert paths on every command
- Used `etcdctl member list` to get cert flag syntax right before attempting the snapshot

Port gotcha: docs page near the backup section mentions port `2380` — tried it first, failed. Remembered 2380 is the peer port; client port is `2379`. Always use `2379` for `etcdctl`.

Verified snapshot with `etcdutl snapshot status /opt/backup/etcd-snapshot.db --write-out=table` — confirmed healthy before restoring.

Shut down etcd by moving its manifest out of `/etc/kubernetes/manifests/`, restored snapshot to `/opt/test/` (run 1 already used the exam path, and i wanted to use a different one), updated `hostPath` in `etcd.yaml`, moved manifest back.

Wasted ~1 minute troubleshooting after the restore because etcd takes a few minutes to start — forgot about the startup delay. Nothing was wrong.
