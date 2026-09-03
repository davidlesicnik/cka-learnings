# Network Policies

By default Kubernetes has **no network isolation at all** — any pod can reach any pod in any namespace.

---

## Key Concepts

### Default behavior: allow all

Without any NetworkPolicy, the cluster is a flat network — every pod can talk to every other pod, regardless of namespace. This is simple but insecure.

### Applying a policy flips the default

The moment a NetworkPolicy selects a pod (via `podSelector`), that pod becomes **default-deny** for the policy type(s) specified (Ingress, Egress, or both). Only traffic explicitly allowed by NetworkPolicy rules gets through.

This means:
- No policy on a pod = all traffic allowed
- Any policy on a pod = only traffic matching policy rules is allowed
- Multiple policies on a pod = union of all rules (additive, never subtractive)

**Be careful:** when applying policies, you need to craft a complete set that allows all required connections. Missing a rule means broken communication with no obvious error — connections just timeout.

### Policy anatomy

```yaml
spec:
  podSelector:      # WHO does this policy apply to (target pods)
  policyTypes:      # WHAT direction: Ingress, Egress, or both
  ingress:          # RULES for incoming traffic
  - from:           # WHERE traffic can come FROM
    - podSelector:  #   pods matching these labels
    - namespaceSelector:  # pods in namespaces matching these labels
    - ipBlock:      #   raw CIDR ranges
    ports:          # ON WHICH ports
  egress:           # RULES for outgoing traffic
  - to:             # WHERE traffic can go TO (same selectors as from)
    ports:          # ON WHICH ports
```

### Combining selectors: AND vs OR

This is a common exam gotcha:

```yaml
# OR — two separate list items (either match allows traffic)
ingress:
- from:
  - podSelector:
      matchLabels: {role: client}
  - namespaceSelector:
      matchLabels: {env: prod}

# AND — single list item with both selectors (BOTH must match)
ingress:
- from:
  - podSelector:
      matchLabels: {role: client}
    namespaceSelector:
      matchLabels: {env: prod}
```

The difference is a single `-` list item (AND) vs two `-` list items (OR). Easy to mis-indent.

### Don't forget DNS with egress policies

If you apply an egress deny-all, pods can't resolve DNS. Almost always need a DNS allow rule:

```yaml
egress:
- to:
  - namespaceSelector: {}
    podSelector:
      matchLabels:
        k8s-app: kube-dns
  ports:
  - protocol: UDP
    port: 53
  - protocol: TCP
    port: 53
```

### Useful label for namespace selection

`kubernetes.io/metadata.name` is automatically set on every namespace to its name — lets you select by namespace name without adding custom labels:

```yaml
ingress:
- from:
  - namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: monitoring
```

---

## Testing the Defaults

Create a namespace and three pods to test default cluster behavior:

```bash
kubectl create namespace netpol-test

kubectl run web --image=nginx --namespace=netpol-test --labels="app=web"
kubectl expose pod web -n netpol-test --port=80 --name=web
kubectl run client --image=busybox --namespace=netpol-test --labels="role=client" --command -- sleep 3600
kubectl run other-client --image=busybox --namespace=netpol-test --labels="role=other" --command -- sleep 3600
```

Test unrestricted traffic — this returns the nginx welcome page:

```bash
kubectl exec -n netpol-test client -- wget -qO- --timeout=2 web
```

---

## Deny-All Foundation

Lock down all ingress to the namespace. Create `default-deny-ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: netpol-test
spec:
  podSelector: {}
  policyTypes:
  - Ingress
```

`podSelector: {}` with no `ingress:` rules = select all pods, allow nothing in.

Apply it:

```bash
kubectl apply -f default-deny-ingress.yaml
```

Same wget now times out — access is blocked:

```bash
kubectl exec -n netpol-test client -- wget -qO- --timeout=2 web
# wget: download timed out
# command terminated with exit code 1
```

---

## Allowing Specific Traffic

Now allow only the `client` pod to reach the `web` pod. Create `allow-client-to-web.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-client-to-web
  namespace: netpol-test
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          role: client
```

Reading the manifest: `podSelector` targets pods with `app=web`. The `ingress.from` rule allows traffic from pods with `role=client`. This is why we defined labels during pod creation (`--labels="role=client"`) — NetworkPolicies select pods entirely through labels.

Once applied, the `client` pod (label `role=client`) can reach `web`, but `other-client` (label `role=other`) cannot.
