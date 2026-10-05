# Exercise: DNS Resolution Broken for Cluster Services

## Task

Service `ledger` in namespace `payments` has healthy backing pods and endpoints, but applications in the cluster report that `ledger.payments.svc.cluster.local` cannot be resolved. Pods can still reach external names like `kubernetes.io`.

Diagnose and fix so the name resolves from inside the cluster.

Constraints:
- Do not modify the `ledger` Service or Deployment
- Do not deploy a replacement DNS server or edit any pod's `/etc/resolv.conf`
- Write the ClusterIP that `ledger.payments.svc.cluster.local` resolves to into `/opt/answers/q8.txt`

---

## Setup

```bash
mkdir -p /opt/answers
kubectl create namespace payments
kubectl create deployment ledger -n payments --image=nginx:1.27 --replicas=2
kubectl expose deployment ledger -n payments --port=80

# back up the original, then introduce the fault
kubectl get cm coredns -n kube-system -o yaml > /root/coredns-cm.orig.yaml
kubectl get cm coredns -n kube-system -o yaml \
  | sed 's/kubernetes cluster.local/kubernetes cluster.locall/' \
  | kubectl replace -f -
kubectl rollout restart deployment coredns -n kube-system
kubectl rollout status deployment coredns -n kube-system
```

---

## Reference Solution

### Step 1: Confirm the failure and scope

```bash
kubectl run test --image=busybox:1.36 --rm -it --restart=Never -- \
  nslookup ledger.payments.svc.cluster.local
# Server failure or NXDOMAIN

kubectl run test --image=busybox:1.36 --rm -it --restart=Never -- \
  nslookup kubernetes.io
# Resolves fine
```

External DNS works, cluster-local fails → CoreDNS is running but the `cluster.local` zone is misconfigured.

### Step 2: Check CoreDNS pods and logs

```bash
kubectl get pods -n kube-system | grep coredns
# Running — not the issue

kubectl logs -n kube-system -l k8s-app=coredns
# No errors — CoreDNS starts fine with a broken Corefile zone
```

### Step 3: Inspect the CoreDNS ConfigMap

```bash
kubectl get cm coredns -n kube-system -o yaml
```

Look at the `Corefile` key. Find the kubernetes plugin line:

```
kubernetes cluster.locall in-addr.arpa ip6.arpa {
#                      ↑ extra 'l'
```

### Step 4: Fix the typo

```bash
kubectl edit cm coredns -n kube-system
# Change: kubernetes cluster.locall
# To:     kubernetes cluster.local
```

### Step 5: Restart CoreDNS to pick up the change

```bash
kubectl rollout restart deployment coredns -n kube-system
kubectl rollout status deployment coredns -n kube-system
```

### Step 6: Verify and write answer

```bash
kubectl run test --image=busybox:1.36 --rm -it --restart=Never -- \
  nslookup ledger.payments.svc.cluster.local
# Returns the ClusterIP

kubectl get svc ledger -n payments
# CLUSTER-IP: 10.x.x.x

echo "10.x.x.x" > /opt/answers/q8.txt
```

---

## Tips

**External DNS works but `cluster.local` fails = Corefile zone misconfigured.** CoreDNS handles external names via the `forward` plugin (separate from the `kubernetes` plugin). If external resolves but cluster-local doesn't, the `kubernetes cluster.local` line in the Corefile is broken — CoreDNS doesn't crash, it just ignores the zone it can't parse.

**CoreDNS is a Deployment, not a static pod.** After editing the ConfigMap, run `kubectl rollout restart deployment coredns -n kube-system`. Pods don't auto-reload on ConfigMap changes.

**The Corefile is inside the ConfigMap under the key `Corefile`.** `kubectl get cm coredns -n kube-system -o yaml` shows it. Compare against the docs reference: kubernetes.io → "Customizing DNS Service".

**`kubectl logs -l k8s-app=coredns` logs all CoreDNS pods at once.** Useful when the Deployment has 2 replicas.

---

## Run Notes

### Run 1 — 6 minutes

Pods healthy, service had endpoints, logs clean. No obvious signal. Crawled the CoreDNS docs page, compared the ConfigMap to the reference Corefile — spotted `cluster.locall` (extra `l`). Fixed, restarted, resolved.

Key lesson: CoreDNS doesn't log errors for a typo in the zone name — it just silently fails to serve that zone. The only signal is "cluster-local resolution broken, external works."
