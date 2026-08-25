# RBAC: ClusterRoles and ClusterRoleBindings

This continues from the previous RBAC doc. Where Roles are namespace-scoped, **ClusterRoles** apply cluster-wide — they're needed for resources that don't live in any namespace.

---

## When Do You Need a ClusterRole?

Some resources are **cluster-scoped** — they exist outside any namespace:

| Cluster-scoped resources | Why they're not namespaced |
|--------------------------|---------------------------|
| Nodes | Physical/virtual machines, shared by all namespaces |
| PersistentVolumes | Storage is provisioned at cluster level, claimed by PVCs in namespaces |
| Namespaces | You can't put a namespace inside a namespace |
| ClusterRoles / ClusterRoleBindings | Cluster-wide permissions |
| StorageClasses | Cluster-level storage configuration |
| IngressClasses | Cluster-level ingress configuration |

A namespace-scoped Role simply cannot grant access to these resources. You must use a ClusterRole.

**Bonus use:** ClusterRoles can also be used for namespaced resources when you want the same permissions in ALL namespaces (e.g. a monitoring tool that needs to list pods everywhere). Binding a ClusterRole with a ClusterRoleBinding grants it everywhere; binding it with a RoleBinding limits it to one namespace.

---

## Creating a ClusterRole

Create a ClusterRole granting read-only access to nodes:

```bash
kubectl create clusterrole node-reader \
  --verb=get,list,watch \
  --resource=nodes
```

Verify the YAML:

```bash
kubectl get clusterrole node-reader -o yaml
```

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: node-reader
rules:
- apiGroups:
  - ""
  resources:
  - nodes
  verbs:
  - get
  - list
  - watch
```

Notice there's no `namespace:` field — ClusterRoles literally cannot have one, because they apply to cluster-scoped resources.

---

## The "Role for Cluster Resources" Trap

Creating a namespace-scoped Role for a cluster-scoped resource doesn't error:

```bash
kubectl create role bad-role --verb=get --resource=nodes
# role.rbac.authorization.k8s.io/bad-role created
```

The Role object exists. You can even create a RoleBinding for it. Everything looks fine — until you actually try to use the permission and get `Forbidden`.

This is similar to the Flannel/NetworkPolicy trap from earlier: Kubernetes accepts the object without complaint, but it's silently useless. The lesson: **always match the scope of your Role to the scope of the resource.**

| Resource scope | Use |
|----------------|-----|
| Namespaced resources (pods, services, deployments) | Role + RoleBinding |
| Cluster resources (nodes, PVs, namespaces) | ClusterRole + ClusterRoleBinding |
| Namespaced resources across ALL namespaces | ClusterRole + ClusterRoleBinding |
| ClusterRole limited to one namespace | ClusterRole + RoleBinding (in target namespace) |

---

## Binding a ClusterRole

To actually grant the `node-reader` permissions to a subject, create a ClusterRoleBinding:

```bash
kubectl create clusterrolebinding dev-node-reader \
  --clusterrole=node-reader \
  --serviceaccount=rbac-test:dev-user
```

Verify:

```bash
kubectl auth can-i list nodes --as=system:serviceaccount:rbac-test:dev-user
# yes
```

Without the binding, same check returns `no` — the ClusterRole alone grants nothing.

---

## RoleBinding + ClusterRole: Scoping Down

A RoleBinding can reference a ClusterRole instead of a Role. When it does, the ClusterRole's permissions are **limited to the RoleBinding's namespace** — you get the ClusterRole's permission set, but only within that one namespace.

### Why this is useful

Imagine you have 10 teams, each with their own namespace. Every team needs the same permissions: read pods, read services, read configmaps. Without this pattern, you'd need to:

1. Create identical Role objects in all 10 namespaces
2. Maintain them in sync when permissions change

With a ClusterRole + RoleBinding per namespace:

1. Create ONE ClusterRole defining the shared permissions
2. Create a RoleBinding in each namespace pointing to that ClusterRole
3. When permissions change, update one object — all namespaces pick it up

### Example

Create a ClusterRole for common read access:

```bash
kubectl create clusterrole common-reader \
  --verb=get,list,watch \
  --resource=pods,services,configmaps
```

Bind it in a specific namespace using a RoleBinding (not ClusterRoleBinding):

```bash
kubectl create rolebinding team-a-reader \
  --clusterrole=common-reader \
  --serviceaccount=team-a:dev-user \
  --namespace=team-a
```

Now `dev-user` can read pods/services/configmaps in `team-a` only — not in `team-b` or anywhere else, despite `common-reader` being a ClusterRole.

### Key distinction

| Binding type | Effect with ClusterRole |
|--------------|------------------------|
| **ClusterRoleBinding** | Grants permissions in ALL namespaces + cluster-scoped resources |
| **RoleBinding** | Grants permissions in ONLY the binding's namespace |

Same ClusterRole, different binding type = completely different scope. The ClusterRole is reusable; the binding controls where it applies.

> **Note:** This only works for namespaced resources in the ClusterRole. If the ClusterRole includes cluster-scoped resources (nodes, PVs), those permissions are silently ignored when bound via a RoleBinding — you can't namespace-scope access to something that isn't namespaced.

---

## ClusterRole vs Role: Decision Flowchart

```
Is the resource cluster-scoped (nodes, PVs, namespaces)?
  → Yes: ClusterRole + ClusterRoleBinding

Is it namespaced but you need access in ALL namespaces?
  → Yes: ClusterRole + ClusterRoleBinding

Is it namespaced and you only need access in ONE namespace?
  → ClusterRole + RoleBinding (reusable role, limited scope)
  → OR Role + RoleBinding (role tied to that namespace)
```

The last option (ClusterRole + RoleBinding) is common in practice — you define permissions once as a ClusterRole, then bind it per-namespace with individual RoleBindings. This avoids duplicating Role objects across namespaces.
