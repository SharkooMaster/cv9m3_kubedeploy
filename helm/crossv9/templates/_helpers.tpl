{{- define "crossv9.name" -}}
{{- default .Chart.Name .Values.global.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "crossv9.fullname" -}}
{{- if .Values.global.fullnameOverride -}}
{{- .Values.global.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "crossv9.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "crossv9.labels" -}}
app.kubernetes.io/name: {{ include "crossv9.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
{{- end -}}

{{/*
Shared env block for gateway-shaped pods (the request-handling
gateway Deployment and the singleton gateway-coordinator Deployment).
Keeps the two in sync — every env var the gateway needs at runtime
must live here so a single source of truth controls both.

Argument: a dict with keys
  - root: . (the chart root)
  - coordinator: bool, true only on the singleton coordinator pod.
    Forces REBALANCE_COORDINATOR_ENABLED=true on the coordinator and
    false on every request-path pod when the split mode is on
    (gatewayCoordinator.enabled=true).
*/}}
{{- define "crossv9.gatewayEnv" -}}
{{- $root := .root -}}
{{- $isCoordinator := .coordinator -}}
{{- $splitEnabled := and $root.Values.gatewayCoordinator $root.Values.gatewayCoordinator.enabled -}}
- name: ASPNETCORE_ENVIRONMENT
  value: "Development"
- name: MY_POD_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.name
- name: MY_NODE_NAME
  valueFrom:
    fieldRef:
      fieldPath: spec.nodeName
- name: OTEL_EXPORTER_OTLP_ENDPOINT
  value: {{ $root.Values.observability.otel.endpoint | quote }}
- name: DOTNET_PerfMapEnabled
  value: "1"
- name: COMPlus_PerfMapEnabled
  value: "1"
- name: CROSS_MODE
  value: {{ $root.Values.mode.crossMode | quote }}
- name: AGENTS_LOADBALANCER
  value: {{ printf "%s-agent-headless" (include "crossv9.fullname" $root) | quote }}
{{- $etcdEndpoint := "" }}
{{- if $root.Values.etcd.enabled }}
  {{- $etcdEndpoint = printf "http://%s-etcd.%s.svc.cluster.local:2379" (include "crossv9.fullname" $root) $root.Release.Namespace }}
{{- else if $root.Values.externalEtcd.endpoint }}
  {{- $etcdEndpoint = $root.Values.externalEtcd.endpoint }}
{{- end }}
{{- if $etcdEndpoint }}
- name: ETCD_ENDPOINT
  value: {{ $etcdEndpoint | quote }}
{{- end }}
- name: REPLICATION_FACTOR
  value: {{ (default 3 $root.Values.agent.replicationFactor) | quote }}
- name: WRITE_QUORUM
  value: {{ (default 2 $root.Values.agent.writeQuorum) | quote }}
# REBALANCE_COORDINATOR_ENABLED is set by an explicit rule, not the
# user's values, when the split-deployment mode is on:
#   - On gateway-coordinator pods: always true (that's their purpose)
#   - On request-path gateway pods: always false (so multi-replica
#     scaling doesn't create competing coordinators that race on the
#     same drain → conflicting RetirementTracker state across pods)
# When the split mode is off (gatewayCoordinator.enabled=false), we
# fall back to the user-controlled gateway.rebalanceCoordinatorEnabled,
# defaulting to "true" for the single-pod legacy behaviour.
- name: REBALANCE_COORDINATOR_ENABLED
  {{- if $splitEnabled }}
  value: {{ ternary "true" "false" $isCoordinator | quote }}
  {{- else }}
  value: {{ (default "true" $root.Values.gateway.rebalanceCoordinatorEnabled) | quote }}
  {{- end }}
- name: CHUNK_SIZE
  value: {{ $root.Values.chunkSize | default 4096 | quote }}
- name: GATEWAY_SEARCH_TIMEOUT_SEC
  value: {{ $root.Values.gateway.searchTimeoutSec | quote }}
- name: GATEWAY_STORE_TIMEOUT_SEC
  value: {{ $root.Values.gateway.storeTimeoutSec | quote }}
- name: GATEWAY_STREAM_CONCURRENCY
  value: {{ $root.Values.gateway.streamConcurrency | quote }}
{{- end -}}
