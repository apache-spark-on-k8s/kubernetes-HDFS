{{/* vim: set filetype=mustache: */}}
{{/*
Create a short app name.
*/}}
{{- define "hdfs-k8s.name" -}}
{{- printf "hdfs" -}}
{{- end -}}

{{/*
Create a fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "hdfs-k8s.fullname" -}}
{{- $name := "hdfs" -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the subchart label.
*/}}
{{- define "hdfs-k8s.subchart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "hdfs-k8s.config.fullname" -}}
{{- template "hdfs-k8s.fullname" . -}}-config
{{- end -}}

{{- define "hdfs-k8s.journalnode.fullname" -}}
{{- template "hdfs-k8s.fullname" . -}}-journalnode
{{- end -}}

{{- define "hdfs-k8s.namenode.fullname" -}}
{{- template "hdfs-k8s.fullname" . -}}-namenode
{{- end -}}

{{- define "hdfs-k8s.datanode.fullname" -}}
{{- template "hdfs-k8s.fullname" . -}}-datanode
{{- end -}}

{{/*
Create the kerberos principal suffix for core HDFS services
*/}}
{{- define "hdfs-principal" -}}
{{- printf "hdfs/_HOST@%s" .Values.global.kerberosRealm -}}
{{- end -}}

{{/*
Create the kerberos principal for HTTP services
*/}}
{{- define "http-principal" -}}
{{- printf "HTTP/_HOST@%s" .Values.global.kerberosRealm -}}
{{- end -}}

{{/*
Create the zookeeper quorum server list.  The below uses two loops to make
sure the last item does not have comma. It uses index 0 for the last item
since that is the only special index that helm template gives us.
*/}}
{{- define "zookeeper-quorum" -}}
{{- if .Values.global.zookeeperQuorumOverride -}}
{{- .Values.global.zookeeperQuorumOverride -}}
{{- else -}}
{{- $service := printf "%s-zookeeper" .Release.Name -}}
{{- $replicas := .Values.global.zookeeperServers | int -}}
{{- range $i, $e := until $replicas -}}
  {{- if ne $i 0 -}}
    {{- printf "%s-%d.%s-headless:2181," $service $i $service -}}
  {{- end -}}
{{- end -}}
{{- range $i, $e := until $replicas -}}
  {{- if eq $i 0 -}}
    {{- printf "%s-%d.%s-headless:2181" $service $i $service -}}
  {{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create the journalnode quorum server list.  The below uses two loops to make
sure the last item does not have the delimiter. It uses index 0 for the last
item since that is the only special index that helm template gives us.
*/}}
{{- define "journalnode-quorum" -}}
{{- $service := include "hdfs-k8s.journalnode.fullname" . -}}
{{- $replicas := .Values.global.journalnodeQuorumSize | int -}}
{{- range $i, $e := until $replicas -}}
  {{- if ne $i 0 -}}
    {{- printf "%s-%d.%s:8485;" $service $i $service -}}
  {{- end -}}
{{- end -}}
{{- range $i, $e := until $replicas -}}
  {{- if eq $i 0 -}}
    {{- printf "%s-%d.%s:8485" $service $i $service -}}
  {{- end -}}
{{- end -}}
{{- end -}}

{{/*
Construct the name of the namenode pod 0.
*/}}
{{- define "namenode-pod-0" -}}
{{- template "hdfs-k8s.namenode.fullname" . -}}-0
{{- end -}}

{{/*
Construct the name of the namenode pod 0.
*/}}
{{- define "namenode-svc-0" -}}
{{- template "namenode-pod-0" . -}}.{{- template "hdfs-k8s.namenode.fullname" . -}}
{{- end -}}

{{/*
Construct the name of the namenode pod 1.
*/}}
{{- define "namenode-pod-1" -}}
{{- template "hdfs-k8s.namenode.fullname" . -}}-1
{{- end -}}

{{/*
Construct the name of the namenode pod 1.
*/}}
{{- define "namenode-svc-1" -}}
{{- template "namenode-pod-1" . -}}.{{- template "hdfs-k8s.namenode.fullname" . -}}
{{- end -}}
