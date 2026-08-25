# RBAC: Roles and RoleBindings

RBAC (Role-Based Access Control) is how Kubernetes controls **who** can do **what** to **which resources**. It's the authorization layer — after authentication proves your identity, RBAC decides if you're allowed to perform the action.

This document covers:

- Roles + RoleBindings (namespace-scoped)
- `kubectl auth can-i` verification
- Testing RBAC from inside a pod

---

## How RBAC Works

RBAC has four objects:

| Object | Scope | Purpose |
|--------|-------|---------|
| **Role** | Namespace | Defines permissions (verbs + resources) within a namespace |
| **ClusterRole** | Cluster-wide | Defines permissions across all namespaces |
| **RoleBinding** | Namespace | Grants a Role to a user/group/SA within a namespace |
| **ClusterRoleBinding** | Cluster-wide | Grants a ClusterRole across the entire cluster |

The pattern is always: **Subject** (who) → **Binding** (grants) → **Role** (permissions).

Subjects can be:
- **Users** — external identity (certificates, OIDC tokens). Kubernetes has no "user" object — users are defined outside the cluster
- **Groups** — collection of users (e.g. `kubeadm:cluster-admins`)
- **ServiceAccounts** — identity for pods. These ARE Kubernetes objects, namespaced

---

## A Note on admin.conf and system:masters

Since kubeadm 1.29+, `admin.conf` is no longer bound to `system:masters` — the hardcoded, unrevocable RBAC-bypass group. It's now bound to `kubeadm:cluster-admins`, a regular Group that gets cluster-admin permissions through an ordinary ClusterRoleBinding.

This matters because:
- `system:masters` bypasses RBAC entirely — no policy can restrict it, no audit can limit it
- `kubeadm:cluster-admins` uses the same RBAC mechanism as everything else — it could theoretically be revoked or scoped down

Confirm the binding exists:

```bash
kubectl get clusterrolebinding kubeadm:cluster-admins -o yaml
```

This is a security improvement — your admin access now flows through the same RBAC system you're about to learn, rather than being a magic backdoor.

---

## Step 1: Create a Role

Since Roles are namespace-scoped, create a namespace to work in:

```bash
kubectl create namespace rbac-test
```

Create a Role that grants read-only access to pods in this namespace:

```bash
kubectl create role pod-reader \
  --verb=get,list,watch \
  --resource=pods \
  --namespace=rbac-test
```

**What the verbs mean:**

| Verb | HTTP equivalent | What it allows |
|------|----------------|----------------|
| `get` | GET (single) | Read a specific pod by name |
| `list` | GET (collection) | List all pods in the namespace |
| `watch` | GET with watch=true | Stream real-time changes to pods |
| `create` | POST | Create new pods |
| `update` | PUT | Modify existing pods |
| `patch` | PATCH | Partially modify pods |
| `delete` | DELETE | Delete pods |

We only grant `get`, `list`, `watch` — read-only.

Verify the Role:

```bash
kubectl get role pod-reader -n rbac-test -o yaml
```

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: rbac-test
rules:
- apiGroups:
  - ""
  resources:
  - pods
  verbs:
  - get
  - list
  - watch
```

**About `apiGroups: [""]`** — the empty string means the "core" API group (pods, services, configmaps, secrets). Other resources live in named groups like `apps` (deployments), `networking.k8s.io` (network policies), `rbac.authorization.k8s.io` (RBAC objects themselves).

---

## Step 2: Create a ServiceAccount and RoleBinding

A Role on its own does nothing — it needs to be bound to a subject. Create a ServiceAccount:

```bash
kubectl create serviceaccount dev-user -n rbac-test
```

Bind the Role to the SA:

```bash
kubectl create rolebinding dev-user-pod-reader \
  --role=pod-reader \
  --serviceaccount=rbac-test:dev-user \
  --namespace=rbac-test
```

The `--serviceaccount` format is `namespace:name`.

### Important: Bindings don't validate subjects

Kubernetes doesn't warn you if the subject doesn't exist. The RoleBinding sits "dormant" and applies whenever a matching subject appears. This means:
- Typos in subject names silently fail (no permissions granted, no error)
- You can create bindings before the SA/user exists (useful for automation)

Verify the RoleBinding:

```bash
kubectl get rolebinding dev-user-pod-reader -n rbac-test -o yaml
```

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: dev-user-pod-reader
  namespace: rbac-test
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: pod-reader
subjects:
- kind: ServiceAccount
  name: dev-user
  namespace: rbac-test
```

**Note:** `roleRef` is immutable — you cannot change which Role a binding points to after creation. You must delete and recreate the binding. Subjects can be added/removed freely.

---

## Step 3: Verify with `kubectl auth can-i`

`can-i` lets you test permissions without actually performing the action. The `--as` flag impersonates a user/SA.

Can dev-user get pods in rbac-test?

```bash
kubectl auth can-i get pods -n rbac-test --as=system:serviceaccount:rbac-test:dev-user
# yes
```

Can dev-user delete pods? (not in our Role):

```bash
kubectl auth can-i delete pods -n rbac-test --as=system:serviceaccount:rbac-test:dev-user
# no
```

Can dev-user get pods in a different namespace? (Role is scoped to rbac-test):

```bash
kubectl auth can-i get pods -n default --as=system:serviceaccount:rbac-test:dev-user
# no
```

**The `--as` format for ServiceAccounts:** `system:serviceaccount:<namespace>:<name>`. This is the full identity string that Kubernetes uses internally when a pod authenticates with its SA token.

---

## Step 4: Verify from Inside a Pod

Real-world verification — run a pod as the SA and confirm RBAC is enforced from within.

`kubectl run` doesn't support `--serviceaccount`, so generate a manifest with dry-run and add it manually:

```bash
kubectl run test-pod -n rbac-test --image=bitnami/kubectl \
  --command --dry-run=client -o yaml -- sleep 3600 > test-pod.yaml
```

Edit `test-pod.yaml` — add `serviceAccountName: dev-user` under `spec:`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    run: test-pod
  name: test-pod
  namespace: rbac-test
spec:
  serviceAccountName: dev-user
  containers:
  - command:
    - sleep
    - "3600"
    image: bitnami/kubectl
    name: test-pod
    resources: {}
  dnsPolicy: ClusterFirst
  restartPolicy: Always
```

Apply and wait for it to be running:

```bash
kubectl apply -f test-pod.yaml
kubectl wait --for=condition=Ready pod/test-pod -n rbac-test --timeout=60s
```

**What `serviceAccountName` does:** Kubernetes mounts a signed JWT token into the pod at `/var/run/secrets/kubernetes.io/serviceaccount/token`. When kubectl runs inside the pod, it automatically uses this token to authenticate with the API server — identifying as `system:serviceaccount:rbac-test:dev-user`.

### Test from inside the pod

List pods (allowed):

```bash
kubectl exec -it test-pod -n rbac-test -- kubectl get pods
```

```
NAME       READY   STATUS    RESTARTS   AGE
test-pod   1/1     Running   0          53s
```

Delete a pod (forbidden):

```bash
kubectl exec -it test-pod -n rbac-test -- kubectl delete pod test-pod
```

```
Error from server (Forbidden): pods "test-pod" is forbidden: User "system:serviceaccount:rbac-test:dev-user" cannot delete resource "pods" in API group "" in the namespace "rbac-test"
```

RBAC is enforced — the pod can only do what its ServiceAccount's Role allows.

---

## Cleanup

```bash
kubectl delete namespace rbac-test
```

Deleting the namespace removes everything inside it — the pod, SA, Role, and RoleBinding.
