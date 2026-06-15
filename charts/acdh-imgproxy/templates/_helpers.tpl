{{- define "acdh-imgproxy.labels" -}}
app.kubernetes.io/managed-by: {{ .Release.Service | quote }}
app.kubernetes.io/instance: {{ .Release.Name | quote }}
app.kubernetes.io/part-of: imgproxy
helm.sh/chart: {{ printf "%s-%s" .Chart.Name (.Chart.Version | replace "+" "_") | quote }}
{{- end }}

{{- define "acdh-imgproxy.cacheName" -}}
{{- default (printf "%s-cache" .Release.Name) .Values.cache.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "acdh-imgproxy.cacheSelectorLabels" -}}
app.kubernetes.io/name: imgproxy-cache
{{- end }}

{{- define "acdh-imgproxy.originServiceName" -}}
{{- default (printf "%s-imgproxy" .Release.Name) .Values.origin.service.name | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "acdh-imgproxy.ingressName" -}}
{{- printf "%s-imgproxy" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end }}

