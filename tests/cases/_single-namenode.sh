#!/usr/bin/env bash

function run_test_case () {

  _NODE=$(kubectl get node --no-headers -o name | cut -d/ -f2)
  kubectl label nodes $_NODE hdfs-namenode-selector=hdfs-namenode-0

  _run helm install -n my-hdfs-config hdfs-k8s  \
    --set tags.all-subcharts=false  \
    --set subchart.config=true  \
    --set global.fullnameOverride=my-hdfs  \
    --set global.namenodeHAEnabled=false

  _run helm install -n my-hdfs-namenode hdfs-k8s  \
    --set tags.all-subcharts=false  \
    --set subchart.simple-namenode=true  \
    --set global.fullnameOverride=my-hdfs  \
    --set global.namenodeHAEnabled=false  \
    --set "hdfs-simple-namenode-k8s.nameNodeHostPath=/mnt/sda1/hdfs-name"

  _run helm install -n my-hdfs-datanode hdfs-k8s  \
    --set tags.all-subcharts=false  \
    --set subchart.datanode=true  \
    --set global.fullnameOverride=my-hdfs  \
    --set global.namenodeHAEnabled=false  \
    --set "hdfs-datanode-k8s.dataNodeHostPath={/mnt/sda1/hdfs-data}"

  _run helm install -n my-hdfs-client hdfs-k8s  \
    --set tags.all-subcharts=false  \
    --set subchart.client=true  \
    --set global.fullnameOverride=my-hdfs  \
    --set global.namenodeHAEnabled=false

  k8s_single_pod_ready -l app=hdfs-namenode,release=my-hdfs-namenode
  k8s_single_pod_ready -l app=hdfs-datanode,release=my-hdfs-datanode
  k8s_single_pod_ready -l app=hdfs-client,release=my-hdfs-client
  _CLIENT=$(kubectl get pods -l app=hdfs-client,release=my-hdfs-client -o name |  \
      cut -d/ -f 2)
  echo Found client pod: $_CLIENT

  echo All pods:
  kubectl get pods

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
