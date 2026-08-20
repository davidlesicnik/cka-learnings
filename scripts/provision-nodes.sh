#!/usr/bin/env bash
# Run this FROM YOUR MAC — it provisions all 3 Multipass VMs for kubeadm.
set -euo pipefail

NODES=(k8s-cp1 k8s-worker1 k8s-worker2)
K8S_VERSION="1.34"

for node in "${NODES[@]}"; do
  echo "=================================================="
  echo ">>> Provisioning $node"
  echo "=================================================="

  multipass exec "$node" -- bash -c '
    set -euo pipefail

    echo "--- Disabling swap ---"
    sudo swapoff -a
    sudo sed -i "/swap/d" /etc/fstab

    echo "--- Kernel modules + sysctl ---"
    cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
    sudo modprobe overlay
    sudo modprobe br_netfilter

    cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
    sudo sysctl --system

    echo "--- Installing containerd ---"
    sudo apt-get update -qq
    sudo apt-get install -y -qq containerd
    sudo mkdir -p /etc/containerd
    containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
    sudo sed -i "s/SystemdCgroup = false/SystemdCgroup = true/" /etc/containerd/config.toml
    sudo systemctl restart containerd
    sudo systemctl enable containerd -q

    echo "--- Installing kubeadm/kubelet/kubectl ---"
    sudo apt-get install -y -qq apt-transport-https ca-certificates curl gpg
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v'"$K8S_VERSION"'/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v'"$K8S_VERSION"'/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list

    sudo apt-get update -qq
    sudo apt-get install -y -qq kubelet kubeadm kubectl
    sudo apt-mark hold kubelet kubeadm kubectl > /dev/null

    echo "--- Done on $(hostname) ---"
  '
done

echo ""
echo "=================================================="
echo "All nodes provisioned. Next steps:"
echo "  1. multipass shell k8s-cp1"
echo "  2. sudo kubeadm init --pod-network-cidr=10.244.0.0/16 \\"
echo "       --apiserver-advertise-address=<cp1-ip> \\"
echo "       --control-plane-endpoint=<cp1-ip>"
echo "=================================================="
