{{/*
Chart name, overridable.
*/}}
{{- define "revealroll.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Fully-qualified release name, capped at 63 chars (the label-value limit).
*/}}
{{- define "revealroll.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Full label set — for metadata only.
*/}}
{{- define "revealroll.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "revealroll.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Selector labels.

⚠ A Deployment's .spec.selector is IMMUTABLE. Anything included here is frozen for the
life of the Deployment — so this deliberately excludes chart version and app version,
which change on every release. Putting them here would make every chart bump fail with
"field is immutable" and the only fix would be deleting the Deployment (an outage).
*/}}
{{- define "revealroll.selectorLabels" -}}
app.kubernetes.io/name: {{ include "revealroll.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
