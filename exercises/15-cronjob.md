# Exercise: Job and CronJob

## Task

1. Create a **Job** named `db-backup` in namespace `ops` using `busybox` that runs: `sh -c "echo backing up database && sleep 5 && echo done"`. It should retry up to 3 times on failure and run at most 1 pod at a time.

2. Create a **CronJob** named `cleanup` in namespace `ops` using `busybox` that runs `sh -c "echo cleaning up"` every 5 minutes. Keep only the last 2 successful and 1 failed job history.

3. Manually trigger a Job from the `cleanup` CronJob immediately.

4. Write the status of the `db-backup` Job (Complete/Failed) to `/opt/answers/q13.txt`.

---

## Reference Solution

```bash
kubectl create namespace ops

# 1. Job
kubectl create job db-backup -n ops --image=busybox \
  -- sh -c "echo backing up database && sleep 5 && echo done"

# Add retries + parallelism via patch or dry-run edit:
kubectl create job db-backup -n ops --image=busybox --dry-run=client -o yaml \
  -- sh -c "echo backing up database && sleep 5 && echo done" > job.yaml
# edit: add backoffLimit: 3 and completions: 1 under spec

kubectl apply -f job.yaml

# 2. CronJob
kubectl create cronjob cleanup -n ops \
  --image=busybox \
  --schedule="*/5 * * * *" \
  -- sh -c "echo cleaning up"

# Add history limits via dry-run edit:
kubectl create cronjob cleanup -n ops --image=busybox \
  --schedule="*/5 * * * *" --dry-run=client -o yaml \
  -- sh -c "echo cleaning up" > cronjob.yaml
# edit: add successfulJobsHistoryLimit: 2 and failedJobsHistoryLimit: 1 under spec

kubectl apply -f cronjob.yaml

# 3. Manual trigger
kubectl create job cleanup-manual -n ops --from=cronjob/cleanup

# 4. Write status
kubectl get job db-backup -n ops -o jsonpath='{.status.conditions[0].type}' > /opt/answers/q13.txt
```

---

## Tips

**`kubectl create job --from=cronjob/<name>` triggers immediately.** No need to edit the schedule. The triggered job name must be unique.

**`backoffLimit` is retries, not total attempts.** `backoffLimit: 3` = 3 retries = 4 total attempts max.

**`successfulJobsHistoryLimit` / `failedJobsHistoryLimit` are on the CronJob spec**, not the Job spec. Easy to put in the wrong place.

**Cron schedule syntax — common patterns:**
| Schedule | Meaning |
|---|---|
| `*/5 * * * *` | Every 5 minutes |
| `0 * * * *` | Every hour |
| `0 0 * * *` | Daily at midnight |
| `0 0 * * 0` | Weekly on Sunday |

**Job vs CronJob dry-run:** `kubectl create job` and `kubectl create cronjob` both support `--dry-run=client -o yaml`. Use this to get the base YAML then add `backoffLimit`, history limits, etc.

---

## Run Notes

### Run 1 — ~10 minutes

Most syntax found in the docs. Manual trigger was the sticking point — forgot you use `kubectl create job <name> --from=cronjob/<name>`. Found it via `kubectl create job --help`.
