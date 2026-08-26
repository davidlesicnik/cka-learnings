# Troubleshooting

Real issues encountered while working through these exercises. Not manufactured scenarios — actual problems that came up and how they were resolved.

---

## CoreDNS CrashLoopBackOff After CNI Swap

**When:** During the network policies exercise, freshly created services couldn't be resolved.

**Symptoms:**

```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns
```

```
NAME                       READY   STATUS             RESTARTS          AGE
coredns-589f44dc88-4c6gl   0/1     Running            704 (3h12m ago)   5d7h
coredns-589f44dc88-smz6k   0/1     CrashLoopBackOff   708 (4m51s ago)   5d7h
```

**Root cause:** CoreDNS pods had stale IPs from the old Flannel IP range (`10.244.0.x`, `10.244.2.x`), while Calico pods were on a different range (`10.244.71.x`, `10.244.126.x`, `10.244.194.x`). The leftover pod IPs couldn't route to the Kubernetes API service (`10.96.0.1:443`).

The logs confirmed it:

```
[ERROR] plugin/kubernetes: Failed to watch: ... dial tcp 10.96.0.1:443: connect: no route to host
```

**Why it happened:** When we swapped Flannel for Calico (see [03-flannel-to-calico](03-flannel-to-calico.md)), CoreDNS pods were already running. They kept their old network interfaces and IPs assigned by Flannel. Calico only assigns new IPs to newly created pods — existing pods retain their stale networking until deleted.

**Fix:** Delete both CoreDNS pods — the Deployment recreates them, and Calico assigns proper IPs:

```bash
kubectl delete pod -n kube-system -l k8s-app=kube-dns
```

Verify they come back healthy with Calico-range IPs:

```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
```

```
NAME                       READY   STATUS    RESTARTS   AGE   IP              NODE
coredns-589f44dc88-c67g9   1/1     Running   0          17s   10.244.126.5    k8s-worker2
coredns-589f44dc88-tklv4   1/1     Running   0          17s   10.244.194.67   k8s-worker1
```

**Lesson:** After a CNI swap, any pods that were running before the swap still have stale networking. Safest approach: restart all pods in `kube-system` after installing the new CNI. At minimum, always restart CoreDNS — if DNS is broken, everything looks broken.
