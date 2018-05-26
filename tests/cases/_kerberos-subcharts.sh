#!/usr/bin/env bash

function run_test_case () {
  _run helm install krb5-server  \
    --name my-krb5-server
  k8s_single_pod_ready -l app=krb5-server

  _KDC=$(kubectl get pod -l app=krb5-server --no-headers -o name | cut -d/ -f2)
  _run kubectl cp $_KDC:/etc/krb5.conf $_TEST_DIR/tmp/krb5.conf
  _run kubectl create configmap kerberos-config  \
    --from-file=$_TEST_DIR/tmp/krb5.conf

  _run helm install zookeeper  \
    --name my-zk  \
    --version 0.6.3 \
    --repo https://kubernetes-charts-incubator.storage.googleapis.com/  \
    --set servers=1,heap=100m,resources.requests.memory=100m
  k8s_single_pod_ready -l app=zookeeper

  _SECRET_CMD="kubectl create secret generic hdfs-kerberos-keytabs"
  _HOSTS="hdfs-journalnode-0.hdfs-journalnode.default.svc.cluster.local  \
    hdfs-journalnode-1.hdfs-journalnode.default.svc.cluster.local  \
    hdfs-journalnode-2.hdfs-journalnode.default.svc.cluster.local  \
    hdfs-namenode-0.hdfs-namenode.default.svc.cluster.local  \
    hdfs-namenode-1.hdfs-namenode.default.svc.cluster.local  \
    $(kubectl get node --no-headers -o name | cut -d/ -f2)"
  for _HOST in $_HOSTS; do
    _run kubectl exec $_KDC -- kadmin.local -q  \
      "addprinc -randkey hdfs/$_HOST@MYCOMPANY.COM"
    _run kubectl exec $_KDC -- kadmin.local -q  \
      "addprinc -randkey HTTP/$_HOST@MYCOMPANY.COM"
    _run kubectl exec $_KDC -- kadmin.local -q  \
      "ktadd -norandkey -k /tmp/$_HOST.keytab hdfs/$_HOST@MYCOMPANY.COM HTTP/$_HOST@MYCOMPANY.COM"
    _run kubectl cp $_KDC:/tmp/$_HOST.keytab $_TEST_DIR/tmp/$_HOST.keytab
    _SECRET_CMD+=" --from-file=$_TEST_DIR/tmp/$_HOST.keytab"
  done
  _run $_SECRET_CMD

  _run helm install hdfs-config-k8s  \
    --name my-hdfs-config  \
    --set fullnameOverride=hdfs-config  \
    --set "dataNodeHostPath={/mnt/sda1/hdfs-data}"  \
    --set zookeeperQuorum=my-zk-zookeeper-0.my-zk-zookeeper-headless.default.svc.cluster.local:2181 \
    --set kerberosEnabled=true  \
    --set kerberosRealm=MYCOMPANY.COM

  _run helm install hdfs-journalnode-k8s  \
    --name my-hdfs-journalnode  \
    --set kerberosEnabled=true
  k8s_all_pods_ready 3 -l app=hdfs-journalnode

  # Disables hostNetwork so namenode pods on a single minikube node can avoid
  # port conflict
  _run helm install hdfs-namenode-k8s  \
    --name my-hdfs-namenode  \
    --set kerberosEnabled=true  \
    --set hostNetworkEnabled=false
  k8s_all_pods_ready 2 -l app=hdfs-namenode

  _run helm install hdfs-datanode-k8s  \
    --name my-hdfs-datanode  \
    --set kerberosEnabled=true  \
    --set "dataNodeHostPath={/mnt/sda1/hdfs-data}"
  k8s_single_pod_ready -l name=hdfs-datanode

  echo All pods:
  kubectl get pods

  echo All persistent volumes:
  kubectl get pv

  _NN0=hdfs-namenode-0
  kubectl exec $_NN0 -- sh -c "(apt install -y krb5-user > /dev/null)"  \
    || true
  _run kubectl exec $_NN0 --   \
    kinit -kt /etc/security/hdfs.keytab  \
    hdfs/hdfs-namenode-0.hdfs-namenode.default.svc.cluster.local@MYCOMPANY.COM
  _run kubectl exec $_NN0 -- hdfs dfsadmin -report
  _run kubectl exec $_NN0 -- hdfs haadmin -getServiceState nn0
  _run kubectl exec $_NN0 -- hdfs haadmin -getServiceState nn1
  _run kubectl exec $_NN0 -- hadoop fs -rm -r -f /tmp
  _run kubectl exec $_NN0 -- hadoop fs -mkdir /tmp
  _run kubectl exec $_NN0 -- hadoop fs -chmod 0777 /tmp

  _run helm install hdfs-client  \
    --name my-hdfs-client  \
    --set kerberosEnabled=true
  k8s_single_pod_ready -l app=hdfs-client
  _CLIENT=$(kubectl get pods -l app=hdfs-client -o name| cut -d/ -f 2)
  echo Found client pod $_CLIENT

  _run kubectl exec $_KDC -- kadmin.local -q  \
    "addprinc -randkey user1@MYCOMPANY.COM"
  _run kubectl exec $_KDC -- kadmin.local -q  \
    "ktadd -norandkey -k /tmp/user1.keytab user1@MYCOMPANY.COM"
  _run kubectl cp $_KDC:/tmp/user1.keytab $_TEST_DIR/tmp/user1.keytab
  _run kubectl cp $_TEST_DIR/tmp/user1.keytab $_CLIENT:/tmp/user1.keytab

  kubectl exec $_CLIENT -- sh -c "(apt install -y krb5-user > /dev/null)"  \
    || true

  _run kubectl exec $_CLIENT -- kinit -kt /tmp/user1.keytab user1@MYCOMPANY.COM
  _run kubectl exec $_CLIENT -- sh -c  \
    "(head -c 100M < /dev/urandom > /tmp/random-100M)"
  _run kubectl exec $_CLIENT -- hadoop fs -ls /
  _run kubectl exec $_CLIENT -- hadoop fs -copyFromLocal /tmp/random-100M /tmp
}

function cleanup_test_case() {
  kubectl delete configmap kerberos-config || true
  kubectl delete secret hdfs-kerberos-keytabs || true
  local charts="my-hdfs-client  \
    my-hdfs-datanode  \
    my-hdfs-namenode  \
    my-hdfs-journalnode  \
    my-hdfs-config  \
    my-zk  \
    my-krb5-server"
  for chart in $charts; do
    helm delete --purge $chart || true
  done
}
