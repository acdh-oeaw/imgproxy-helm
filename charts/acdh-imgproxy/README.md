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

## Cache refresh

The cache serves a rendered image for 30 days (`cache.config.validSuccess`), also after its source
changed. Client cache headers, such as those sent by "Disable cache" in browser devtools, don't
bypass the cache, because anyone could send them to force renders on the origin. The cache key also
ignores query strings, which imgproxy ignores as well.

To replace a cached response, send its url with a refresh token in the `X-Cache-Refresh` header.
The cache then fetches the response from imgproxy and stores it. WebP and other formats are cached
separately, so refresh both:

```bash
curl -sI -H "X-Cache-Refresh: $TOKEN" -H "Accept: image/webp" "$URL" | grep -i x-cache-status  # BYPASS
curl -sI -H "X-Cache-Refresh: $TOKEN" "$URL" | grep -i x-cache-status                         # BYPASS
```

Without a token, which is the default, nothing can bypass the cache. To set one, create a Secret
and reference it, or set `cache.refresh.token` to let the chart create the Secret. Tokens need 32 to
128 characters from `A-Z a-z 0-9 _ -`:

```bash
kubectl -n imgproxy create secret generic imgproxy-cache-refresh \
  --from-literal=token="$(openssl rand -hex 32)"
```

```yaml
cache:
  refresh:
    existingSecret: imgproxy-cache-refresh
    secretKey: token
```

An init container writes the token into the Nginx configuration when a cache pod starts, so the
token stays out of the ConfigMap. After changing an existing Secret, restart the cache pods:

```bash
kubectl -n imgproxy rollout restart deployment/imgproxy-cache  # statefulset/imgproxy-cache with cache.storage.persistent
```

With `cache.refresh.token`, the pods restart on their own when the token changes.

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
