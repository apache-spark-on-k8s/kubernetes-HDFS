#!/usr/bin/env bash

function run_test_case () {
  _run helm install zookeeper  \
    --name my-zk  \
    --version 0.6.3 \
    --repo https://kubernetes-charts-incubator.storage.googleapis.com/  \
    --set servers=1,heap=100m,resources.requests.memory=100m
  k8s_single_pod_ready -l app=zookeeper

  _run helm install hdfs-config-k8s  \
    --name my-hdfs-config  \
    --set fullnameOverride=hdfs-config  \
    --set zookeeperQuorum=my-zk-zookeeper-0.my-zk-zookeeper-headless.default.svc.cluster.local:2181

  _run helm install hdfs-journalnode-k8s  \
    --name my-hdfs-journalnode
  k8s_all_pods_ready 3 -l app=hdfs-journalnode

  # Disables hostNetwork so namenode pods on a single minikube node can avoid
  # port conflict
  _run helm install hdfs-namenode-k8s  \
    --name my-hdfs-namenode  \
    --set hostNetworkEnabled=false  \
    --set zookeeperQuorum=my-zk-zookeeper-0.my-zk-zookeeper-headless.default.svc.cluster.local:2181
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
  _CLIENT=$(kubectl get pods -l app=hdfs-client -o name| cut -d/ -f 2)
  echo Found client pod $_CLIENT

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
  local charts="my-hdfs-client  \
    my-hdfs-datanode  \
    my-hdfs-namenode  \
    my-hdfs-journalnode  \
    my-hdfs-config  \
    my-zk"
  for chart in $charts; do
    helm delete --purge $chart || true
  done
}
