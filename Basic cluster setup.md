# Basic Cluster Setup

This document covers:

- Creating 3 Ubuntu VMs for use in our k8s cluster
- Setting up and provisioning the nodes
- Initializing the cluster
- Joining the worker nodes to the cluster

---

## 1. Creating and Provisioning the VMs

A Kubernetes cluster needs multiple machines (nodes). In production these are real servers or cloud instances. For learning, we use lightweight VMs via **Multipass** — a tool from Canonical that spins up Ubuntu VMs quickly on macOS using the native hypervisor.

### Why 3 nodes?

A minimal realistic cluster has:

- **1 control plane node** — runs the API server, scheduler, controller manager, and etcd (cluster state database)
- **2 worker nodes** — run your actual workloads (pods)

The control plane gets more resources (2 CPU / 4GB RAM) because it runs etcd which is memory-hungry. Workers get less (2 CPU / 2GB RAM) since we're only running test workloads.

### Setup

Install multipass:

```bash
brew install multipass
```

Launch the nodes:

```bash
multipass launch 22.04 --name k8s-cp1 --cpus 2 --memory 4G --disk 15G
multipass launch 22.04 --name k8s-worker1 --cpus 2 --memory 2G --disk 10G
multipass launch 22.04 --name k8s-worker2 --cpus 2 --memory 2G --disk 10G
```

We use Ubuntu 22.04 LTS because it's well-tested with kubeadm and has long-term support.

Verify they're running and grab IPs:

```bash
multipass list
```

Note the IPs — you'll need the control plane IP (`k8s-cp1`) for the `kubeadm init` command later.

### Provisioning

Run the provisioning script:

```bash
bash scripts/provision-nodes.sh
```

This script handles all the prerequisites that Kubernetes requires on each node:

- **Disabling swap** — kubelet refuses to run if swap is enabled, because swap makes memory limits unpredictable for containers
- **Loading kernel modules** (`overlay`, `br_netfilter`) — needed for container networking to work; `overlay` is for the container filesystem, `br_netfilter` allows iptables to see bridged traffic
- **Sysctl settings** (`net.bridge.bridge-nf-call-iptables`, `ip_forward`) — enables packet forwarding between pods across nodes
- **Installing containerd** — the container runtime that actually runs containers (Kubernetes removed Docker support in 1.24, containerd is the standard)
- **Installing kubeadm, kubelet, kubectl** — the Kubernetes tooling, pinned to version 1.34 so we can practice upgrades later

The version is pinned (held) so `apt upgrade` won't accidentally bump it.

---

## 2. Initializing the Cluster

This is where we turn a plain VM into a Kubernetes control plane.

### Enter the control plane node

```bash
multipass shell k8s-cp1
sudo -i
```

> All commands from here run inside the cp1 shell unless stated otherwise.

### Verify kubeadm version

Since we pinned a specific version, confirm it's correct:

```bash
kubeadm version -o short
# Should say v1.34.10
```

### Run kubeadm init

```bash
sudo kubeadm init \
  --kubernetes-version=v1.34.10 \
  --pod-network-cidr=10.244.0.0/16 \
  --apiserver-advertise-address=192.168.252.2 \
  --control-plane-endpoint=192.168.252.2
```

**What each flag does:**

| Flag | Purpose |
|------|---------|
| `--kubernetes-version` | Explicitly set the version so it doesn't pull latest (matches our pinned packages) |
| `--pod-network-cidr` | IP range for pod-to-pod networking. `10.244.0.0/16` is the default for Flannel CNI. Each node gets a `/24` subnet from this range |
| `--apiserver-advertise-address` | IP that the API server will advertise to other nodes — must be the control plane's actual IP |
| `--control-plane-endpoint` | Stable endpoint for the API server. In HA setups this would be a load balancer. For single CP, same as the advertise address |

### What kubeadm init actually does

1. Runs preflight checks (swap off, ports available, required images pullable)
2. Generates certificates for all cluster components (stored in `/etc/kubernetes/pki/`)
3. Writes static pod manifests for control plane components into `/etc/kubernetes/manifests/`:
   - `kube-apiserver` — the REST API frontend for the entire cluster
   - `kube-controller-manager` — runs control loops (ensures desired state = actual state)
   - `kube-scheduler` — assigns pods to nodes
   - `etcd` — distributed key-value store holding all cluster state
