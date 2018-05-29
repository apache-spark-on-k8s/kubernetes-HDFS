---
layout: global
title: HDFS charts
---

# HDFS charts
Helm charts for launching HDFS daemons in a K8s cluster. The main entry-point
chart is `hdfs-k8s`, which is a uber-chart that specifies other charts as
dependency subcharts. This means you can launch all HDFS components using
`hdfs-k8s`.

Note that the HDFS charts are currently in pre-alpha quality. They are also
being heavily revised and are subject to change.

HDFS on K8s supports the following features:
  - namenode high availability (HA): HDFS namenode daemons are in charge of
    maintaining file system metadata concerning which directories have which
    files and where are the file data. Namenode crash will cause service outage.
    HDFS can run two namenodes in active/standby setup. HDFS on K8s supports HA.
  - K8s persistent volumes (PV) for metadata: Namenode crash will cause service
    outage. Losing namenode metadata can lead to loss of file system. HDFS on
    K8s can store the metadata in remote K8s persistent volumes so that metdata
    can remain intact even if both namenode daemons are lost or restarted.
  - K8s HostPath volumes for file data: HDFS datanodes daemons store actual
    file data. File data should also survive datanode crash or restart. HDFS on
    K8s store the file data on the local disks of the K8s cluster nodes using
    K8s HostPath volumes. (We plan to switch to a better mechanism, K8s
    persistent local volumes)
  - Kerberos: Vanilla HDFS is not secure. Intruders can easily write custom
    client code, put a fake user name in requests and steal data. Production
    HDFS often secure itself using Kerberos. HDFS on K8s supports Kerberos.

