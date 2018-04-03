# Helper bash functions.

# Wait for Kubernetes resources to be up and ready.
_k8s_ready() {
  local jsonpath="$1"
  shift
  local evidence="$1"
  shift
  local attempts=20
  until kubectl get "$@" -o jsonpath="$jsonpath" 2>&1 | grep -q "$evidence"
  do
    ((attempts--)) || return 1
    kubectl get "$@" || true
    sleep 5
  done
}

k8s_any_node_ready() {
  local jsonpath='{range .items[*]}{@.metadata.name}:{range @.status.conditions[*]}{@.type}={@.status};{end}{end}'
  _k8s_ready "$jsonpath" "Ready=True" nodes "$@"
}

# Wait for any pod to be ready among a list of pods
k8s_any_pod_ready() {
  local jsonpath='{range .items[*]}{@.metadata.name}:{range @.status.conditions[*]}{@.type}={@.status};{end}{end}'
  _k8s_ready "$jsonpath" "Ready=True" pods "$@"
}

# Wait for a single particular pod to be ready.
k8s_single_pod_ready() {
  local jsonpath='jsonpath={.status.containerStatuses[0].ready}'
  _k8s_ready "$jsonpath" "true" pod "$@"
}
