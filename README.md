# CKA Learnings

Personal notes and walkthroughs as I progress through CKA (Certified Kubernetes Administrator) preparation.

The base content of each document is written by me as I work through the topics hands-on. Formatting, structure, and additional explanations were added with help from Claude Code.

## Documents

- [Cluster Setup](01-cluster-setup.md) — Creating a 3-node cluster with kubeadm on multipass VMs
- [Cluster Upgrade](02-cluster-upgrade.md) — Upgrading Kubernetes one minor version at a time
- [Flannel to Calico](03-flannel-to-calico.md) — Replacing the CNI plugin for NetworkPolicy support
- [etcd Backup & Restore](04-etcd-backup-restore.md) — Backing up and restoring the cluster database
- [RBAC: Roles & RoleBindings](05-rbac-role-rolebindings.md) — Namespace-scoped permissions with ServiceAccounts
- [RBAC: ClusterRoles](06-rbac-clusterrole.md) — Cluster-wide permissions and scoping ClusterRoles with RoleBindings
- [Network Policies](07-network-policies.md) — Restricting pod-to-pod traffic with deny-all and allow rules
- [Troubleshooting](99-troubleshooting.md) — Real issues encountered along the way and how they were fixed
