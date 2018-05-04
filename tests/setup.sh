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
_MY_DIR=$(cd "$(dirname "$_MY_SCRIPT")" && pwd)
# Avoids 1.7.x because of https://github.com/kubernetes/minikube/issues/2240
# Also avoids 1.9.4 because of
# https://github.com/kubernetes/kubernetes/issues/61076#issuecomment-376660233
# TODO: Try 1.9.x > 1.9.4 when a new minikube version supports that.
_DEFAULT_K8S_VERSION=v1.10.0
: "${K8S_VERSION:=$_DEFAULT_K8S_VERSION}"
_DEFAULT_MINIKUBE_VERSION=v0.26.0
: "${MINIKUBE_VERSION:=$_DEFAULT_MINIKUBE_VERSION}"
_HELM_VERSION=v2.8.1

_UNAME_OUT=$(uname -s)
case "${_UNAME_OUT}" in
    Linux*)     _MY_OS=linux;;
    Darwin*)    _MY_OS=darwin;;
    *)          _MY_OS="UNKNOWN:${unameOut}"
esac
echo "Local OS is ${_MY_OS}"

export MINIKUBE_WANTUPDATENOTIFICATION=false
export MINIKUBE_WANTREPORTERRORPROMPT=false
export CHANGE_MINIKUBE_NONE_USER=true

cd $_MY_DIR

source lib/_k8s.sh

rm -rf tmp
mkdir -p bin tmp
if [[ ! -x bin/kubectl ]]; then
  echo Downloading kubectl, which is a requirement for using minikube.
  curl -Lo bin/kubectl  \
    https://storage.googleapis.com/kubernetes-release/release/${K8S_VERSION}/bin/${_MY_OS}/amd64/kubectl
  chmod +x bin/kubectl
fi
if [[ ! -x bin/minikube ]]; then
  echo Downloading minikube.
  curl -Lo bin/minikube  \
    https://storage.googleapis.com/minikube/releases/${MINIKUBE_VERSION}/minikube-${_MY_OS}-amd64
  chmod +x bin/minikube
fi
if [[ ! -x bin/helm ]]; then
  echo Downloading helm
  curl -Lo tmp/helm.tar.gz  \
    https://storage.googleapis.com/kubernetes-helm/helm-${_HELM_VERSION}-${_MY_OS}-amd64.tar.gz
  (cd tmp; tar xfz helm.tar.gz; mv ${_MY_OS}-amd64/helm ${_MY_DIR}/bin)
fi

export PATH="${_MY_DIR}/bin:$PATH"

if [[ "${USE_MINIKUBE_DRIVER_NONE:-}" = "true" ]]; then
  # Run minikube with none driver.
  # See https://blog.travis-ci.com/2017-10-26-running-kubernetes-on-travis-ci-with-minikube
  _VM_DRIVER="--vm-driver=none"
  if [[ ! -x /usr/local/bin/nsenter ]]; then
    # From https://engineering.bitnami.com/articles/implementing-kubernetes-integration-tests-in-travis.html
    # Travis ubuntu trusty env doesn't have nsenter, needed for --vm-driver=none
    which nsenter >/dev/null && return 0
    echo "INFO: Building 'nsenter' ..."
cat <<-EOF | docker run -i --rm -v "$(pwd):/build" ubuntu:14.04 >& nsenter.build.log
        apt-get update
        apt-get install -qy git bison build-essential autopoint libtool automake autoconf gettext pkg-config
        git clone --depth 1 git://git.kernel.org/pub/scm/utils/util-linux/util-linux.git /tmp/util-linux
        cd /tmp/util-linux
        ./autogen.sh
        ./configure --without-python --disable-all-programs --enable-nsenter
        make nsenter
        cp -pfv nsenter /build
EOF
    if [ ! -f ./nsenter ]; then
        echo "ERROR: nsenter build failed, log:"
        cat nsenter.build.log
        return 1
    fi
    echo "INFO: nsenter build OK"
    sudo mv ./nsenter /usr/local/bin
  fi
fi

_MINIKUBE="minikube"
if [[ "${USE_SUDO_MINIKUBE:-}" = "true" ]]; then
  _MINIKUBE="sudo PATH=$PATH bin/minikube"
fi

# The default bootstrapper kubeadm assumes CentOS. Travis is Debian.
$_MINIKUBE config set bootstrapper localkube
$_MINIKUBE config set ShowBootstrapperDeprecationNotification false || true
$_MINIKUBE start --kubernetes-version=${K8S_VERSION}  \
  ${_VM_DRIVER:-}
# Fix the kubectl context, as it's often stale.
$_MINIKUBE update-context
echo Minikube disks:
if [[ "${USE_MINIKUBE_DRIVER_NONE:-}" = "true" ]]; then
  # minikube does not support ssh for --vm-driver=none
  df
else
  $_MINIKUBE ssh df
fi

# Wait for Kubernetes to be up and ready.
k8s_single_node_ready

echo Minikube addons:
$_MINIKUBE addons list
kubectl get storageclass
echo Showing kube-system pods
kubectl get -n kube-system pods

(k8s_single_pod_ready -n kube-system -l component=kube-addon-manager) ||
  (_ADDON=$(kubectl get pod -n kube-system -l component=kube-addon-manager
      --no-headers -o name| cut -d/ -f2);
   echo Addon-manager describe:;
   kubectl describe pod -n kube-system $_ADDON;
   echo Addon-manager log:;
   kubectl logs -n kube-system $_ADDON;
   exit 1)
k8s_single_pod_ready -n kube-system -l k8s-app=kube-dns
k8s_single_pod_ready -n kube-system storage-provisioner

helm init
k8s_single_pod_ready -n kube-system -l name=tiller
