#!/usr/bin/env bash

function run_test_case () {

  _NODE=$(kubectl get node --no-headers -o name | cut -d/ -f2)
  kubectl label nodes $_NODE hdfs-namenode-selector=hdfs-namenode-0

  _helm_diff_and_install ${_TEST_DIR}/gold/single-namenode.gold  \
    hdfs-k8s  \
    -n my-hdfs  \
    --set tags.ha=false  \
    --set tags.simple=true  \
    --set global.namenodeHAEnabled=false  \
    --set "hdfs-simple-namenode-k8s.nameNodeHostPath=/mnt/sda1/hdfs-name"  \
    --set "global.dataNodeHostPath={/mnt/sda1/hdfs-data}"

  if [[ "${DRY_RUN_ONLY:-false}" = "true" ]]; then
    return
  fi

  k8s_single_pod_ready -l app=hdfs-namenode,release=my-hdfs
  k8s_single_pod_ready -l app=hdfs-datanode,release=my-hdfs
  k8s_single_pod_ready -l app=hdfs-client,release=my-hdfs
  _CLIENT=$(kubectl get pods -l app=hdfs-client,release=my-hdfs -o name |  \
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
  helm delete --purge my-hdfs || true

  _NODE=$(kubectl get node --no-headers -o name | cut -d/ -f2) || true
  kubectl label nodes $_NODE hdfs-namenode-selector- || true
}
