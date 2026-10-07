{{- define "social-media-host.fullname" -}}
social-media-host
{{- end -}}

{{- define "social-media-host.labels" -}}
app.kubernetes.io/name: social-media-host
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