Here is the list of all charts.

  - hdfs-k8s: main uber-chart. Launches other charts.
  - hdfs-namenode-k8s: a statefulset and other K8s components for launching HDFS
    namenode daemons, which maintains file system metadata. The chart supports
    namenode high availability (HA).
  - hdfs-datanode-k8s: a daemonset and other K8s components for launching HDFS
    datanode daemons, which are responsible for storing file data.
  - hdfs-config-k8s: a configmap containing Hadoop config files for HDFS.
  - zookeeper: This chart is NOT in this repo. But hdfs-k8s pulls the zookeeper
    chart in the incubator remote repo
    (https://kubernetes-charts-incubator.storage.googleapis.com/)
    as a dependency and launhces zookeeper daemons. Zookeeper makes sure
    only one namenode is active in the HA setup, while the other namenode
    becomes standby.
  - hdfs-journalnode-k8s: a statefulset and other K8s components for launching
    HDFS journalnode quorums, which ensures the file system metadata are
    properly shared among the two namenode daemons in the HA setup.
  - hdfs-client-k8s: a pod that is configured to run Hadoop client commands
    for accessing HDFS.
  - hdfs-krb5-k8s: a size-1 statefulset and other K8s components for launching
    a Kerberos server, which can be used to secure HDFS. Disabled by default.
  - hdfs-simple-namenode-k8s: Disabled by default. A simpler variant of the
    namenode that runs only one namenode. i.e. This does not support HA. It does
    not support Kerberos either.

# Prerequisite

Requires Kubernetes 1.6+ as the `namenode` and `datanodes` are using
`ClusterFirstWithHostNet`, which was introduced in Kubernetes 1.6

# Usage
## Basic

The HDFS daemons can be launched using the main `hdfs-k8s` chart. First, build
the main chart using:

```
  $ helm repo add incubator  \
      https://kubernetes-charts-incubator.storage.googleapis.com/
  $ helm dependency build charts/hdfs-k8s
```

Then launch the main char. Specify the chart release name say "my-hdfs",
which will be the prefix of the K8s resource names for the HDFS components.

```
  $ helm install -n my-hdfs charts/hdfs-k8s
```

Wait for all daemons to be ready. Note some daemons may restart themselves
a few times before they become ready.

```
  $ kubectl get pod -l release=my-hdfs

  NAME                             READY     STATUS    RESTARTS   AGE
  my-hdfs-client-c749d9f8f-d5pvk   1/1       Running   0          2m
  my-hdfs-datanode-o7jia           1/1       Running   3          2m
  my-hdfs-datanode-p5kch           1/1       Running   3          2m
  my-hdfs-datanode-r3kjo           1/1       Running   3          2m
  my-hdfs-journalnode-0            1/1       Running   0          2m
  my-hdfs-journalnode-1            1/1       Running   0          2m
  my-hdfs-journalnode-2            1/1       Running   0          1m
  my-hdfs-namenode-0               1/1       Running   3          2m
  my-hdfs-namenode-1               1/1       Running   3          2m
  my-hdfs-zookeeper-0              1/1       Running   0          2m
  my-hdfs-zookeeper-1              1/1       Running   0          2m
  my-hdfs-zookeeper-2              1/1       Running   0          2m
```

Finally, test with the client pod:

```
  $ CLIENT=$(kubectl get pods -l app=hdfs-client,release=my-hdfs -o name |  \
      cut -d/ -f 2)
  $ kubectl exec $CLIENT -- hdfs dfsadmin -report
  $ kubectl exec $CLIENT -- hdfs haadmin -getServiceState nn0
  $ kubectl exec $CLIENT -- hdfs haadmin -getServiceState nn1

  $ kubectl exec $CLIENT -- hadoop fs -rm -r -f /tmp
  $ kubectl exec $CLIENT -- hadoop fs -mkdir /tmp
  $ kubectl exec $CLIENT -- sh -c  \
    "(head -c 100M < /dev/urandom > /tmp/random-100M)"
  $ kubectl exec $CLIENT -- hadoop fs -copyFromLocal /tmp/random-100M /tmp
```

## Kerberos

Kerberos can be enabled with a few related options:

```
  $ helm install -n my-hdfs charts/hdfs-k8s  \
    --set global.kerberosEnabled=true  \
    --set global.kerberosRealm=MYCOMPANY.COM  \
    --set tags.kerberos=true
```

This will launch all charts including the Kerberos server, which will become
ready pretty soon. However, HDFS daemon charts will be blocked as the deamons
require Kerberos service principals to be available. So we need to unblock
them by creating those principals.

First, create a configmap containing the common Kerberos config file:

```
  $ mkdir -p ~/tmp/
  $ KDC=$(kubectl get pod -l app=hdfs-krb5,release=my-hdfs --no-headers  \
      -o name | cut -d/ -f2)
  $ kubectl cp $KDC:/etc/krb5.conf ~/tmp/krb5.conf
  $ kubectl create configmap my-hdfs-krb5-config  \
      --from-file=~/tmp/krb5.conf
```

Create the service principals and passwords. Kerberos requires service
principals to be host specific. And some HDFS daemons are associated with your
K8s cluster nodes' host names.  So find your cluster node names first.
You can get them like:

```
  $ kubectl get nodes  \
    -o=jsonpath='{.items[*].status.addresses[?(@.type == "Hostname")].address}'
```

Suppose they are kube-n1.mycompany.com, kube-n2.mycompany.com and
kube-n3.mycompany.com.

Others HDFS daemons are also associated with Kubernetes virtual service names,
for instance my-hdfs-namenode-0.my-hdfs-namenode.default.svc.cluster.local.

You can get the list of the virtual service names from the hdfs configmap:

```
  $ kubectl describe configmap my-hdfs-config |  \
        grep -A 1 -e dfs.namenode.rpc-address.hdfs-k8s -e dfs.namenode.shared.edits.dir
        <name>dfs.namenode.rpc-address.hdfs-k8s.nn0</name>
        <value>my-hdfs-namenode-0.my-hdfs-namenode.default.svc.cluster.local:8020</value>
    --
        <name>dfs.namenode.rpc-address.hdfs-k8s.nn1</name>
        <value>my-hdfs-namenode-1.my-hdfs-namenode.default.svc.cluster.local:8020</value>
    --
        <name>dfs.namenode.shared.edits.dir</name>
        <value>qjournal://my-hdfs-journalnode-1.my-hdfs-journalnode.default.svc.cluster.local:8485;my-hdfs-journalnode-2.my-hdfs-journalnode.default.svc.cluster.local:8485;my-hdfs-journalnode-0.my-hdfs-journalnode.default.svc.cluster.local:8485/hdfs-k8s</value>
```

Then generate per-host principal accounts and password keytab files.

```
  $ SECRET_CMD="kubectl create secret generic my-hdfs-krb5-keytabs"

  $ HOSTS="my-hdfs-journalnode-0.my-hdfs-journalnode.default.svc.cluster.local  \
      my-hdfs-journalnode-1.my-hdfs-journalnode.default.svc.cluster.local  \
      my-hdfs-journalnode-2.my-hdfs-journalnode.default.svc.cluster.local  \
      my-hdfs-namenode-0.my-hdfs-namenode.default.svc.cluster.local  \
      my-hdfs-namenode-1.my-hdfs-namenode.default.svc.cluster.local  \
      kube-n1.mycompany.com  \
      kube-n2.mycompany.com  \
      kube-n3.mycompany.com"

  $ for HOST in $HOSTS; do
    kubectl exec $KDC -- kadmin.local -q  \
      "addprinc -randkey hdfs/$HOST@MYCOMPANY.COM"
    kubectl exec $KDC -- kadmin.local -q  \
      "addprinc -randkey HTTP/$HOST@MYCOMPANY.COM"
    kubectl exec $KDC -- kadmin.local -q  \
      "ktadd -norandkey -k /tmp/$HOST.keytab hdfs/$HOST@MYCOMPANY.COM HTTP/$HOST@MYCOMPANY.COM"
    kubectl cp $KDC:/tmp/$HOST.keytab ~/tmp/$HOST.keytab
    SECRET_CMD+=" --from-file=~/tmp/$HOST.keytab"
  done
```

The above was building a command using a shell variable `SECRET_CMD` for
creating a K8s secret that contains all keytab files. Run the command to create
the secret.

```
  $ $SECRET_CMD
```

This will unblock all HDFS daemon pods. Wait until they become ready.

Finally, test using the following command:

```
FIXME. fill out the section.
```
