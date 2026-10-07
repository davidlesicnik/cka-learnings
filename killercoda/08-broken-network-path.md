# Killercoda: Troubleshoot a Broken Network Path

Source: https://killercoda.com/chadmcrowell/course/cka

Scenario: **Troubleshoot a Broken Network Path**

Note: different angle from ex-21 (app-unreachable) — focuses on port misconfiguration between service and pod.

---

## Run Notes

### Run 1 — 2m

Checked pod logs (nginx healthy), checked endpointslice (populated). Compared port on Deployment vs Service — service `targetPort` was `8081`, nginx listened on `80`. Fixed via `kubectl edit svc`.
