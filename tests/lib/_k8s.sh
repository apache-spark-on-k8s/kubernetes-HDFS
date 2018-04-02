# Helper bash functions.

# Wait for Kubernetes resources to be up and ready.
k8s_check_ready() {
  local jsonpath='{range .items[*]}{@.metadata.name}:{range @.status.conditions[*]}{@.type}={@.status};{end}{end}'
  local attempts=1
  until kubectl get "$@" -o jsonpath="$jsonpath" 2>&1 | grep -q "Ready=True"
  do
    if (( attempts++ > 20 ))
    then
      return 1
    fi
    kubectl get "$@" || true
    sleep 5
  done
}
