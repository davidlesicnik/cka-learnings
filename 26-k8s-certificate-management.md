# Certificate Management

Every kubeadm cluster runs entirely on certificates for internal trust — all cluster components authenticate to each other using certs signed by the cluster's own CA.

By default most certs have a 1-year expiry. Left unmanaged, this is a real production failure mode: when they expire, components can no longer authenticate, and the cluster starts failing in ways that look like networking or auth issues rather than cert expiry.

One important detail: kubeadm renews all certs automatically whenever the Kubernetes version is upgraded. If you're upgrading yearly, manual renewal is optional.

---

## Checking Expiry

```bash
sudo kubeadm certs check-expiration
```

Shows expiry for every cert in the cluster. CA certs last 10 years; everything else defaults to 1 year from cluster creation.

---

## Renewing Certs

```bash
sudo kubeadm certs renew all
```

```
[renew] Reading configuration from the "kubeadm-config" ConfigMap in namespace "kube-system"...
[renew] Use 'kubeadm init phase upload-config kubeadm --config your-config-file' to re-upload it.

certificate embedded in the kubeconfig file for the admin to use and for kubeadm itself renewed
certificate for serving the Kubernetes API renewed
certificate the apiserver uses to access etcd renewed
certificate for the API server to connect to kubelet renewed
certificate embedded in the kubeconfig file for the controller manager to use renewed
certificate for liveness probes to healthcheck etcd renewed
certificate for etcd nodes to communicate with each other renewed
certificate for serving etcd renewed
certificate for the front proxy client renewed
certificate embedded in the kubeconfig file for the scheduler manager to use renewed
certificate embedded in the kubeconfig file for the super-admin renewed

Done renewing certificates. You must restart the kube-apiserver, kube-controller-manager, kube-scheduler and etcd, so that they can use the new certificates.
```

**Important:** `check-expiration` will show the new expiry immediately after renewal, but the running components still hold the old certs in memory. They must be restarted before the new certs take effect.

---

## Restarting Components After Renewal

Static pod components (apiserver, controller-manager, scheduler, etcd) are restarted by briefly removing their manifest from `/etc/kubernetes/manifests/` — kubelet detects the removal and stops the container, then detects the file returning and starts a fresh one.

```bash
sudo mv /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/
sleep 5
sudo mv /tmp/kube-apiserver.yaml /etc/kubernetes/manifests/
```

Repeat for each component listed at the end of the renewal output:
- `kube-apiserver`
- `kube-controller-manager`
- `kube-scheduler`
- `etcd`
