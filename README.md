# CKA Learnings

Personal notes and walkthroughs as I progress through CKA (Certified Kubernetes Administrator) preparation.

The base content of each document is written by me as I work through the topics hands-on. Formatting, structure, and additional explanations were added with help from Claude Code.

## Exercises

Hands-on drills with reference solutions, tips, and run notes:

- [etcd Restore](exercises/01-etcd-restore.md) — Full backup-and-restore cycle with etcdutl
- [RBAC](exercises/02-rbac.md) — Role, ClusterRole, and ServiceAccount bindings
- [NetworkPolicy](exercises/03-networkpolicy.md) — Pick the least-permissive policy from four candidates
- [Static Pod and Scheduling](exercises/04-static-pod-and-scheduling.md) — Static pod + forced control-plane scheduling
- [PV, PVC, and Pod](exercises/05-pv-pvc-pod.md) — Create and bind a PersistentVolume, mount into a pod
- [Fix Broken Service + HTTPRoute](exercises/06-service-gateway.md) — Diagnose empty endpoints, expose via Gateway API
- [Helm](exercises/07-helm.md) — Add repo, install, upgrade, rollback, list across namespaces
- [Kustomize](exercises/08-kustomize.md) — Overlay with namespace, namePrefix, replicas, image tag, ConfigMap generator
- [Pods Unschedulable](exercises/09-pods-unschedulable.md) — No events on Pending pods → broken kube-scheduler static pod
- [DNS Resolution Broken](exercises/10-dns-resolving.md) — cluster.local fails, external resolves → CoreDNS Corefile typo
- [Init Container + Sidecar](exercises/11-init-sidecar.md) — seed init writes file, sidecar tails it, main container runs alongside
- [Deployment Rollout](exercises/12-deployment-rollout.md) — Update image, check history, rollback, scale
- [Node NotReady](exercises/13-node-troubleshooting.md) — All conditions Unknown → stopped kubelet on worker node
- [ClusterRole Scoped with RoleBinding](exercises/14-clusterrole-scoping.md) — ClusterRole + RoleBinding to restrict to one namespace
- [Job and CronJob](exercises/15-cronjob.md) — Job with retries, CronJob with history limits, manual trigger
- [Pod Failure Triage](exercises/16-pod-failures.md) — CrashLoopBackOff, ImagePullBackOff, OOMKilled, Pending diagnosis
- [ConfigMap and Secret](exercises/17-configmap-secret.md) — Create and inject as env vars and volume mount
- [StorageClass Dynamic Provisioning](exercises/18-storageclass-dynamic.md) — StorageClass YAML, PVC, pod with WaitForFirstConsumer
- [Ingress](exercises/19-ingress.md) — Path-based routing, ingressClassName, curl with Host header
- [HPA](exercises/20-hpa.md) — Autoscale deployment on CPU utilization
- [Pod Failure Triage](exercises/16-pod-failures.md) — CrashLoopBackOff, ImagePullBackOff, OOMKilled, Pending diagnosis
- [ConfigMap and Secret](exercises/17-configmap-secret.md) — Inject config via env vars and volume mounts
- [StorageClass and Dynamic Provisioning](exercises/18-storageclass-dynamic.md) — StorageClass, dynamic PVC, WaitForFirstConsumer
- [Ingress](exercises/19-ingress.md) — Path-based routing to two backends with ingressClassName
- [HPA](exercises/20-hpa.md) — CPU-based autoscaling with min/max bounds
- [Application Unreachable](exercises/21-app-unreachable.md) — Service selector mismatch + NetworkPolicy blocking, two faults in one

## Killercoda Scenarios

Scenarios from [Chad M. Crowell's CKA course](https://killercoda.com/chadmcrowell/course/cka) — done there, notes tracked here:

- [Cluster Upgrade](killercoda/01-cluster-upgrade.md) — Control plane + worker upgrade with kubeadm
- [Cordon and Drain](killercoda/02-cordon-drain.md) — Maintenance workflow, PodDisruptionBudgets
- [Certificate PKI](killercoda/03-certificate-pki.md) — PKI directory, cert expiry, renewal with kubeadm certs
- [Taints and Tolerations](killercoda/04-taints-tolerations.md) — Apply, remove taints; add tolerations to YAML
- [Node Affinity](killercoda/05-node-affinity.md) — Required vs preferred, nodeSelector scheduling
- [Troubleshoot Stuck PVC](killercoda/06-troubleshoot-stuck-pvc.md) — PVC stuck Pending diagnosis and fix
- [Priority Class](killercoda/07-priority-class.md) — PriorityClass scheduling and preemption
- [Broken Network Path](killercoda/08-broken-network-path.md) — Port misconfiguration between service and pod
- [Kubelet SSH](killercoda/09-kubelet-ssh.md) — SSH into worker node, check and restart kubelet
- [Kustomize](killercoda/10-kustomize.md) — Apply, common labels, configmap/secret, env overlay, patch image (5 scenarios)

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
- [PriorityClass](31-priority-class.md) — Pod scheduling order and preemption via priority values, including built-in system classes
- [Troubleshooting](99-troubleshooting.md) — Real issues encountered along the way and how they were fixed
