{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "shared-infra.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "shared-infra.labels" -}}
helm.sh/chart: {{ include "shared-infra.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}