# Exercise: ClusterRole Scoped with RoleBinding

## Task

Create the following RBAC setup:

1. A `ClusterRole` named `secret-reader` that allows `get`, `list`, `watch` on `secrets`
2. A `ServiceAccount` named `vault-agent` in namespace `vault`
3. A `RoleBinding` (not ClusterRoleBinding) in namespace `vault` that grants `vault-agent` the `secret-reader` ClusterRole — but **only within the `vault` namespace**

Verify:
- `vault-agent` can list secrets in `vault` namespace
- `vault-agent` cannot list secrets in `default` namespace

Write `allowed` or `denied` for each check to `/opt/answers/q12.txt` (one per line, vault first).

---

## Reference Solution

```bash
# 1. ClusterRole
kubectl create clusterrole secret-reader --verb=get,list,watch --resource=secrets

# 2. ServiceAccount
kubectl create namespace vault
kubectl create serviceaccount vault-agent -n vault

# 3. RoleBinding (not ClusterRoleBinding — scopes to vault namespace only)
kubectl create rolebinding vault-secret-reader \
  -n vault \
  --clusterrole=secret-reader \
  --serviceaccount=vault:vault-agent

# Verify
kubectl auth can-i list secrets -n vault \
  --as=system:serviceaccount:vault:vault-agent

kubectl auth can-i list secrets -n default \
  --as=system:serviceaccount:vault:vault-agent

# Write answer
printf "allowed\ndenied\n" > /opt/answers/q12.txt
```

---

## Tips

**RoleBinding + ClusterRole = namespace-scoped.** Using a `RoleBinding` (not `ClusterRoleBinding`) to bind a ClusterRole restricts it to the RoleBinding's namespace. This is the intended pattern for reusable permission sets.

**`--clusterrole` flag on `kubectl create rolebinding`.** It accepts either `--role` or `--clusterrole` — the result is still a `RoleBinding` object either way.

**`--as=system:serviceaccount:<ns>:<name>` format.** Exact prefix required. `system:serviceaccount:vault:vault-agent` — namespace first, then name.

**`auth can-i` returns `yes`/`no`, not `allowed`/`denied`.** The task asks you to write the English words — don't just pipe the command output directly.

**Trap:** creating a `ClusterRoleBinding` instead of `RoleBinding` grants access cluster-wide. Read the task carefully.

---

## Run Notes

