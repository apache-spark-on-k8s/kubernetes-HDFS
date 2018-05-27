#!/usr/bin/env bash

function run_test_case () {
  _run helm install krb5-server  \
    --name my-krb5-server
  k8s_single_pod_ready -l app=krb5-server

  _KDC=$(kubectl get pod -l app=krb5-server --no-headers -o name | cut -d/ -f2)
  _run kubectl cp $_KDC:/etc/krb5.conf $_TEST_DIR/tmp/krb5.conf
  _run kubectl create configmap kerberos-config  \
    --from-file=$_TEST_DIR/tmp/krb5.conf

  _SECRET_CMD="kubectl create secret generic my-hdfs-kerberos-keytabs"
  _HOSTS="my-hdfs-journalnode-0.my-hdfs-journalnode.default.svc.cluster.local  \
    my-hdfs-journalnode-1.my-hdfs-journalnode.default.svc.cluster.local  \
    my-hdfs-journalnode-2.my-hdfs-journalnode.default.svc.cluster.local  \
    my-hdfs-namenode-0.my-hdfs-namenode.default.svc.cluster.local  \
    my-hdfs-namenode-1.my-hdfs-namenode.default.svc.cluster.local  \
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

  # Disables hostNetwork so namenode pods on a single minikube node can avoid
  # port conflict.
  _run helm install -n my-hdfs hdfs-k8s  \
    --set zookeeper.servers=1  \
    --set zookeeper.heap=100m  \
    --set zookeeper.resources.requests.memory=100m  \
    --set hdfs-namenode-k8s.hostNetworkEnabled=false  \
    --set global.zookeeperServers=1  \
    --set global.affinityEnabled=false  \
    --set "global.dataNodeHostPath={/mnt/sda1/hdfs-data}"  \
    --set global.kerberosEnabled=true  \
    --set global.kerberosRealm=MYCOMPANY.COM  \
    --set global.kerberosKeytabsSecret=my-hdfs-kerberos-keytabs

  k8s_single_pod_ready -l app=zookeeper,release=my-hdfs
  k8s_all_pods_ready 3 -l app=hdfs-journalnode,release=my-hdfs
  k8s_all_pods_ready 2 -l app=hdfs-namenode,release=my-hdfs
  k8s_single_pod_ready -l app=hdfs-datanode,release=my-hdfs
  k8s_single_pod_ready -l app=hdfs-client,release=my-hdfs
  _CLIENT=$(kubectl get pods -l app=hdfs-client,release=my-hdfs -o name |  \
      cut -d/ -f 2)
  echo Found client pod: $_CLIENT

  echo All pods:
  kubectl get pods

  echo All persistent volumes:
  kubectl get pv

  _NN0=my-hdfs-namenode-0
  kubectl exec $_NN0 -- sh -c "(apt install -y krb5-user > /dev/null)"  \
    || true
  _run kubectl exec $_NN0 --   \
    kinit -kt /etc/security/hdfs.keytab  \
    hdfs/my-hdfs-namenode-0.my-hdfs-namenode.default.svc.cluster.local@MYCOMPANY.COM
  _run kubectl exec $_NN0 -- hdfs dfsadmin -report
  _run kubectl exec $_NN0 -- hdfs haadmin -getServiceState nn0
  _run kubectl exec $_NN0 -- hdfs haadmin -getServiceState nn1
  _run kubectl exec $_NN0 -- hadoop fs -rm -r -f /tmp
  _run kubectl exec $_NN0 -- hadoop fs -mkdir /tmp
  _run kubectl exec $_NN0 -- hadoop fs -chmod 0777 /tmp

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
  kubectl delete secret my-hdfs-kerberos-keytabs || true
  helm delete --purge my-hdfs
}
