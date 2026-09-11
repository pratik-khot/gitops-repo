{{- define "argocd-application-inventory.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "argocd-application-inventory.fullname" -}}
{{- printf "%s-%s" .Values.clusterConfig.environment (include "argocd-application-inventory.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "argocd-application-inventory.applicationName" -}}
{{- printf "%s-%s" .Values.clusterConfig.environment .appName | trunc 63 | trimSuffix "-" -}}
{{- end -}}
