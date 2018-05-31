#!/usr/bin/env bash

# Exit on error. Append "|| true" if you expect an error.
set -o errexit
# Exit on error inside any functions or subshells.
set -o errtrace
# Do not allow use of undefined vars. Use ${VAR:-} to use an undefined VAR
set -o nounset
# Catch an error in command pipes. e.g. mysqldump fails (but gzip succeeds)
# in `mysqldump |gzip`
set -o pipefail
if [[ "${DEBUG:-}" = "true" ]]; then
# Turn on traces, useful while debugging but commented out by default
  set -o xtrace
fi

_MY_SCRIPT="${BASH_SOURCE[0]}"
_TEST_DIR=$(cd "$(dirname "$_MY_SCRIPT")" && pwd)
export PATH=${_TEST_DIR}/bin:$PATH
source ${_TEST_DIR}/lib/_k8s.sh

_PROJECT_DIR=$(cd "$(dirname "$_TEST_DIR")" && pwd)
_CHART_DIR=${_PROJECT_DIR}/charts

function _run () {
  local attempts=2
  echo Running: "$@"
  until "$@"; do
    ((attempts--)) || return 1
    sleep 5
  done
}

function _helm_diff_and_install () {
  local gold=$1
  shift
  echo Running: helm install --dry-run --debug "$@"
  local tmpfile=$(mktemp ${_TEST_DIR}/tmp/helm-dry-run.XXXXXX)
  (helm install --dry-run --debug "$@" |  \
      grep -v -e "^RELEASED" -e "^\[debug\]") > $tmpfile
  if [[ "${BLESS_DIFF:-}" = "true" ]]; then
    echo Blessing $tmpfile
    cp -f $tmpfile $gold
  else
    echo Comparing $gold and $tmpfile
    if [[ "${CRASH_ON_DIFF:-false}" = "true" ]]; then
      diff $gold $tmpfile
    else
      diff $gold $tmpfile || true
    fi
  fi
  rm "$tmpfile"
  if [[ "${DRY_RUN_ONLY:-false}" = "true" ]]; then
    return
  fi
  echo Running: helm install "$@"
  helm install "$@"
}

kubectl cluster-info
cd $_CHART_DIR
rm -rf hdfs-k8s/charts hdfs-k8s/requirements.lock
_run helm repo add incubator  \
  https://kubernetes-charts-incubator.storage.googleapis.com/
_run helm dependency build hdfs-k8s

_DEFAULT_CASES="*"
: "${CASES:=$_DEFAULT_CASES}"
_CASES=$(ls ${_TEST_DIR}/cases/${CASES})
for _CASE in $_CASES; do
  echo Running test case: $_CASE
  source $_CASE
  run_test_case
  if [[ "${SKIP_CLEANUP:-false}" = "false" ]]; then
    echo Cleaning up test case: $_CASE
    cleanup_test_case
  fi
done
