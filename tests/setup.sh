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
set -o xtrace

_MY_SCRIPT="${BASH_SOURCE[0]}"
_MY_DIR=$(cd "$(dirname "$_MY_SCRIPT")" && pwd)
_KUBERNETES_VERSION=v1.7.5
_MINIKUBE_VERSION=v0.25.2

_UNAME_OUT=$(uname -s)
case "${_UNAME_OUT}" in
    Linux*)     _MY_OS=linux;;
    Darwin*)    _MY_OS=darwin;;
    *)          _MY_OS="UNKNOWN:${unameOut}"
esac
echo "My OS is ${_MY_OS}"

export MINIKUBE_WANTUPDATENOTIFICATION=false
export MINIKUBE_WANTREPORTERRORPROMPT=false
export CHANGE_MINIKUBE_NONE_USER=true

cd $_MY_DIR
rm -rf bin
mkdir -p bin
# Download kubectl, which is a requirement for using minikube.
curl -Lo bin/kubectl  \
  https://storage.googleapis.com/kubernetes-release/release/${_KUBERNETES_VERSION}/bin/${_MY_OS}/amd64/kubectl
chmod +x bin/kubectl
# Download minikube.
curl -Lo bin/minikube  \
  https://storage.googleapis.com/minikube/releases/${_MINIKUBE_VERSION}/minikube-${_MY_OS}-amd64
chmod +x bin/minikube

export PATH=${_MY_DIR}/bin:$PATH

_VM_DRIVER=""
if [[ "${USE_MINIKUBE_DRIVER_NONE:-}" == "true" ]]; then
# Run minikube with none driver.
# See https://blog.travis-ci.com/2017-10-26-running-kubernetes-on-travis-ci-with-minikube
  _VM_DRIVER="--vm-driver=none"
fi
_MINIKUBE="minikube"
if [[ "${USE_SUDO_MINIKUBE_START:-}" == "true" ]]; then
  _MINIKUBE="sudo ./bin/minikube"
fi
$_MINIKUBE start --kubernetes-version=${_KUBERNETES_VERSION}  \
  $_VM_DRIVER
# Fix the kubectl context, as it's often stale.
minikube update-context
# Wait for Kubernetes to be up and ready.
_JSONPATH='{range .items[*]}{@.metadata.name}:{range @.status.conditions[*]}{@.type}={@.status};{end}{end}'
until kubectl get nodes -o jsonpath="$_JSONPATH" 2>&1 | grep -q "Ready=True"
do
  sleep 1
done
