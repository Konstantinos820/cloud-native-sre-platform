{{/*
Chart name + version, used as a label value.
*/}}
{{- define "sre-platform-app.chart" -}}
{{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{/*
Common labels applied to every resource in this chart.
*/}}
{{- define "sre-platform-app.commonLabels" -}}
app.kubernetes.io/part-of: sre-platform
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ include "sre-platform-app.chart" . }}
{{- end -}}

{{/*
Labels + selector labels for the FastAPI component.
*/}}
{{- define "sre-platform-app.appSelectorLabels" -}}
app.kubernetes.io/name: {{ .Values.app.name }}
app.kubernetes.io/component: api
{{- end -}}

{{- define "sre-platform-app.appLabels" -}}
{{ include "sre-platform-app.appSelectorLabels" . }}
{{ include "sre-platform-app.commonLabels" . }}
{{- end -}}

{{/*
Labels + selector labels for the PostgreSQL component.
*/}}
{{- define "sre-platform-app.postgresSelectorLabels" -}}
app.kubernetes.io/name: postgres
app.kubernetes.io/component: database
{{- end -}}

{{- define "sre-platform-app.postgresLabels" -}}
{{ include "sre-platform-app.postgresSelectorLabels" . }}
{{ include "sre-platform-app.commonLabels" . }}
{{- end -}}
