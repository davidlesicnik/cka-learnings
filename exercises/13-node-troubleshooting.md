# Exercise: Worker Node NotReady

## Task

Node `k8s-worker1` is in `NotReady` state. Pods scheduled to it are stuck in `Unknown` or `Terminating`.

Diagnose and fix the node so it returns to `Ready`.

Constraints:
- Do not delete and recreate the node
- Do not drain or cordon the node
- Write the name of the failed component to `/opt/answers/q11.txt`

## Setup

```bash
# Run this on k8s-worker1 (ssh or kubectl debug node/)
sudo systemctl stop kubelet
```

---

## Reference Solution

```bash
# 1. Check node status
kubectl get nodes
kubectl describe node k8s-worker1 | grep -A5 Conditions

# 2. Check kubelet on the node
# SSH or use: kubectl debug node/k8s-worker1 -it --image=busybox
# then: chroot /host

systemctl status kubelet
journalctl -u kubelet -n 50

# 3. Fix
sudo systemctl start kubelet
sudo systemctl enable kubelet

# 4. Verify
kubectl get nodes  # wait for Ready

# 5. Write answer
echo "kubelet" > /opt/answers/q11.txt
```

---

## Tips

**`kubectl describe node` → Conditions block.** All conditions `Unknown` at once = kubelet stopped reporting. A single bad condition (e.g. `MemoryPressure True`) = actual resource issue on the node.

**`LastHeartbeatTime` tells you when it died.** If it's recent, something just happened. If it's old, it's been broken for a while.

**`journalctl -u kubelet -n 50` is faster than `journalctl -u kubelet | tail`.** Gets the last 50 lines directly.

**Common real causes beyond stopped kubelet:** wrong `--kubeconfig` path, expired certs, misconfigured `--config` flag. If `systemctl start kubelet` succeeds but node stays NotReady, check `journalctl -u kubelet -f` for the actual error.

**`systemctl enable kubelet`** — ensures kubelet restarts on reboot. Easy to forget under pressure; exam might check for it implicitly.

---

## Run Notes

### Run 1 — 1m50s

`kubectl get nodes` → worker1 NotReady. `kubectl describe node k8s-worker1` → all conditions `Unknown`, reason `NodeStatusUnknown: Kubelet stopped posting node status.` — kubelet dead.

SSHed into worker1, `systemctl status kubelet` confirmed stopped. `systemctl start kubelet`, node back to Ready. Clean path.
