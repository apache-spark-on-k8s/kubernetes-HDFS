#!/usr/bin/env bash

function run_test_case () {

  # Disables hostNetwork so namenode pods on a single minikube node can avoid
  # port conflict.
  _run helm install -n my-hdfs hdfs-k8s  \
    --set zookeeper.servers=1  \
    --set zookeeper.heap=100m  \
    --set zookeeper.resources.requests.memory=100m  \
    --set global.zookeeperServers=1  \
    --set global.affinityEnabled=false  \
    --set "global.dataNodeHostPath={/mnt/sda1/hdfs-data0,/mnt/sda1/hdfs-data1}"  \
    --set hdfs-namenode-k8s.hostNetworkEnabled=false  \
    --values ${_TEST_DIR}/values/custom-hadoop-config.yaml  \

  k8s_single_pod_ready -l app=zookeeper,release=my-hdfs
  k8s_all_pods_ready 3 -l app=hdfs-journalnode,release=my-hdfs
  k8s_all_pods_ready 2 -l app=hdfs-namenode,release=my-hdfs
  k8s_single_pod_ready -l app=hdfs-datanode,release=my-hdfs
  k8s_single_pod_ready -l app=hdfs-client,release=my-hdfs
  _CLIENT=$(kubectl get pods -l app=hdfs-client,release=my-hdfs -o name |  \
      cut -d/ -f 2)
  echo Found client pod $_CLIENT

  echo All pods:
  kubectl get pods

  echo All persistent volumes:
  kubectl get pv

  _run kubectl exec $_CLIENT -- hdfs dfsadmin -report
  _run kubectl exec $_CLIENT -- hdfs haadmin -getServiceState nn0
  _run kubectl exec $_CLIENT -- hdfs haadmin -getServiceState nn1

  _run kubectl exec $_CLIENT -- hadoop fs -rm -r -f /tmp
  _run kubectl exec $_CLIENT -- hadoop fs -mkdir /tmp
  _run kubectl exec $_CLIENT -- sh -c  \
    "(head -c 100M < /dev/urandom > /tmp/random-100M)"
  _run kubectl exec $_CLIENT -- hadoop fs -copyFromLocal /tmp/random-100M /tmp
}

function cleanup_test_case() {
  helm delete --purge my-hdfs
}
