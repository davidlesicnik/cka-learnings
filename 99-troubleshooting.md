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

---

## Network Policies Blocking Despite Being Allowed

**When:** During the network policies exercise, after creating a deny-all policy then adding a policy to allow `role=client`, traffic was still blocked.

**Symptoms:**

```bash
kubectl apply -f allow-client-to-web.yaml
# networkpolicy.networking.k8s.io/allow-client-to-web created

kubectl exec -n netpol-test client -- wget -qO- --timeout=2 web
# wget: download timed out
# command terminated with exit code 1
```

### Debugging steps

**1. Verify pod labels match policy selectors:**

```bash
kubectl get pod client -n netpol-test --show-labels
```

```
NAME     READY   STATUS    RESTARTS        AGE   LABELS
client   1/1     Running   97 (8m4s ago)   8d    role=client
```

```bash
kubectl -n netpol-test describe networkpolicy allow-client-to-web
```

```
Spec:
  PodSelector:     app=web
  Allowing ingress traffic:
    To Port: <any> (traffic allowed to all ports)
    From:
      PodSelector: role=client
  Not affecting egress traffic
  Policy Types: Ingress
```

Labels match — pod has `role=client`, policy selects `role=client`.

**2. Verify the web server is actually serving:**

```bash
kubectl exec -n netpol-test web -- curl -s -o /dev/null -w '%{http_code}\n' localhost
# 200
```

Web server is fine — problem is network-level, not application-level.

**3. Isolate which policy is causing the block:**

Deleted the default-deny policy — still broken. Deleted the allow-client-to-web policy — traffic works again. Re-applied just allow-client-to-web — broken again.

This confirmed the allow policy itself was the problem, even though selectors looked correct.

**4. Check Calico's view of the policy:**

```bash
kubectl -n calico-system logs calico-node-vqxx4 | grep -iE 'allow-client-to-web'
```

```
2026-09-03 08:26:51.343 [INFO][82] felix/label_inheritance_index.go 187: Updating selector id=Policy(Name=allow-client-to-web, Namespace=netpol-test, Kind=KubernetesNetworkPolicy) selector=((projectcalico.org/orchestrator == "k8s" && app == "web") && projectcalico.org/namespace == "netpol-test")
```

Calico sees the policy and applied it correctly.

**5. Check if the client pod's IP is in Calico's ipsets:**

```bash
kubectl exec -n calico-system calico-node-vqxx4 -- ipset list | grep -B5 10.244.194.66
```

Empty result. The client pod's IP wasn't in any of Calico's ipsets — Calico didn't know this pod existed in its allow rules, so it couldn't match it against the policy selector.

**Root cause:** Calico's ipset was stale and didn't include the client pod. This is likely a side effect of the pods being old (8 days, 97 restarts) — they predated the Calico installation, similar to the CoreDNS issue above.

**Fix:** Delete all calico-node pods to force a full rebuild of ipsets:

```bash
kubectl delete pod -n calico-system -l k8s-app=calico-node
```

After 20-30 seconds, verify the pod IP is now in the ipset:

```bash
kubectl exec -n calico-system calico-node-8q99d -- ipset list | grep -B5 10.244.194.66
```

```
Header: family inet hashsize 1024 maxelem 1048576 bucketsize 12 initval 0xc4a4c29d
Size in memory: 504
References: 1
Number of entries: 1
Members:
10.244.194.66
```

Pod is now in the ipset, and the wget works.

**Lesson:** When NetworkPolicies look correct but don't work, check Calico's ipsets. Stale pods (from before the CNI was installed, or with many restarts) may not be tracked properly. Restarting calico-node pods forces a full resync of ipsets. Also consider recreating the affected application pods themselves — fresh pods get properly registered.
