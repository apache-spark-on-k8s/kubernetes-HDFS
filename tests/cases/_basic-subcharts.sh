#!/usr/bin/env bash

function run_test_case () {
  _helm_diff_and_install  \
    ${_TEST_DIR}/gold/subchart-zookeeper.gold  \
    hdfs-k8s  \
    -n my-hdfs-zookeeper  \
    --values ${_TEST_DIR}/values/common.yaml  \
    --set tags.ha=false  \
    --set condition.subchart.zookeeper=true  \
    --set zookeeper.fullnameOverride=my-hdfs-zookeeper  \
    --set global.fullnameOverride=my-hdfs

  _helm_diff_and_install  \
    ${_TEST_DIR}/gold/subchart-config.gold  \
    hdfs-k8s  \
    -n my-hdfs-config  \
    --values ${_TEST_DIR}/values/common.yaml  \
    --set tags.ha=false  \
    --set condition.subchart.config=true  \
    --set global.fullnameOverride=my-hdfs

  _helm_diff_and_install  \
    ${_TEST_DIR}/gold/subchart-journalnode.gold  \
    hdfs-k8s  \
    -n my-hdfs-journalnode  \
    --values ${_TEST_DIR}/values/common.yaml  \
    --set tags.ha=false  \
    --set condition.subchart.journalnode=true  \
    --set global.fullnameOverride=my-hdfs

  _helm_diff_and_install  \
    ${_TEST_DIR}/gold/subchart-namenode.gold  \
    hdfs-k8s  \
    -n my-hdfs-namenode  \
    --values ${_TEST_DIR}/values/common.yaml  \
    --set tags.ha=false  \
    --set condition.subchart.namenode=true  \
    --set global.fullnameOverride=my-hdfs

  _helm_diff_and_install  \
    ${_TEST_DIR}/gold/subchart-datanode.gold  \
    hdfs-k8s  \
    -n my-hdfs-datanode  \
    --values ${_TEST_DIR}/values/common.yaml  \
    --set tags.ha=false  \
    --set condition.subchart.datanode=true  \
    --set global.fullnameOverride=my-hdfs

  _helm_diff_and_install  \
    ${_TEST_DIR}/gold/subchart-client.gold  \
    hdfs-k8s  \
    -n my-hdfs-client \
    --values ${_TEST_DIR}/values/common.yaml  \
    --set tags.ha=false  \
    --set condition.subchart.client=true  \
    --set global.fullnameOverride=my-hdfs

  if [[ "${DRY_RUN_ONLY:-false}" = "true" ]]; then
    return
  fi

  k8s_single_pod_ready -l app=zookeeper,release=my-hdfs-zookeeper
  k8s_all_pods_ready 3 -l app=hdfs-journalnode,release=my-hdfs-journalnode
  k8s_all_pods_ready 2 -l app=hdfs-namenode,release=my-hdfs-namenode
  k8s_single_pod_ready -l app=hdfs-datanode,release=my-hdfs-datanode
  k8s_single_pod_ready -l app=hdfs-client,release=my-hdfs-client
  _CLIENT=$(kubectl get pods -l app=hdfs-client,release=my-hdfs-client -o name |  \
      cut -d/ -f 2)
  echo Found client pod: $_CLIENT

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
  local charts="my-hdfs-client  \
    my-hdfs-datanode  \
    my-hdfs-namenode  \
    my-hdfs-journalnode  \
    my-hdfs-config  \
    my-hdfs-zookeeper"
  for chart in $charts; do
    helm delete --purge $chart || true
  done
}
