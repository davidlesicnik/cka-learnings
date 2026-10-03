# Exercise: RBAC — Role and RoleBinding

## Task

Create a ServiceAccount `deploy-bot` in namespace `apps`. Create a Role that allows only `get`, `list`, and `create` on deployments in that namespace, and bind it to the ServiceAccount. Use `kubectl auth can-i` to verify it cannot delete deployments and cannot list deployments in `default`.

---

## Reference Solution

### Imperative (fastest on exam)

```bash
kubectl create namespace apps
kubectl create serviceaccount deploy-bot -n apps
kubectl create role deploy-bot -n apps --verb=get,list,create --resource=deployments
kubectl create rolebinding deploy-bot -n apps --role=deploy-bot --serviceaccount=apps:deploy-bot
```

`--serviceaccount` format is `namespace:name`.

### Verify

```bash
# Should return "yes"
kubectl auth can-i get deployments -n apps --as=system:serviceaccount:apps:deploy-bot

# Should return "no"
kubectl auth can-i delete deployments -n apps --as=system:serviceaccount:apps:deploy-bot

# Should return "no" (role is namespace-scoped to apps, not default)
kubectl auth can-i list deployments -n default --as=system:serviceaccount:apps:deploy-bot
```

### YAML reference (if imperative not available)

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: apps
  name: deploy-bot
rules:
- apiGroups: ["apps"]
  resources: ["deployments"]   # plural — "deployment" silently does nothing
  verbs: ["get", "list", "create"]
```

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: deploy-bot
  namespace: apps
subjects:
- kind: ServiceAccount
  name: deploy-bot
  apiGroup: ""                 # empty string for ServiceAccounts, NOT rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: deploy-bot
  apiGroup: rbac.authorization.k8s.io
```

---

## Tips

**`resources` must be plural.** `"deployment"` silently creates a role that matches nothing. `"deployments"` is correct. Same applies to `"pods"`, `"services"`, etc. When in doubt, check with `kubectl api-resources | grep deploy`.

**`apiGroup: ""` for ServiceAccount subjects.** The `subjects[].apiGroup` field for a ServiceAccount must be `""` (empty string), not `rbac.authorization.k8s.io`. Using the wrong group means the binding silently doesn't apply. Users use `rbac.authorization.k8s.io`, ServiceAccounts use `""`.

**Deployments are in the `apps` apiGroup**, not core (`""`). When writing a Role for deployments, `apiGroups: ["apps"]` is required. For pods, services, configmaps — use `apiGroups: [""]`.

**Test specific permissions, not `--list`.** `--list` dumps everything and is noisy. Test exactly what the task asks:
```bash
kubectl auth can-i <verb> <resource> -n <namespace> --as=system:serviceaccount:<ns>:<name>
```

**Impersonation format for ServiceAccounts:** `system:serviceaccount:<namespace>:<name>` — always this exact prefix.

---

## Run Notes

### Run 1 — 6 minutes

Used YAML instead of imperative commands. Bound to `kind: User` instead of `kind: ServiceAccount` in the RoleBinding subjects — binding silently applied but permissions didn't work. Fixed after checking.

Also used `resources: ["deployment"]` (singular) and `apiGroup: rbac.authorization.k8s.io` on the subject — both wrong. The `--list` output not showing deployments was the signal the role wasn't working, but didn't catch it at the time.

**Key lesson:** Use imperative commands — `kubectl create role` and `kubectl create rolebinding` handle the pluralization and apiGroup fields automatically, removing both bugs above.
