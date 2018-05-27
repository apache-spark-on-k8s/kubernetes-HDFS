# Helper bash functions.

# Wait for Kubernetes resources to be up and ready.
function _wait_for_ready () {
  local count="$1"
  shift
  local evidence="$1"
  shift
  local attempts=60
  echo "Waiting till ready (count: $count): $@"
  while [[ "$count" != $("$@" 2>&1 | tail -n +2 | grep -c $evidence) ]];
  do
    if [[ "$attempts" = "1" ]]; then
      echo "Last run: $@"
      "$@" || true
      local command="$@"
      command="${command/get/describe}"
      $command || true
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
  _wait_for_ready "$count" "-v NotReady" kubectl get nodes
  _wait_for_ready "$count" Ready kubectl get nodes
}

function k8s_single_node_ready () {
  k8s_all_nodes_ready 1
}

# Wait for all expected number of pods to be ready. This works only for
# pods with up to 4 containers, as we check "1/1" to "4/4" in
# `kubectl get pods` output.
function k8s_all_pods_ready () {
  local count="$1"
  shift
  local evidence="-e 1/1 -e 2/2 -e 3/3 -e 4/4"
  _wait_for_ready "$count" "$evidence" kubectl get pods "$@"
}

function k8s_single_pod_ready () {
  k8s_all_pods_ready 1 "$@"
}
