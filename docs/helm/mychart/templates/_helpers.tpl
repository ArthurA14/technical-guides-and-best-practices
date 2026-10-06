{{- define "projectname.name" -}}
# {{/* .Chart.Name */}}
{{- default .Chart.Name .Values.metadata.nameOverride -}}
{{- end }}

{{- define "projectname.fullname" -}}
{{/* printf "%s-%s" .Chart.Name .Release.Name */}}
{{- if .Values.metadata.fullnameOverride -}}
{{- .Values.metadata.fullnameOverride -}}
{{- else -}}
{{- printf "%s-%s" (include "projectname.name" .) .Release.Name -}}
{{- end -}}
{{- end }}

{{- define "projectname.namespace" -}}
{{- default (include "projectname.name" .) .Values.metadata.namespaceOverride -}}
{{- end }}

{{- define "projectname.component" -}}
{{- default "frontend" .Values.metadata.component | quote -}}
{{- end }}
