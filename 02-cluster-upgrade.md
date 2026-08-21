# Cluster Upgrade

This document covers upgrading a Kubernetes cluster from one minor version to the next.

---

## Key Rule: One Minor Version at a Time

Kubernetes only supports upgrades between consecutive minor versions:

```
1.34 → 1.35 → 1.36   ✅
1.34 → 1.36           ❌ (skipping 1.35 is unsupported)
```

**Why?** Each minor version may introduce API changes, deprecations, or new resource formats. The upgrade tooling (`kubeadm upgrade`) only knows how to migrate state one step at a time. Skipping a version could leave cluster state in an inconsistent format that no single migration path handles.

---

## Upgrade Order

The upgrade must follow a specific sequence:

1. **kubeadm** (on control plane) — upgrades the tool that orchestrates everything else
2. **Control plane components** (via `kubeadm upgrade apply`) — API server, controller manager, scheduler, etcd
3. **kubelet + kubectl** (on control plane node) — the node agent and CLI
4. **Worker nodes** (one at a time) — same process but uses `kubeadm upgrade node` instead

**Why this order?** The kubelet must never be newer than the API server. Kubernetes guarantees compatibility only when: `kubelet <= API server <= kubeadm`. Upgrading kubeadm first ensures it can orchestrate the control plane upgrade; upgrading the control plane before workers ensures workers always talk to an API server >= their own version.

---

## Step 1: Upgrade kubeadm on the Control Plane

Enter the control plane node:

```bash
multipass shell k8s-cp1
sudo -i
```

### Unhold the packages

In the cluster setup we pinned (held) packages at 1.34 to prevent accidental upgrades. Remove that hold:

```bash
apt-mark unhold kubeadm kubelet kubectl
```

### Point apt at the new version's repository

Each Kubernetes minor version has its own apt repository. Switch from v1.34 to v1.35:

```bash
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.35/deb/Release.key \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg  # Overwrite if asked

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.35/deb/ /' \
  | tee /etc/apt/sources.list.d/kubernetes.list

apt update
```

### Verify the new version is available

```bash
apt-cache madison kubeadm | head
```

Expected output — a list of 1.35.x versions:

```
   kubeadm | 1.35.7-1.1 | https://pkgs.k8s.io/core:/stable:/v1.35/deb  Packages
   kubeadm | 1.35.6-1.1 | https://pkgs.k8s.io/core:/stable:/v1.35/deb  Packages
   ...
```

### Install and re-hold kubeadm

```bash
apt install -y kubeadm=1.35.7-1.1
apt-mark hold kubeadm
kubeadm version -o short  # Should print v1.35.7
```

We only upgrade kubeadm first — kubelet and kubectl come later. This is intentional: kubeadm needs to be at the target version to know how to perform the upgrade.

---

## Step 2: Upgrade the Control Plane Components

### Dry-run with upgrade plan

```bash
kubeadm upgrade plan
```

This checks:
- Current cluster version
- Available target versions
- Whether all prerequisites are met (healthy etcd, reachable API server)
- Any deprecated API versions your manifests use

Near the end of the output you'll see:

```
You can now apply the upgrade by executing the following command:

        kubeadm upgrade apply v1.35.7
```

### Apply the upgrade

```bash
kubeadm upgrade apply v1.35.7
```

This takes a few minutes. What it does:

1. Downloads new container images for control plane components
2. Upgrades the static pod manifests in `/etc/kubernetes/manifests/`
3. Restarts control plane pods (API server, controller manager, scheduler)
4. Upgrades etcd if needed
5. Updates cluster-internal ConfigMaps (like `kubeadm-config`, `kubelet-config`)

Success output:

```
[upgrade] SUCCESS! A control plane node of your cluster was upgraded to "v1.35.7".
[upgrade] Now please proceed with upgrading the rest of the nodes by following the right order.
```

> At this point the API server runs 1.35 but the kubelet on this node is still 1.34. This is fine — kubelet can be one minor version behind the API server.

---

## Step 3: Upgrade kubelet and kubectl on the Control Plane

### Drain the node

Before touching the kubelet, drain the node so no workloads are disrupted during restart:

```bash
kubectl drain k8s-cp1 --ignore-daemonsets
```

**What drain does:**
- Marks the node as unschedulable (cordon)
- Evicts all pods (except DaemonSet pods, which we ignore since they must run on every node)
- Pods managed by Deployments/ReplicaSets get rescheduled elsewhere

### Upgrade the packages

