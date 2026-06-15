# ACDH imgproxy Helm chart

This repository publishes the `acdh-imgproxy` Helm chart used for the shared ACDH imgproxy service.
It wraps the official [`imgproxy/imgproxy`](https://github.com/imgproxy/imgproxy-helm) chart and
adds an unprivileged Nginx transformation cache in front of imgproxy.

## Install the repository

```bash
helm repo add acdh-imgproxy https://acdh-oeaw.github.io/imgproxy-helm
helm repo update
```

See [the chart documentation](charts/acdh-imgproxy/README.md) for migration, configuration, and
upgrade instructions.

## Development

```bash
helm dependency build charts/acdh-imgproxy
helm lint charts/acdh-imgproxy
helm template imgproxy charts/acdh-imgproxy --namespace imgproxy
```

## Releases

Merging a chart-version change to `main` creates a GitHub Release and updates the Helm index on the
`gh-pages` branch. Increment `version` in `charts/acdh-imgproxy/Chart.yaml` for every chart release.

