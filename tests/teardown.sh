#!/usr/bin/env bash
# Exit on error. Append "|| true" if you expect an error.
set -o errexit
# Exit on error inside any functions or subshells.
set -o errtrace
# Do not allow use of undefined vars. Use ${VAR:-} to use an undefined VAR
set -o nounset
# Catch the error in case mysqldump fails (but gzip succeeds) in `mysqldump |gzip`
set -o pipefail
# Turn on traces, useful while debugging but commented out by default
#set -o xtrace

_MY_SCRIPT="${BASH_SOURCE[0]}"
_MY_DIR=$(cd "$(dirname "$_MY_SCRIPT")" && pwd)

cd $_MY_DIR
export PATH=${_MY_DIR}/bin:$PATH

for chart in my-hdfs-datanode my-hdfs-namenode my-hdfs-journalnode my-zk; do
  helm delete --purge $chart || true
done

minikube status || true
minikube stop || true

rm -rf tmp
if [[ "${TEARDOWN_DELETE_MINIKUBE:-}" = "true" ]]; then
  minikube delete || true
fi
if [[ "${TEARDOWN_DELETE_BIN:-}" = "true" ]]; then
  rm -rf bin
fi
