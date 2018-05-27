#!/usr/bin/env bash

function run_test_case () {
  _run helm install -n my-hdfs-zookeeper hdfs-k8s  \
    --values ${_TEST_DIR}/values/common.yaml  \
    --set tags.all-subcharts=false  \
    --set subchart.zookeeper=true

  _run helm install -n my-hdfs-config hdfs-k8s  \
    --values ${_TEST_DIR}/values/common.yaml  \
    --set tags.all-subcharts=false  \
    --set subchart.config=true

  _run helm install -n my-hdfs-journalnode hdfs-k8s  \
    --values ${_TEST_DIR}/values/common.yaml  \
    --set tags.all-subcharts=false  \
    --set subchart.journalnode=true

  _run helm install -n my-hdfs-namenode hdfs-k8s  \
    --values ${_TEST_DIR}/values/common.yaml  \
    --set tags.all-subcharts=false  \
    --set subchart.namenode=true

  _run helm install -n my-hdfs-datanode hdfs-k8s  \
    --values ${_TEST_DIR}/values/common.yaml  \
    --set tags.all-subcharts=false  \
    --set subchart.datanode=true

  _run helm install -n my-hdfs-client hdfs-k8s  \
    --values ${_TEST_DIR}/values/common.yaml  \
    --set tags.all-subcharts=false  \
    --set subchart.client=true

  k8s_single_pod_ready -l app=zookeeper,release=my-hdfs-zookeeper
  k8s_all_pods_ready 3 -l app=hdfs-journalnode,release=my-hdfs-zookeeper
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
