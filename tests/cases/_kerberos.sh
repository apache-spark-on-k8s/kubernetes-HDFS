#!/usr/bin/env bash

function run_test_case () {
  _helm_diff_and_install ${_TEST_DIR}/gold/kerberos.gold  \
    hdfs-k8s  \
    -n my-hdfs  \
    --values ${_TEST_DIR}/values/common.yaml  \
    --values ${_TEST_DIR}/values/kerberos.yaml  \
    --set tags.kerberos=true

  if [[ "${DRY_RUN_ONLY:-false}" = "true" ]]; then
    return
  fi

  # The above helm command launches all components. However, core HDFS
  # componensts such as namenodes and datanodes are blocked by a expected
  # Kerberos configmap and secret. So we create them here.
  k8s_single_pod_ready -l app=hdfs-krb5,release=my-hdfs
  _KDC=$(kubectl get pod -l app=hdfs-krb5,release=my-hdfs --no-headers  \
      -o name | cut -d/ -f2)
  _run kubectl cp $_KDC:/etc/krb5.conf $_TEST_DIR/tmp/krb5.conf
  _run kubectl create configmap my-hdfs-krb5-config  \
    --from-file=$_TEST_DIR/tmp/krb5.conf

  _HOSTS=$(kubectl get nodes  \
    -o=jsonpath='{.items[*].status.addresses[?(@.type == "Hostname")].address}')
  _HOSTS+=$(kubectl describe configmap my-hdfs-config |  \
      grep -A 1 -e dfs.namenode.rpc-address.hdfs-k8s  \
          -e dfs.namenode.shared.edits.dir |  
      grep "<value>" |
      sed -e "s/<value>//"  \
          -e "s/<\/value>//"  \
          -e "s/:8020//"  \
          -e "s/qjournal:\/\///"  \
          -e "s/:8485;/ /g"  \
          -e "s/:8485\/hdfs-k8s//")

  echo Adding service principals for hosts $_HOSTS
  _SECRET_CMD="kubectl create secret generic my-hdfs-krb5-keytabs"
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
  echo Adding a K8s secret containing Kerberos keytab files
  _run $_SECRET_CMD

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

  _NN0=$(kubectl get pods -l app=hdfs-namenode,release=my-hdfs -o name |  \
    head -1 |  \
    cut -d/ -f2)
  kubectl exec $_NN0 -- sh -c "(apt update > /dev/null)"  \
    || true
  kubectl exec $_NN0 -- sh -c "(DEBIAN_FRONTEND=noninteractive apt install -y krb5-user > /dev/null)"  \
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

  kubectl exec $_CLIENT -- sh -c "(apt update > /dev/null)"  \
    || true
  kubectl exec $_CLIENT -- sh -c "(DEBIAN_FRONTEND=noninteractive apt install -y krb5-user > /dev/null)"  \
    || true

  _run kubectl exec $_CLIENT -- kinit -kt /tmp/user1.keytab user1@MYCOMPANY.COM
  _run kubectl exec $_CLIENT -- sh -c  \
    "(head -c 100M < /dev/urandom > /tmp/random-100M)"
  _run kubectl exec $_CLIENT -- hadoop fs -ls /
  _run kubectl exec $_CLIENT -- hadoop fs -copyFromLocal /tmp/random-100M /tmp
}

function cleanup_test_case() {
  kubectl delete configmap my-hdfs-krb5-config || true
  kubectl delete secret my-hdfs-krb5-keytabs || true
  helm delete --purge my-hdfs || true
}
