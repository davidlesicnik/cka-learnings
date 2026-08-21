# Swap Flannel for Calico

In the basic cluster setup we used Flannel as the initial CNI plugin. Flannel is great for quick basic setups, but it lacks support for **NetworkPolicies** and other advanced features.

To continue with CKA topics (which require NetworkPolicy support), we'll swap Flannel out for Calico.

---

## Why Calico over Flannel?

| Feature | Flannel | Calico |
|---------|---------|--------|
| Basic pod networking | Yes | Yes |
| NetworkPolicy support | No | Yes |
| BGP peering | No | Yes |
| IP-in-IP / VXLAN encapsulation | VXLAN only | Both |
| Per-pod firewall rules | No | Yes (iptables/eBPF) |

The CKA exam tests NetworkPolicy knowledge, so a CNI that supports it is required. Calico is the most common production choice.

### Flannel's Silent NetworkPolicy Trap

Flannel doesn't outright reject NetworkPolicy objects — Kubernetes lets you `kubectl apply` them just fine because NetworkPolicy is a core API resource. The API server stores them in etcd regardless of whether any CNI enforces them.

With Flannel, your policies exist but **do absolutely nothing**. Traffic flows freely despite a "deny-all" policy being in place. This is dangerous because:

- You get no error, no warning, no event — everything looks correct
- `kubectl get networkpolicy` shows your policy exists
- You might assume you're locked down when you're wide open

This is a common gotcha in both the CKA exam and real clusters. If NetworkPolicies seem to have no effect, check which CNI is installed.

---

## Important: This Causes Downtime

Swapping a CNI is disruptive — you're removing the entire pod network and replacing it. During the gap:

- All nodes go `NotReady`
- Pod-to-pod communication breaks
- CoreDNS stops resolving

In production you'd never do this live. For a learning cluster it's fine.

---

## Step 1: Remove Flannel

Enter the control plane node:

```bash
multipass shell k8s-cp1
sudo -i
```

Delete the Flannel DaemonSet and related resources:

```bash
kubectl delete -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
```

This removes the Flannel pods but leaves behind state on each node's filesystem and network interfaces.

---

## Step 2: Clean Up Flannel State (All Nodes)

Run the following on **every node** (cp1, worker1, worker2):

```bash
# Remove CNI config files Flannel left behind
sudo rm -f /etc/cni/net.d/*flannel*
sudo rm -f /etc/cni/net.d/10-flannel.conflist

# Remove the virtual network interfaces Flannel created
sudo ip link delete flannel.1 2>/dev/null || true
sudo ip link delete cni0 2>/dev/null || true

# Restart containerd and kubelet to drop cached network state
sudo systemctl restart containerd
sudo systemctl restart kubelet
```

**Why this cleanup is necessary:**

- `/etc/cni/net.d/` — kubelet reads CNI config from here. If old Flannel configs remain, the new CNI may conflict or kubelet may try to use the stale config
- `flannel.1` — the VXLAN interface Flannel created for overlay traffic
- `cni0` — the bridge interface Flannel used to connect pods on the same node
- Restarting containerd/kubelet forces them to re-read CNI config on next pod creation

---

## Step 3: Verify Nodes Are NotReady

After cleanup, all nodes should be `NotReady` — this confirms Flannel is fully gone:

```
$ kubectl get nodes
NAME          STATUS     ROLES           AGE     VERSION
k8s-cp1       NotReady   control-plane   6h34m   v1.36.3
k8s-worker1   NotReady   <none>          6h28m   v1.36.3
k8s-worker2   NotReady   <none>          6h27m   v1.36.3
```

If a node still shows `Ready`, the old CNI config wasn't fully cleaned on that node.

---

## Step 4: Install Calico (via Tigera Operator)

Calico can be installed two ways: as a standalone manifest or via the **Tigera operator**. We use the operator because:

- It manages Calico component lifecycle (upgrades, scaling)
- It's the recommended approach for production
- It uses CRDs to configure Calico declaratively

### Install the operator

```bash
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.1/manifests/tigera-operator.yaml
```

This creates:
- The `tigera-operator` namespace
- CRDs for Calico configuration (`Installation`, `IPPool`, etc.)
- The operator Deployment that watches for those CRDs

### Configure the pod CIDR

By default Calico assumes `192.168.0.0/16` for pod IPs. Our cluster uses `10.244.0.0/16` (set during `kubeadm init --pod-network-cidr`). We must match it:

```bash
curl https://raw.githubusercontent.com/projectcalico/calico/v3.32.1/manifests/custom-resources.yaml -O
sed -i 's/192.168.0.0\/16/10.244.0.0\/16/' custom-resources.yaml
kubectl create -f custom-resources.yaml
```

**Why the CIDR must match:** The `--pod-network-cidr` told `kube-controller-manager` which range to allocate pod subnets from. If Calico uses a different range, pods get IPs that the controller manager doesn't know about, breaking routing.

---

## Step 5: Verify Calico Is Running

Watch Calico pods come up:

```bash
watch kubectl get pods -n calico-system
```

You should see:
- `calico-node-*` — DaemonSet, one per node (handles routing + network policy enforcement)
- `calico-kube-controllers-*` — single pod (syncs Kubernetes NetworkPolicy objects to Calico datastore)
- `calico-typha-*` — optional (fan-out proxy between API server and calico-node, reduces API load on large clusters)

Once all pods are `Running`, check nodes:

```
$ kubectl get nodes
NAME          STATUS   ROLES           AGE     VERSION
k8s-cp1       Ready    control-plane   6h37m   v1.36.3
k8s-worker1   Ready    <none>          6h32m   v1.36.3
k8s-worker2   Ready    <none>          6h31m   v1.36.3
```

All `Ready` — Calico is handling pod networking and the cluster is healthy.