4. Creates the kubeconfig files for these components
5. Generates a bootstrap token for nodes to join
6. Starts the kubelet, which picks up the static pod manifests and runs them

### Join commands from output

The init outputs two `kubeadm join` commands — one for additional control plane nodes and one for workers.

Example (**do not copy — the token and hash change each time**):

```bash
# Control plane join:
kubeadm join 192.168.252.2:6443 --token 38wngx.fk1j6fmy2ylkd2qo \
  --discovery-token-ca-cert-hash sha256:17e7fc6e2acdbfb4e2ea105db582d9b40d8449790ce94f9e16c39c615dd53782 \
  --control-plane

# Worker join:
kubeadm join 192.168.252.2:6443 --token 38wngx.fk1j6fmy2ylkd2qo \
  --discovery-token-ca-cert-hash sha256:17e7fc6e2acdbfb4e2ea105db582d9b40d8449790ce94f9e16c39c615dd53782
```

**About the token and hash:**

- The **token** is a short-lived credential (24h by default) that authenticates the joining node
- The **discovery-token-ca-cert-hash** lets the joining node verify it's talking to the real API server (prevents MITM attacks)
- If the token expires, generate a new one: `kubeadm token create --print-join-command`

---

## 3. Setting Up kubeconfig

The API server requires authentication. `kubeadm init` generates an admin kubeconfig at `/etc/kubernetes/admin.conf`. We copy it to the default kubectl location:

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

This config contains:
- **Cluster info** — API server URL + CA certificate
- **User credentials** — client certificate signed by the cluster CA
- **Context** — binds user to cluster (so kubectl knows where to send requests)

Verify — node shows up but `NotReady`:

```
$ kubectl get nodes
NAME      STATUS     ROLES           AGE     VERSION
k8s-cp1   NotReady   control-plane   3m14s   v1.34.10
```

`NotReady` means the node's network plugin isn't configured yet. The kubelet reports this condition because it can't set up pod networking without a CNI plugin.

---

## 4. Joining Worker Nodes

Worker nodes only run the **kubelet** (node agent) and **kube-proxy** (network rules). They don't need API server, scheduler, or etcd — they just take orders from the control plane.

From your host, shell into each worker:

```bash
multipass shell k8s-worker1
sudo -i
```

Run the `kubeadm join` command for workers (from the init output). Repeat for `k8s-worker2`.

**What kubeadm join does on a worker:**

1. Uses the token to authenticate with the API server
2. Verifies the API server's CA certificate using the hash
3. Downloads cluster info and generates a kubelet kubeconfig
4. Starts the kubelet, which registers the node with the API server

Once both are joined, verify from the control plane:

```
$ kubectl get nodes
NAME          STATUS     ROLES           AGE     VERSION
k8s-cp1       NotReady   control-plane   6m22s   v1.34.10
k8s-worker1   NotReady   <none>          29s     v1.34.10
k8s-worker2   NotReady   <none>          10s     v1.34.10
```

Workers show `ROLES: <none>` — this is just a label, not a functional difference. You can label them with:

```bash
kubectl label node k8s-worker1 node-role.kubernetes.io/worker=
kubectl label node k8s-worker2 node-role.kubernetes.io/worker=
```

---

## 5. Next Steps

All nodes show `NotReady` because there's no **CNI (Container Network Interface)** plugin installed. The CNI plugin is responsible for:

- Assigning IPs to pods from the `--pod-network-cidr` range
- Setting up routes so pods on different nodes can reach each other
- Creating virtual network interfaces for each pod

Common choices:

| CNI Plugin | Notes |
|------------|-------|
| **Flannel** | Simple, uses VXLAN overlay. Good for learning |
| **Calico** | More features (network policies, BGP). Production-grade |
| **Cilium** | eBPF-based, high performance. Growing in popularity |

Once a CNI is installed, all nodes transition to `Ready` and pods can be scheduled.
