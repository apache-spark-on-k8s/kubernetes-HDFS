#!/usr/bin/env bash

function run_test_case () {

  _run helm install hdfs-config-k8s  \
    --name my-hdfs-config  \
    --set fullnameOverride=hdfs-config  \
    --set namenodeHAEnabled=false

  _NODE=$(kubectl get node --no-headers -o name | cut -d/ -f2)
  kubectl label nodes $_NODE hdfs-namenode-selector=hdfs-namenode-0

  _run helm install hdfs-simple-namenode-k8s  \
    --name my-hdfs-namenode  \
    --set "nameNodeHostPath=/mnt/sda1/hdfs-name"
  k8s_all_pods_ready 1 -l app=hdfs-namenode

  _run helm install hdfs-datanode-k8s  \
    --name my-hdfs-datanode  \
    --set "dataNodeHostPath={/mnt/sda1/hdfs-data}"
  k8s_single_pod_ready -l name=hdfs-datanode

  echo All pods:
  kubectl get pods

  _run helm install hdfs-client  \
    --name my-hdfs-client
  k8s_single_pod_ready -l app=hdfs-client
  _CLIENT=$(kubectl get pods -l app=hdfs-client -o name| cut -d/ -f 2)
  echo Found client pod $_CLIENT

  _run kubectl exec $_CLIENT -- hdfs dfsadmin -report

  _run kubectl exec $_CLIENT -- hadoop fs -rm -r -f /tmp
  _run kubectl exec $_CLIENT -- hadoop fs -mkdir /tmp
  _run kubectl exec $_CLIENT -- sh -c  \
    "(head -c 100M < /dev/urandom > /tmp/random-100M)"
  _run kubectl exec $_CLIENT -- hadoop fs -copyFromLocal /tmp/random-100M /tmp
}

function cleanup_test_case() {
  local charts="my-hdfs-client  \
    my-hdfs-datanode  \
    my-hdfs-namenode  \
    my-hdfs-config"
  for chart in $charts; do
    helm delete --purge $chart || true
  done

  _NODE=$(kubectl get node --no-headers -o name | cut -d/ -f2)
  kubectl label nodes $_NODE hdfs-namenode-selector-
}
