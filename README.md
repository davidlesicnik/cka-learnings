# CKA Learnings

Personal notes and walkthroughs as I progress through CKA (Certified Kubernetes Administrator) preparation.

The base content of each document is written by me as I work through the topics hands-on. Formatting, structure, and additional explanations were added with help from Claude Code.

## Documents

- [Exam Shortcuts](00-exam-shortcuts.md) — `--dry-run=client -o yaml` quick reference for generating manifests
- [Cluster Setup](01-cluster-setup.md) — Creating a 3-node cluster with kubeadm on multipass VMs
- [Cluster Upgrade](02-cluster-upgrade.md) — Upgrading Kubernetes one minor version at a time
- [Flannel to Calico](03-flannel-to-calico.md) — Replacing the CNI plugin for NetworkPolicy support
- [etcd Backup & Restore](04-etcd-backup-restore.md) — Backing up and restoring the cluster database
- [RBAC: Roles & RoleBindings](05-rbac-role-rolebindings.md) — Namespace-scoped permissions with ServiceAccounts
- [RBAC: ClusterRoles](06-rbac-clusterrole.md) — Cluster-wide permissions and scoping ClusterRoles with RoleBindings
- [Network Policies](07-network-policies.md) — Restricting pod-to-pod traffic with deny-all and allow rules
- [Service Types](08-network-service-types.md) — ClusterIP, NodePort, LoadBalancer, and ExternalName
- [Ingress](09-ingress.md) — HTTP routing with Traefik as the ingress controller
- [Storage: PVs & PVCs](10-storage.md) — Persistent Volumes, Claims, and mounting into pods
- [Storage Classes](11-storage-classes.md) — Dynamic provisioning with local-path-provisioner
- [Deployments](12-deployments.md) — Rolling updates, rollbacks, and scaling strategies
- [DaemonSets](13-daemon-set.md) — Running one pod per node for infrastructure agents
- [StatefulSets](14-stateful-set.md) — Stable pod identity, ordered scaling, and per-pod storage
- [Resource Requests & Limits](15-resource-limits-requests.md) — CPU/memory guarantees, caps, QoS classes, and OOM kills
- [Affinities](16-affinities.md) — Node affinity, pod affinity/anti-affinity, and enforcement levels
- [Taints and Tolerations](17-taints-tolerations.md) — Repelling pods from nodes and bypassing taints with tolerations
- [ConfigMaps and Secrets](18-configmap-secret-md) — Injecting config and sensitive data via env vars and volume mounts
- [HPA](19-hpa.md) — Automatic replica scaling based on CPU/memory via metrics-server
- [Jobs and CronJobs](20-jobs-cronjobs.md) — Run-to-completion workloads and scheduled jobs
- [Helm and Kustomize](21-helm-kustomize.md) — Package management with Helm and environment overlays with Kustomize
- [Gateway API](22-gatewayapi.md) — Successor to Ingress with split ownership across GatewayClass, Gateway, and HTTPRoute
- [Troubleshooting Drills Part 1](23-troubleshooting-drills-1.md) — Bad image tag, service selector mismatch, broken kubelet, crashed kube-apiserver, NetworkPolicy label mismatch
- [Troubleshooting Drills Part 2](24-troubleshooting-drills-2.md) — CrashLoopBackOff exit code triage, pod Pending, PVC Pending, node NotReady, CoreDNS down
- [kubectl debug](25-kubectl-debug.md) — Ephemeral containers, node shell access, and copying crashing pods
- [Certificate Management](26-k8s-certificate-management.md) — Checking cert expiry, manual renewal, and restarting components after renewal
- [Init Containers](27-init-containers.md) — Sequential pre-start containers, status progression, and debugging init failures
- [Sidecar Containers](28-sidecar-containers.md) — Long-running companion containers via `restartPolicy: Always` in initContainers
- [Static Pods](29-static-pods.md) — Kubelet-managed pods, node hostname suffix tell, and why `kubectl edit` is silently ignored
- [LimitRange](30-limit-range.md) — Namespace-scoped default injection and min/max bounds enforcement for container resources
- [Troubleshooting](99-troubleshooting.md) — Real issues encountered along the way and how they were fixed
