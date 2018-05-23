{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "hdfs-journalnode-k8s.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "hdfs-journalnode-k8s.fullname" -}}
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
Create chart name and version as used by the chart label.
*/}}
{{- define "hdfs-journalnode-k8s.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create the journalnode quorum server list.  The below uses two loops to make sure the
last item does not have comma. It uses index 0 for the last item since that is
the only special index that helm template gives us.
*/}}
{{- define "journalnode-quorum" -}}
{{- $release := .Release.Name -}}
{{- $replicas := 3 | int -}}
{{- range $i, $e := until $replicas -}}
  {{- if ne $i 0 -}}
    {{- printf "%s-journalnode-%d.%s-journalnode:8485," $release $i $release -}}
  {{- end -}}
{{- end -}}
{{- range $i, $e := until $replicas -}}
  {{- if eq $i 0 -}}
    {{- printf "%s-journalnode-%d.%s-journalnode:8485" $release $i $release -}}
  {{- end -}}
{{- end -}}
{{- end -}}
