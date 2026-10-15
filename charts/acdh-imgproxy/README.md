# `acdh-imgproxy`

This is a thin wrapper around the official
[`imgproxy/imgproxy`](https://github.com/imgproxy/imgproxy-helm) chart. The upstream chart remains a
versioned dependency in `Chart.yaml`; this chart adds an Nginx cache and replaces the upstream
Ingress so public traffic reaches Nginx first.

## Upstream upgrades

Upstream changes remain available without copying or merging upstream templates:

1. Change the `imgproxy` dependency version in `Chart.yaml`.
2. Run `helm dependency update charts/acdh-imgproxy`.
3. Review `Chart.lock` and the rendered manifests.
4. Test against the test hostname before upgrading production.

The wrapper templates only own the cache and public Ingress. Origin Deployment, Service, Secret,
ServiceMonitor, and PodDisruptionBudget continue to come from the upstream dependency.

## Local validation

Fetch the pinned upstream dependency:

```bash
helm dependency update charts/acdh-imgproxy
```

Render and lint with non-secret defaults:

```bash
helm lint charts/acdh-imgproxy
helm template imgproxy charts/acdh-imgproxy --namespace imgproxy
```

## Upgrade the deployed release

Update the repository metadata and inspect the available chart versions:

```bash
helm repo update
helm search repo acdh-imgproxy/acdh-imgproxy --versions
```

Run a server-side dry run with the target version:

```bash
helm upgrade imgproxy acdh-imgproxy/acdh-imgproxy \
  --version <version> \
  --namespace imgproxy \
  --reset-then-reuse-values \
  --dry-run=server \
  --hide-secret \
  --debug
```

Deploy the version after reviewing the dry-run output:

```bash
helm upgrade imgproxy acdh-imgproxy/acdh-imgproxy \
  --version <version> \
  --namespace imgproxy \
  --reset-then-reuse-values \
  --atomic \
  --timeout 10m
```

`--reset-then-reuse-values` starts with the new chart defaults and reapplies the values stored in
the current release. This preserves deployment-specific settings while allowing new chart defaults
to take effect.

Verify the release, the origin and the cache:

```bash
helm status imgproxy --namespace imgproxy
kubectl -n imgproxy rollout status deployment/imgproxy-imgproxy
kubectl -n imgproxy rollout status deployment/imgproxy-cache  # statefulset/imgproxy-cache with cache.storage.persistent
kubectl -n imgproxy get pods,service,ingress
```

## Persistent cache

By default the cache lives on an `emptyDir` and starts empty after every rollout. With
`cache.storage.persistent=true` the cache runs as a StatefulSet with one `ReadWriteOnce`
PersistentVolumeClaim per replica, sized by `cache.storage.cacheSizeLimit`, so rendered images
survive restarts and upgrades.

- Switching replaces the cache Deployment with a StatefulSet in one upgrade. Helm removes the
  Deployment without waiting for the StatefulSet, so the cache is unavailable until the first new
  pod has its volume and is ready. The new volumes start empty once.
- A StatefulSet replaces its pods one at a time; with 2 replicas, one keeps serving. After a
  restart, Nginx indexes the existing files in the background, and entries it hasn't indexed yet are
  fetched again.
- The volumes are deleted with the StatefulSet (on `helm uninstall` or when switching back) and
  with a replica when scaling down.
- A StatefulSet's volume templates can't be updated, so an upgrade that changes
  `cache.storage.cacheSizeLimit` or `cache.storage.storageClassName` fails. To apply one, delete
  the StatefulSet but keep its pods, then upgrade:

  ```bash
  kubectl -n imgproxy delete statefulset imgproxy-cache --cascade=orphan
  ```

  Existing volumes keep their size and class. Delete each pod and its claim
  (`cache-imgproxy-cache-<n>`) to recreate them, or expand the claims if the StorageClass allows it.

Run the server-side dry run first to check that the StorageClass exists.

When upgrading through Rancher, verify that the current custom values, especially `imgproxy.env`,
are retained. Credentials and signing keys should eventually move to an externally managed
Kubernetes Secret referenced through `imgproxy.resources.addSecrets`.
