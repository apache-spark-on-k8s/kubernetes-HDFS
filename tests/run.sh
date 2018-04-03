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

function _retry () {
  local attempts=3
  echo Running: "$@"
  until "$@"; do
    ((attempts--)) || return 1
    sleep 1
  done
}

_retry helm install zookeeper  \
  --name my-zk  \
  --version 0.6.3 \
  --repo https://kubernetes-charts-incubator.storage.googleapis.com/  \
  --set servers=1,heap=100m,resources.requests.memory=100m

_retry helm install hdfs-journalnode-k8s  \
  --name my-hdfs-journalnode

k8s_single_pod_ready -l app=zookeeper
k8s_all_pods_ready 3 -l app=hdfs-journalnode

# Disables hostNetwork so namenode pods on a single minikube node can avoid
# port conflict
_retry helm install hdfs-namenode-k8s  \
  --name my-hdfs-namenode  \
  --set hostNetworkEnabled=false,zookeeperQuorum=my-zk-zookeeper-0.my-zk-zookeeper.default.svc.cluster.local:2181

_retry helm install hdfs-datanode-k8s  \
  --name my-hdfs-datanode

k8s_all_pods_ready 2 -l app=hdfs-namenode
k8s_single_pod_ready -l name=hdfs-datanode

kubectl get pods

kubectl get pv

_retry helm install hdfs-client  \
  --name my-hdfs-client

k8s_single_pod_ready -l app=hdfs-client
CLIENT=$(kubectl get pods | grep hdfs-client | cut -d' ' -f 1)
echo Found client pod $CLIENT

kubectl exec $CLIENT -- hdfs dfsadmin -report
kubectl exec $CLIENT -- hdfs haadmin -getServiceState nn0
kubectl exec $CLIENT -- hdfs haadmin -getServiceState nn1

kubectl exec $CLIENT -- hadoop fs -rmr /tmp
kubectl exec $CLIENT -- hadoop fs -mkdir /tmp
kubectl exec $CLIENT -- hadoop fs -copyFromLocal /opt/hadoop-2.7.2/share/hadoop/hdfs/lib /tmp
