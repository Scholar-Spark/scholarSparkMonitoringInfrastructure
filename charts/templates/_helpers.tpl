{{- define "shared-infra.labels" -}}
app.kubernetes.io/name: {{ include "shared-infra.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "shared-infra.name" -}}
{{ .Chart.Name }}
{{- end }}
