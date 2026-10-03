# Exercise: NetworkPolicy — Pick the Correct Policy

## Task

Namespace `db` has pods labeled `app=postgres`. Namespaces labeled `team=backend` contain pods labeled `app=api`. The directory `~/netpol` has four NetworkPolicy manifests. Do not modify or delete any of them.

Apply the one manifest that is the least permissive and still satisfies all of these:

- Selects only the `app=postgres` pods in `db`
- Allows ingress only from `app=api` pods that are in namespaces labeled `team=backend`
- Allows only TCP 5432
- All other ingress to those pods is denied, and egress is not affected

---

## Task Setup

```bash
kubectl create ns db; kubectl create ns backend-ns; kubectl create ns other-ns
kubectl label ns backend-ns team=backend; kubectl label ns other-ns team=frontend
kubectl run postgres -n db --image=busybox:1.36 --labels=app=postgres -- nc -lk -p 5432
kubectl run api -n backend-ns --image=busybox:1.36 --labels=app=api -- sleep 3600
kubectl run api -n other-ns --image=busybox:1.36 --labels=app=api -- sleep 3600

mkdir -p ~/netpol && cd ~/netpol
mk() { cat > $1 <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: $2
  namespace: db
spec:
  podSelector:
    matchLabels:
      app: postgres
  policyTypes: [$3]
  ingress:
  - from:
$4
$5
EOF
}
SEL='    - namespaceSelector: {matchLabels: {team: backend}}'
POD='      podSelector: {matchLabels: {app: api}}'
PORT='    ports: [{protocol: TCP, port: 5432}]'

mk policy-1.yaml allow-api-1 Ingress "$SEL
    - podSelector: {matchLabels: {app: api}}" "$PORT"
mk policy-2.yaml allow-api-2 Ingress "$SEL
$POD" ""
mk policy-3.yaml allow-api-3 Ingress "$SEL
$POD" "$PORT"
mk policy-4.yaml allow-api-4 "Ingress, Egress" "$SEL
$POD" "$PORT"
```

---

## Reference Solution

**Answer: `policy-3.yaml`**

### How to evaluate each policy fast

`cat` each file and check three things in this order:

**1. `policyTypes` — does it touch egress?**
- `policy-4` has `Ingress, Egress` with no egress rules → deny-all egress. Task says egress must not be affected. ❌ Eliminated.

**2. `ports` — is TCP 5432 specified?**
- `policy-2` has no `ports` block → allows all ports from matching pods. ❌ Eliminated.

**3. AND vs OR selector — are both selectors on the same list item or separate?**
```yaml
# OR — two list items, either match allows traffic
from:
  - namespaceSelector: {matchLabels: {team: backend}}   # - here
  - podSelector: {matchLabels: {app: api}}              # - here too

# AND — one list item, both must match
from:
  - namespaceSelector: {matchLabels: {team: backend}}   # - here
    podSelector: {matchLabels: {app: api}}              # no - here, indented under same item
```
- `policy-1` uses OR → allows any pod in a `team=backend` namespace **or** any pod labeled `app=api` anywhere. Too permissive. ❌ Eliminated.
- `policy-3` uses AND → only `app=api` pods **that are also** in a `team=backend` namespace. ✅

```bash
kubectl apply -f ~/netpol/policy-3.yaml
```

### Verify

```bash
# Should succeed (api in backend-ns, which has team=backend)
kubectl exec -n backend-ns api -- nc -z -w2 $(kubectl get pod postgres -n db -o jsonpath='{.status.podIP}') 5432 && echo "allowed"

# Should fail (api in other-ns, which has team=frontend)
kubectl exec -n other-ns api -- nc -z -w2 $(kubectl get pod postgres -n db -o jsonpath='{.status.podIP}') 5432 && echo "allowed" || echo "blocked"
```

---

## Tips

**AND vs OR is the most common NetworkPolicy gotcha.** One `-` list item = AND (both selectors must match). Two `-` list items = OR (either selector allows traffic). The indentation difference is one space — easy to misread under pressure. Always count the `-` dashes.

**No `ports` block = all ports allowed.** If the task requires a specific port, the policy must have an explicit `ports` entry. A policy without it is more permissive than it looks.

**`policyTypes: [Ingress, Egress]` with no egress rules = deny-all egress.** Adding `Egress` to `policyTypes` without an `egress:` block doesn't mean "ignore egress" — it means "deny all egress." Only include `Egress` if you have egress rules to go with it.

**Use `diff` to spot differences between similar policies:**
```bash
diff ~/netpol/policy-1.yaml ~/netpol/policy-3.yaml
```

---

## Run Notes

### Run 1 — 4 minutes

Chose `policy-1` — looked right at a glance. Missed that `namespaceSelector` and `podSelector` were two separate list items (OR), not one combined item (AND). Result: too permissive — pods in other namespaces labeled `app=api` could also reach postgres.

Correct answer was `policy-3`: AND combo + port filter + Ingress only.

**Key lesson:** When scanning a policy, look at the `-` dashes in the `from:` block first. One dash = AND. Two dashes = OR. This one character is the difference between correct and wrong.
