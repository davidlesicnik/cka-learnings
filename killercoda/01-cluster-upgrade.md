# Killercoda: Upgrading Kubernetes

Source: https://killercoda.com/chadmcrowell/course/cka

Scenario: **Upgrading Kubernetes** + **Upgrade Kubelet**

---

## Run Notes

### Run 1 — 6m

Patch version upgrade only (not minor). All commands on the docs. Wasted ~1 min waiting for `kubeadm upgrade apply` to finish before running `apt upgrade kubelet kubectl` — those can run in parallel once kubeadm is done.
