{{/*
Usage: {{ include "homefinance.labels" (dict "root" . "component" "backend") }}
*/}}
{{- define "homefinance.selectorLabels" -}}
app.kubernetes.io/name: homefinance
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{- define "homefinance.labels" -}}
{{ include "homefinance.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
app.kubernetes.io/part-of: homefinance
helm.sh/chart: {{ printf "%s-%s" .root.Chart.Name .root.Chart.Version }}
{{- end }}

{{/* Full image reference; tag is mandatory so a deploy can never float on "latest" */}}
{{- define "homefinance.image" -}}
{{- $tag := required (printf "%s.image.tag is required" .name) .image.tag -}}
{{- if .registry -}}
{{ printf "%s/%s:%s" .registry .image.repository $tag }}
{{- else -}}
{{ printf "%s:%s" .image.repository $tag }}
{{- end -}}
{{- end }}
