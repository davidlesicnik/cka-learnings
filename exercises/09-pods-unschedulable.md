# Exercise: Pods Unschedulable — Broken Scheduler

## Task

Deployment `analytics` in namespace `reports` has 3 replicas using `nginx:1.27`. All pods are `Pending`. `kubectl describe pod` shows no events at all.

Diagnose and fix so all 3 pods reach `Running`.

Constraints:
- Do not delete or recreate the `analytics` Deployment
- Do not modify any workload or node object — fix must be on the cluster side
- Write the name of the failing component to `/opt/answers/q7.txt`
- Pods running in other namespaces must stay running

---

## Setup

```bash
kubectl create namespace reports
mkdir -p /opt/answers

# backup, kept outside the manifests directory
cp /etc/kubernetes/manifests/kube-scheduler.yaml /root/kube-scheduler.yaml.orig

# introduce the fault
sed -i 's|- --kubeconfig=/etc/kubernetes/scheduler.conf|- --kubeconfig=/etc/kubernetes/scheduler.conff|' /etc/kubernetes/manifests/kube-scheduler.yaml

# give the kubelet time to restart the component before the workload exists
sleep 30

kubectl create deployment analytics -n reports --image=nginx:1.27 --replicas=3
```

---

## Reference Solution

### Step 1: Check pod events

```bash
kubectl describe pod -n reports analytics-<hash>
# Events: <none>
```

No events = scheduler isn't producing them. Scheduler is down.

### Step 2: Check kube-system components

```bash
kubectl get pods -n kube-system
```

Look for anything not `Running`:

```
kube-scheduler-k8s-cp1   0/1   CrashLoopBackOff   4   2m18s
```

### Step 3: Read scheduler logs

```bash
kubectl logs kube-scheduler-k8s-cp1 -n kube-system
```

```
E1005 10:01:23.594435  1 run.go:72] "command failed" err="stat /etc/kubernetes/scheduler.conff: no such file or directory"
```

Typo: `scheduler.conff` → should be `scheduler.conf`.

### Step 4: Fix the static pod manifest

```bash
vi /etc/kubernetes/manifests/kube-scheduler.yaml
# Fix: --kubeconfig=/etc/kubernetes/scheduler.conff → scheduler.conf
```

Kubelet detects the file change and restarts the scheduler automatically. Wait ~15 seconds:

```bash
kubectl get pods -n kube-system | grep scheduler
# kube-scheduler-k8s-cp1   1/1   Running
```

### Step 5: Verify analytics pods

```bash
kubectl get pods -n reports
# All 3 Running
```

### Step 6: Write answer

```bash
echo "kube-scheduler" > /opt/answers/q7.txt
```

---

## Tips

**No events on a Pending pod = scheduler is not running.** Scheduling events (`Successfully assigned`, `FailedScheduling`) come from the scheduler. If there are no events at all, the scheduler never saw the pod — it's dead or crashed.

**Always check `kubectl get pods -n kube-system` when cluster-wide behavior breaks.** One of the four control plane components (apiserver, etcd, controller-manager, scheduler) will show `CrashLoopBackOff` or `Error`.

**kube-scheduler is a static pod.** Its manifest lives at `/etc/kubernetes/manifests/kube-scheduler.yaml`. Edit the file — kubelet restarts the pod automatically within seconds. No `kubectl delete` needed.

**`kubectl logs` on a crashing static pod often gives the root cause directly.** The error message usually names the bad flag or missing file.

---

## Run Notes

### Run 1 — 3m15s

Saw pods Pending with no events → immediately suspected scheduler. Checked kube-system → scheduler in `CrashLoopBackOff`. Checked logs → typo in config path (`scheduler.conff`). Fixed in manifest. Pods went Running. Clean path.
