# `acdh-imgproxy`

This is a thin wrapper around the official
[`imgproxy/imgproxy`](https://github.com/imgproxy/imgproxy-helm) chart. The upstream chart remains a
versioned dependency in `Chart.yaml`; this chart adds an Nginx cache and replaces the upstream
Ingress so public traffic reaches Nginx first.

## Upstream upgrades

Upstream changes remain available without copying or merging upstream templates:

1. Change the `imgproxy` dependency version in `Chart.yaml`.
2. Run `helm dependency update deploy/imgproxy`.
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

## One-time migration of the existing release

The existing release stores upstream values at the root. The wrapper dependency expects those
values under `imgproxy:`. Some values contain S3 credentials and imgproxy signing keys, so generate
the migration file outside the repository with restrictive permissions:

```bash
umask 077

helm get values imgproxy --namespace imgproxy --output json |
  jq '{
    global: (.global // {}),
    imgproxy: (
      del(.global)
      | .resources.ingress.enabled = false
    )
  }' > /tmp/imgproxy-wrapper-values.json
```

Confirm the file is not empty and is readable only by the current user:

```bash
test -s /tmp/imgproxy-wrapper-values.json
stat --format='%a %n' /tmp/imgproxy-wrapper-values.json
```

Render the exact migration:

```bash
helm template imgproxy charts/acdh-imgproxy \
  --namespace imgproxy \
  --values /tmp/imgproxy-wrapper-values.json \
  > /tmp/imgproxy-wrapper-rendered.yaml
```

Dry-run against the cluster. `--take-ownership` allows the existing manually-created cache
Deployment and Service to become part of release `imgproxy`:

```bash
helm upgrade imgproxy charts/acdh-imgproxy \
  --namespace imgproxy \
  --values /tmp/imgproxy-wrapper-values.json \
  --take-ownership \
  --dry-run=server \
  --debug
```

Perform the migration:

```bash
helm upgrade imgproxy charts/acdh-imgproxy \
  --namespace imgproxy \
  --values /tmp/imgproxy-wrapper-values.json \
  --take-ownership \
  --atomic \
  --timeout 10m
```

Verify ownership and rollout:

```bash
helm status imgproxy --namespace imgproxy
kubectl -n imgproxy rollout status deployment/imgproxy-imgproxy
kubectl -n imgproxy rollout status deployment/imgproxy-cache
kubectl -n imgproxy get deployment,service,ingress,configmap
```

After the Helm-managed cache pods use `imgproxy-cache-config`, remove the obsolete Kustomize
ConfigMaps from the initial rollout:

```bash
kubectl -n imgproxy get deployment imgproxy-cache \
  -o jsonpath='{.spec.template.spec.volumes[0].configMap.name}{"\n"}'

kubectl -n imgproxy delete configmap \
  imgproxy-cache-config-564gdfg7k5 \
  imgproxy-cache-config-64k878mdm7 \
  imgproxy-cache-config-bh5k8hmb4g
```

After verification, remove the temporary files containing secret values:

```bash
shred --remove /tmp/imgproxy-wrapper-values.json
rm -f /tmp/imgproxy-wrapper-rendered.yaml
```

## Future upgrades

Helm stores the migrated nested values in the release. Preserve them on later upgrades:

```bash
helm upgrade imgproxy charts/acdh-imgproxy \
  --namespace imgproxy \
  --reuse-values \
  --atomic \
  --timeout 10m
```

When upgrading through Rancher, verify that the current custom values, especially `imgproxy.env`,
are retained. A stronger future improvement is moving credentials and signing keys to an externally
managed Kubernetes Secret and referencing it through `imgproxy.resources.addSecrets`.

## Rollback

Helm can return to the previous release revision:

```bash
helm history imgproxy --namespace imgproxy
helm rollback imgproxy <revision> --namespace imgproxy --wait --timeout 10m
```
