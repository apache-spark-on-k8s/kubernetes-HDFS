#!/usr/bin/env bash

# Exit on error. Append "|| true" if you expect an error.
set -o errexit
# Exit on error inside any functions or subshells.
set -o errtrace
# Do not allow use of undefined vars. Use ${VAR:-} to use an undefined VAR
set -o nounset
# Catch the error in case mysqldump fails (but gzip succeeds) in `mysqldump |gzip`
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

cd $_CHART_DIR

kubectl cluster-info

function _run () {
  local attempts=2
  echo Running: "$@"
  until "$@"; do
    ((attempts--)) || return 1
    sleep 5
  done
}

_run helm install zookeeper  \
  --name my-zk  \
  --version 0.6.3 \
  --repo https://kubernetes-charts-incubator.storage.googleapis.com/  \
  --set servers=1,heap=100m,resources.requests.memory=100m
k8s_single_pod_ready -l app=zookeeper

_run helm install hdfs-journalnode-k8s  \
  --name my-hdfs-journalnode
k8s_all_pods_ready 3 -l app=hdfs-journalnode

# Disables hostNetwork so namenode pods on a single minikube node can avoid
# port conflict
_run helm install hdfs-namenode-k8s  \
  --name my-hdfs-namenode  \
  --set hostNetworkEnabled=false,zookeeperQuorum=my-zk-zookeeper-0.my-zk-zookeeper-headless.default.svc.cluster.local:2181
k8s_all_pods_ready 2 -l app=hdfs-namenode

_run helm install hdfs-datanode-k8s  \
  --name my-hdfs-datanode  \
  --set "dataNodeHostPath={/mnt/sda1/hdfs-data}"
k8s_single_pod_ready -l name=hdfs-datanode

echo All pods:
kubectl get pods

echo All persistent volumes:
kubectl get pv

_run helm install hdfs-client  \
  --name my-hdfs-client
k8s_single_pod_ready -l app=hdfs-client
_CLIENT=$(kubectl get pods -l app=hdfs-client --no-headers| cut -d' ' -f 1)
echo Found client pod $_CLIENT

_run kubectl exec $_CLIENT -- hdfs dfsadmin -report
_run kubectl exec $_CLIENT -- hdfs haadmin -getServiceState nn0
_run kubectl exec $_CLIENT -- hdfs haadmin -getServiceState nn1

_run kubectl exec $_CLIENT -- hadoop fs -rm -r -f /tmp
_run kubectl exec $_CLIENT -- hadoop fs -mkdir /tmp
_run kubectl exec $_CLIENT -- hadoop fs -copyFromLocal /opt/hadoop-2.7.2/share/hadoop/hdfs/lib /tmp
