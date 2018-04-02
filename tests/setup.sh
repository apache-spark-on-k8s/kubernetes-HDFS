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
_KUBERNETES_VERSION=v1.7.5
_MINIKUBE_VERSION=v0.25.2
_HELM_VERSION=v2.8.1

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

source lib/_k8s.sh

rm -rf tmp
mkdir -p bin tmp
if [[ ! -x bin/kubectl ]]
then
  # Download kubectl, which is a requirement for using minikube.
  curl -Lo bin/kubectl  \
    https://storage.googleapis.com/kubernetes-release/release/${_KUBERNETES_VERSION}/bin/${_MY_OS}/amd64/kubectl
  chmod +x bin/kubectl
fi
if [[ ! -x bin/minikube ]]
then
  # Download minikube.
  curl -Lo bin/minikube  \
    https://storage.googleapis.com/minikube/releases/${_MINIKUBE_VERSION}/minikube-${_MY_OS}-amd64
  chmod +x bin/minikube
fi
if [[ ! -x bin/helm ]]
then
  # Download helm
  curl -Lo tmp/helm.tar.gz  \
    https://storage.googleapis.com/kubernetes-helm/helm-${_HELM_VERSION}-${_MY_OS}-amd64.tar.gz
  (cd tmp; tar xfz helm.tar.gz; mv ${_MY_OS}-amd64/helm ${_MY_DIR}/bin)
fi

export PATH=${_MY_DIR}/bin:$PATH

_VM_DRIVER=""
if [[ "${USE_MINIKUBE_DRIVER_NONE:-}" = "true" ]]; then
# Run minikube with none driver.
# See https://blog.travis-ci.com/2017-10-26-running-kubernetes-on-travis-ci-with-minikube
  _VM_DRIVER="--vm-driver=none"
fi
_MINIKUBE="minikube"
if [[ "${USE_SUDO_MINIKUBE_START:-}" = "true" ]]; then
  _MINIKUBE="sudo ./bin/minikube"
fi
$_MINIKUBE start --kubernetes-version=${_KUBERNETES_VERSION}  \
  $_VM_DRIVER
# Fix the kubectl context, as it's often stale.
minikube update-context

# Wait for Kubernetes to be up and ready.
k8s_check_ready nodes

helm init
k8s_check_ready pod -n kube-system -l name=tiller
