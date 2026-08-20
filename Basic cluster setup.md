# Basic Cluster Setup

This document covers:

- Creating 3 Ubuntu VMs for use in our k8s cluster
- Setting up and provisioning the nodes
- Initializing the cluster
- Joining the worker nodes to the cluster

## 1. Creating and Provisioning the VMs

Install multipass on Mac to create 3 Ubuntu VMs:

```bash
brew install multipass
```

Launch the nodes:

```bash
multipass launch 22.04 --name k8s-cp1 --cpus 2 --memory 4G --disk 15G
multipass launch 22.04 --name k8s-worker1 --cpus 2 --memory 2G --disk 10G
multipass launch 22.04 --name k8s-worker2 --cpus 2 --memory 2G --disk 10G
```

Verify they're running and grab IPs:

```bash
multipass list
```

Run the provisioning script — this installs all prerequisites and Kubernetes 1.34 (version is configurable via variable in script):

```bash
bash scripts/provision-nodes.sh
```

## 2. Initializing the Cluster

Enter the control plane node shell:

```bash
multipass shell k8s-cp1
sudo -i
```

> All commands from here should be run inside the cp1 shell unless stated otherwise.

Verify the installed kubeadm version (we pinned an older version):

```bash
kubeadm version -o short
# Should say v1.34.10
```

Initialize the cluster using that version:

```bash
sudo kubeadm init \
  --kubernetes-version=v1.34.10 \
  --pod-network-cidr=10.244.0.0/16 \
  --apiserver-advertise-address=192.168.252.2 \
  --control-plane-endpoint=192.168.252.2
```

Once finished, it writes all basic cluster manifests into `/etc/kubernetes/` and outputs two `kubeadm join` commands — one for control plane nodes and one for workers.

Example output (**do not copy — the hash will change each time**):

```bash
# Control plane join:
kubeadm join 192.168.252.2:6443 --token 38wngx.fk1j6fmy2ylkd2qo \
  --discovery-token-ca-cert-hash sha256:17e7fc6e2acdbfb4e2ea105db582d9b40d8449790ce94f9e16c39c615dd53782 \
  --control-plane

# Worker join:
kubeadm join 192.168.252.2:6443 --token 38wngx.fk1j6fmy2ylkd2qo \
  --discovery-token-ca-cert-hash sha256:17e7fc6e2acdbfb4e2ea105db582d9b40d8449790ce94f9e16c39c615dd53782
```

## 3. Setting Up kubeconfig

Copy the kubeconfig so kubectl works:

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

Verify — node shows up but `NotReady` (networking not yet configured):

```
$ kubectl get nodes
NAME      STATUS     ROLES           AGE     VERSION
k8s-cp1   NotReady   control-plane   3m14s   v1.34.10
```

## 4. Joining Worker Nodes

From your host, shell into each worker:

```bash
multipass shell k8s-worker1
sudo -i
```

Run the `kubeadm join` command for workers (from the init output). Repeat for `k8s-worker2`.

Once both are joined, verify from the control plane:

```
$ kubectl get nodes
NAME          STATUS     ROLES           AGE     VERSION
k8s-cp1       NotReady   control-plane   6m22s   v1.34.10
k8s-worker1   NotReady   <none>          29s     v1.34.10
k8s-worker2   NotReady   <none>          10s     v1.34.10
```

All nodes show `NotReady` — next step is installing a CNI plugin (e.g., Flannel/Calico) to bring networking up.
