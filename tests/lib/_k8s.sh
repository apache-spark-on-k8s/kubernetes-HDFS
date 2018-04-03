# Helper bash functions.

# Wait for Kubernetes resources to be up and ready.
function _wait_for_ready () {
  local count="$1"
  shift
  local evidence="$1"
  shift
  local attempts=40
  echo "Running: $@"
  while [[ "$count" != $("$@" 2>&1 | tail -n +2 | grep -c "$evidence") ]];
  do
    if [[ "$attempts" = 1 ]]; then
      "$@" || true
    fi
    ((attempts--)) || return 1
    sleep 5
  done
  "$@" || true
}

# Wait for all expected number of nodes to be ready
function k8s_all_nodes_ready () {
  local count="$1"
  shift
  _wait_for_ready "$count" Ready kubectl get nodes
}

function k8s_single_node_ready () {
  k8s_all_nodes_ready 1
}

# Wait for all expected number of pods to be ready. This works only for
# pods with one container. We check "1/1" in the `kubectl get pods` output.
function k8s_all_pods_ready () {
  local count="$1"
  shift
  _wait_for_ready "$count" "1/1" kubectl get pods "$@"
}

function k8s_single_pod_ready () {
  k8s_all_pods_ready 1 "$@"
}