```bash
apt install -y kubelet=1.35.7-1.1 kubectl=1.35.7-1.1
apt-mark hold kubelet kubectl
```

### Restart the kubelet

```bash
systemctl daemon-reload
systemctl restart kubelet
```

`daemon-reload` tells systemd to re-read unit files (in case the kubelet's service definition changed). Then we restart kubelet so it picks up its new binary.

### Uncordon the node

```bash
kubectl uncordon k8s-cp1
```

This marks the node as schedulable again.

### Verify

```
$ kubectl get nodes
NAME          STATUS   ROLES           AGE    VERSION
k8s-cp1       Ready    control-plane   125m   v1.35.7
k8s-worker1   Ready    <none>          119m   v1.34.10
k8s-worker2   Ready    <none>          119m   v1.34.10
```

Control plane is now fully on 1.35. Workers still on 1.34 — this is expected and supported (kubelet can be one minor version behind).

---

## Step 4: Upgrade Worker Nodes

Workers are upgraded one at a time to maintain availability. If you have workloads with multiple replicas, they get rescheduled to the remaining ready node during drain.

### Drain the worker (from cp1 shell)

```bash
kubectl drain k8s-worker1 --ignore-daemonsets --force
```

The `--force` flag is needed here because workers may have standalone pods (not managed by a controller) that drain won't evict without it. Be aware: `--force` deletes those pods permanently — they won't be recreated.

### Upgrade on the worker node

Switch to the worker shell:

```bash
multipass shell k8s-worker1
sudo -i
```

The process is similar to the control plane, with one key difference — workers use `kubeadm upgrade node` instead of `kubeadm upgrade apply`:

```bash
# Unhold and update repo
apt-mark unhold kubeadm kubelet kubectl
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.35/deb/Release.key \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.35/deb/ /' \
  | tee /etc/apt/sources.list.d/kubernetes.list
apt update

# Upgrade kubeadm
apt install -y kubeadm=1.35.7-1.1
apt-mark hold kubeadm

# Upgrade node config
kubeadm upgrade node

# Upgrade kubelet and kubectl
apt install -y kubelet=1.35.7-1.1 kubectl=1.35.7-1.1
apt-mark hold kubelet kubectl
systemctl daemon-reload
systemctl restart kubelet
```

**`kubeadm upgrade node` vs `kubeadm upgrade apply`:**

| Command | Used on | What it does |
|---------|---------|--------------|
| `kubeadm upgrade apply` | First control plane | Upgrades all control plane components + etcd |
| `kubeadm upgrade node` | Workers + additional CPs | Only updates local kubelet config to match new cluster config |

Workers don't run API server/scheduler/etcd, so there's nothing to upgrade except the kubelet configuration and the kubelet binary itself.

### Uncordon (from cp1 shell)

```bash
kubectl uncordon k8s-worker1
```

### Verify

```
$ kubectl get nodes
NAME          STATUS   ROLES           AGE    VERSION
k8s-cp1       Ready    control-plane   129m   v1.35.7
k8s-worker1   Ready    <none>          123m   v1.35.7
k8s-worker2   Ready    <none>          123m   v1.34.10
```

### Repeat for remaining workers

Run the same process on `k8s-worker2`. Once done, all nodes will be on 1.35.7.

---

## Summary: The Complete Upgrade Flow

```
┌─────────────────────────────────────────────────────┐
│ Control Plane Node                                  │
│                                                     │
│  1. Unhold + install kubeadm 1.35                   │
│  2. kubeadm upgrade plan (dry run)                  │
│  3. kubeadm upgrade apply v1.35.7                   │
│  4. drain → upgrade kubelet/kubectl → uncordon      │
└─────────────────────────────────────────────────────┘
              │
              ▼ (repeat per worker)
┌─────────────────────────────────────────────────────┐
│ Worker Node                                         │
│                                                     │
│  1. drain (from CP)                                 │
│  2. Unhold + install kubeadm 1.35                   │
│  3. kubeadm upgrade node                            │
│  4. Upgrade kubelet/kubectl → restart → uncordon    │
└─────────────────────────────────────────────────────┘
```

## Troubleshooting

- **Token expired during upgrade?** Tokens last 24h. Generate a new one: `kubeadm token create --print-join-command`
- **Drain hangs?** A pod with a PodDisruptionBudget may block eviction. Use `kubectl get pdb -A` to check, or add `--delete-emptydir-data` if pods use emptyDir volumes
- **Kubelet won't start after upgrade?** Check `journalctl -u kubelet -f` for errors. Common cause: old config referencing removed flags
