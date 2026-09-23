# Jobs and CronJobs

Jobs run a pod (or set of pods) to completion, then stop. Unlike Deployments — which keep pods running indefinitely — Jobs are for finite work: batch processing, database migrations, one-off scripts.

CronJobs wrap a Job on a schedule, spawning a new Job each time the schedule fires.

The object hierarchy:
```
CronJob → Job → Pod(s)
```

---

## Job Control Fields

Three fields control how a Job runs:

| Field | Meaning |
|-------|---------|
| `completions` | Total successful pod completions needed before the Job is done |
| `parallelism` | How many pods run concurrently |
| `backoffLimit` | How many failed pods are allowed before the Job gives up and marks itself `Failed` |

With `completions: 3` and `parallelism: 2`: two pods start in parallel, once the first finishes a third starts, Job completes when all 3 succeed.

### restartPolicy

Jobs can't use `restartPolicy: Always` (that would run forever, defeating the point). Two valid options:

| Value | Behaviour on failure |
|-------|---------------------|
| `Never` | Create a new pod on failure. Counts against `backoffLimit` |
| `OnFailure` | Restart the same pod. Increments the container restart count |

`Never` is typical for batch work — each attempt gets a fresh pod and clean state.

---

## Exercise: Basic Job

Create `job-demo.yaml`:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: job-demo
spec:
  completions: 3
  parallelism: 2
  backoffLimit: 4
  template:
    spec:
      containers:
        - name: worker
          image: busybox
          command: ["sh", "-c", "echo Processing item; sleep 5"]
      restartPolicy: Never
```

```bash
kubectl apply -f job-demo.yaml
kubectl get pods -l job-name=job-demo
```

```
job-demo-6z9lx   0/1     Completed   0          45s
job-demo-8k2w4   0/1     Completed   0          45s
job-demo-t9svg   0/1     Completed   0          36s
```

Three pods, first two ran in parallel (same age), third started once a slot freed up.

---

## Exercise: backoffLimit in Action

Create `job-fail.yaml`:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: job-fail
spec:
  backoffLimit: 2
  template:
    spec:
      containers:
        - name: worker
          image: busybox
          command: ["sh", "-c", "exit 1"]
      restartPolicy: Never
```

```bash
kubectl apply -f job-fail.yaml
kubectl get pods -l job-name=job-fail
```

```
job-fail-m6t4t   0/1     Error    0          21s
job-fail-n8skf   0/1     Error    0          54s
job-fail-t9ct9   0/1     Error    0          42s
```

`backoffLimit: 2` allows 2 retries — so 3 pods total (initial attempt + 2 retries). After the third failure, the Job stops.

```bash
kubectl get jobs
```

```
NAME       STATUS     COMPLETIONS   DURATION   AGE
job-demo   Complete   3/3           19s        3m8s
job-fail   Failed     0/1           78s        78s
```

```bash
kubectl describe job job-fail
```

```
Events:
  Type     Reason                Age   From            Message
  ----     ------                ----  ----            -------
  Normal   SuccessfulCreate      99s   job-controller  Created pod: job-fail-n8skf
  Normal   SuccessfulCreate      87s   job-controller  Created pod: job-fail-t9ct9
  Normal   SuccessfulCreate      66s   job-controller  Created pod: job-fail-m6t4t
  Warning  BackoffLimitExceeded  62s   job-controller  Job has reached the specified backoff limit
```

---

## CronJobs

CronJobs fire a Job on a cron schedule. The schedule uses standard cron syntax: `minute hour day-of-month month day-of-week`.

Create `cronjob-demo.yaml`:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: cronjob-demo
spec:
  schedule: "*/2 * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: worker
              image: busybox
              command: ["sh", "-c", "date; echo Hello from CronJob"]
          restartPolicy: OnFailure
```

`*/2 * * * *` = every 2 minutes.

```bash
kubectl apply -f cronjob-demo.yaml
kubectl get cronjob
```

```
NAME           SCHEDULE      TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
cronjob-demo   */2 * * * *   <none>     False     0        53s             2m37s
```

```bash
kubectl get jobs
```

```
NAME                    STATUS     COMPLETIONS   DURATION   AGE
cronjob-demo-29835820   Complete   1/1           3s         77s
```

Each firing creates a named Job (`<cronjob-name>-<timestamp>`). By default, Kubernetes keeps the last **3 successful** and **1 failed** Job in history — older ones are cleaned up automatically.

### Useful CronJob fields

| Field | Default | Meaning |
|-------|---------|---------|
| `successfulJobsHistoryLimit` | 3 | How many completed Jobs to keep |
| `failedJobsHistoryLimit` | 1 | How many failed Jobs to keep |
| `concurrencyPolicy` | `Allow` | What to do if previous Job is still running when next fires: `Allow` (run both), `Forbid` (skip), `Replace` (cancel old, start new) |
| `suspend` | `false` | Set to `true` to pause the CronJob without deleting it |

---

## Cleanup

```bash
kubectl delete job job-demo job-fail
kubectl delete cronjob cronjob-demo
```
