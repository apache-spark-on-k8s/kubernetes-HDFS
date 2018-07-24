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
    K8s stores the file data on the local disks of the K8s cluster nodes using
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
    becomes standby. By default, we will launch three zookeeper servers.
  - hdfs-journalnode-k8s: a statefulset and other K8s components for launching
    HDFS journalnode quorums, which ensures the file system metadata are
    properly shared among the two namenode daemons in the HA setup.
    By default, we will launch three journalnode servers.
  - hdfs-client-k8s: a pod that is configured to run Hadoop client commands
    for accessing HDFS.
  - hdfs-krb5-k8s: a size-1 statefulset and other K8s components for launching
    a Kerberos server, which can be used to secure HDFS. Disabled by default.
  - hdfs-simple-namenode-k8s: Disabled by default. A simpler setup of the
    namenode that launches only one namenode. i.e. This does not support HA. It
    does not support Kerberos nor persistent volumes either. As it does not
    support HA, we also don't need zookeeper nor journal nodes.  You may prefer
    this if you want the simplest possible setup.

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

Zookeeper, journalnodes and namenodes need persistent volumes for storing
metadata. By default, the helm charts do not set the storage class name for
dynamically provisioned volumes, nor does it use persistent volume selectors for
static persistent volumes.

This means it will rely on a provisioner for default storage volume class for
dynamic volumes. Or if your cluster has statically provisioned volumes, the
chart will match existing volumes entirely based on the size requirements. To
override this default behavior, you can specify storage volume classes for
dynamic volumes, or volume selectors for static volumes. See below for how to
set these options.

  - namenodes: Each of the two namenodes needs at least a 100 GB volume.  i.e.
    Yon need two 100 GB volumes. This can be overridden by the
    `hdfs-namenode-k8s.persistence.size` option.
    You can also override the storage class or the selector using
    `hdfs-namenode-k8s.persistence.storageClass`, or
    `hdfs-namenode-k8s.persistence.selector` respectively. For details, see the
    values.yaml file inside `hdfs-namenode-k8s` chart dir.
  - zookeeper: You need three > 5 GB volumes. i.e. Each of the two zookeeper
    servers will need at least 5 GB in the volume. Can be overridden by
    the `zookeeper.persistence.size` option. You can also override
    the storage class using `zookeeper.persistence.storageClass`.
  - journalnodes: Each of the three journalnodes will need at least 20 GB in
    the volume. The size can be overridden by the
    `hdfs-journalnode-k8s.persistence.size` option.
    You can also override the storage class or the selector using
    `hdfs-journalnode-k8s.persistence.storageClass`, or
    `hdfs-journalnode-k8s.persistence.selector` respectively. For details, see the
    values.yaml file inside `hdfs-journalnode-k8s` chart dir.
  - kerberos: The single Kerberos server will need at least 20 GB in the volume.
    The size can be overridden by the `hdfs-krb5-k8s.persistence.size` option.
    You can also override the storage class or the selector using
    `hdfs-krb5-k8s.persistence.storageClass`, or
    `hdfs-krb5-k8s.persistence.selector` respectively. For details, see the
    values.yaml file inside `hdfs-krb5-k8s` chart dir.

Then launch the main chart. Specify the chart release name say "my-hdfs",
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

Namenodes and datanodes are currently using the K8s `hostNetwork` so they can
see physical IPs of each other. If they are not using `hostNetowrk`,
overlay K8s network providers such as weave-net may mask the physical IPs,
which will confuse the data locality later inside namenodes.

Finally, test with the client pod:

```
  $ _CLIENT=$(kubectl get pods -l app=hdfs-client,release=my-hdfs -o name |  \
      cut -d/ -f 2)
  $ kubectl exec $_CLIENT -- hdfs dfsadmin -report
  $ kubectl exec $_CLIENT -- hdfs haadmin -getServiceState nn0
  $ kubectl exec $_CLIENT -- hdfs haadmin -getServiceState nn1

  $ kubectl exec $_CLIENT -- hadoop fs -rm -r -f /tmp
  $ kubectl exec $_CLIENT -- hadoop fs -mkdir /tmp
  $ kubectl exec $_CLIENT -- sh -c  \
    "(head -c 100M < /dev/urandom > /tmp/random-100M)"
  $ kubectl exec $_CLIENT -- hadoop fs -copyFromLocal /tmp/random-100M /tmp
```

## Kerberos

Kerberos can be enabled by setting a few related options:

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
  _MY_DIR=~/krb5
  mkdir -p $_MY_DIR
  _KDC=$(kubectl get pod -l app=hdfs-krb5,release=my-hdfs --no-headers  \
      -o name | cut -d/ -f2)
  _run kubectl cp $_KDC:/etc/krb5.conf $_MY_DIR/tmp/krb5.conf
  _run kubectl create configmap my-hdfs-krb5-config  \
    --from-file=$_MY_DIR/tmp/krb5.conf
```

Second, create the service principals and passwords. Kerberos requires service
principals to be host specific. Some HDFS daemons are associated with your K8s
cluster nodes' physical host names say kube-n1.mycompany.com, while others are
associated with Kubernetes virtual service names, for instance
my-hdfs-namenode-0.my-hdfs-namenode.default.svc.cluster.local. You can get
the list of these host names like:

```
  $ _HOSTS=$(kubectl get nodes  \
    -o=jsonpath='{.items[*].status.addresses[?(@.type == "Hostname")].address}')

  $ _HOSTS+=$(kubectl describe configmap my-hdfs-config |  \
      grep -A 1 -e dfs.namenode.rpc-address.hdfs-k8s  \
          -e dfs.namenode.shared.edits.dir |  
      grep "<value>" |
      sed -e "s/<value>//"  \
          -e "s/<\/value>//"  \
          -e "s/:8020//"  \
          -e "s/qjournal:\/\///"  \
          -e "s/:8485;/ /g"  \
          -e "s/:8485\/hdfs-k8s//")
```

Then generate per-host principal accounts and password keytab files.

```
  $ _SECRET_CMD="kubectl create secret generic my-hdfs-krb5-keytabs"
  $ for _HOST in $_HOSTS; do
      kubectl exec $_KDC -- kadmin.local -q  \
        "addprinc -randkey hdfs/$_HOST@MYCOMPANY.COM"
      kubectl exec $_KDC -- kadmin.local -q  \
        "addprinc -randkey HTTP/$_HOST@MYCOMPANY.COM"
      kubectl exec $_KDC -- kadmin.local -q  \
        "ktadd -norandkey -k /tmp/$_HOST.keytab hdfs/$_HOST@MYCOMPANY.COM HTTP/$_HOST@MYCOMPANY.COM"
      kubectl cp $_KDC:/tmp/$_HOST.keytab $_MY_DIR/tmp/$_HOST.keytab
      _SECRET_CMD+=" --from-file=$_MY_DIR/tmp/$_HOST.keytab"
    done
```

The above was building a command using a shell variable `SECRET_CMD` for
creating a K8s secret that contains all keytab files. Run the command to create
the secret.

```
  $ $_SECRET_CMD
```

This will unblock all HDFS daemon pods. Wait until they become ready.

Finally, test the setup using the following commands:

```
  $ _NN0=$(kubectl get pods -l app=hdfs-namenode,release=my-hdfs -o name |  \
      head -1 |  \
      cut -d/ -f2)
  $ kubectl exec $_NN0 -- sh -c "(apt install -y krb5-user > /dev/null)"  \
      || true
  $ kubectl exec $_NN0 --   \
      kinit -kt /etc/security/hdfs.keytab  \
      hdfs/my-hdfs-namenode-0.my-hdfs-namenode.default.svc.cluster.local@MYCOMPANY.COM
  $ kubectl exec $_NN0 -- hdfs dfsadmin -report
  $ kubectl exec $_NN0 -- hdfs haadmin -getServiceState nn0
  $ kubectl exec $_NN0 -- hdfs haadmin -getServiceState nn1
  $ kubectl exec $_NN0 -- hadoop fs -rm -r -f /tmp
  $ kubectl exec $_NN0 -- hadoop fs -mkdir /tmp
  $ kubectl exec $_NN0 -- hadoop fs -chmod 0777 /tmp
  $ kubectl exec $_KDC -- kadmin.local -q  \
      "addprinc -randkey user1@MYCOMPANY.COM"
  $ kubectl exec $_KDC -- kadmin.local -q  \
      "ktadd -norandkey -k /tmp/user1.keytab user1@MYCOMPANY.COM"
  $ kubectl cp $_KDC:/tmp/user1.keytab $_MY_DIR/tmp/user1.keytab
  $ kubectl cp $_MY_DIR/tmp/user1.keytab $_CLIENT:/tmp/user1.keytab

  $ kubectl exec $_CLIENT -- sh -c "(apt install -y krb5-user > /dev/null)"  \
      || true

  $ kubectl exec $_CLIENT -- kinit -kt /tmp/user1.keytab user1@MYCOMPANY.COM
  $ kubectl exec $_CLIENT -- sh -c  \
      "(head -c 100M < /dev/urandom > /tmp/random-100M)"
  $ kubectl exec $_CLIENT -- hadoop fs -ls /
  $ kubectl exec $_CLIENT -- hadoop fs -copyFromLocal /tmp/random-100M /tmp
```

## Advanced options

### Setting HostPath volume locations for datanodes

HDFS on K8s stores the file data on the local disks of the K8s cluster nodes
using K8s HostPath volumes. You may want to change the default locations. Set
global.dataNodeHostPath to override the default value. Note the option
takes a list in case you want to use multiple disks.

```
  $ helm install -n my-hdfs charts/hdfs-k8s  \
      --set "global.dataNodeHostPath={/mnt/sda1/hdfs-data0,/mnt/sda1/hdfs-data1}"
```

### Using an existing zookeeper quorum

By default, HDFS on K8s pulls in the zookeeper chart in the incubator remote
repo (https://kubernetes-charts-incubator.storage.googleapis.com/) as a
dependency and launhces zookeeper daemons. But your K8s cluster may already
have a zookeeper quorum.

It is possible to use the existing zookeeper. We just need set a few options
in the helm install command line. It should be something like:

```
  $helm install -n my-hdfs charts/hdfs-k8s  \
    --set condition.subchart.zookeeper=false  \
    --set global.zookeeperQuorumOverride=zk-0.zk-svc.default.svc.cluster.local:2181,zk-1.zk-svc.default.svc.cluster.local:2181,zk-2.zk-svc.default.svc.cluster.local:2181
```

Setting `condition.subchart.zookeeper` to false prevents the uber-chart from
bringing in zookeeper as sub-chart. And the `global.zookeeperQuorumOverride`
option specifies the custom address for a zookeeper quorum. Use your
zookeeper address here.

### Pinning namenodes to specific K8s cluster nodes

Optionally, you can attach labels to some of your k8s cluster nodes so that
namenodes will always run on those cluster nodes. This can allow your HDFS
client outside the Kubernetes cluster to expect stable IP addresses. When used
by those outside clients, Kerberos expects the namenode addresses to be stable.

```
  $ kubectl label nodes YOUR-HOST-1 hdfs-namenode-selector=hdfs-namenode
  $ kubectl label nodes YOUR-HOST-2 hdfs-namenode-selector=hdfs-namenode
```

You should add the nodeSelector option to the helm chart command:

```
  $ helm install -n my-hdfs charts/hdfs-k8s  \
     --set hdfs-namenode-k8s.nodeSelector.hdfs-namenode-selector=hdfs-namenode \
     ...
```

### Excluding datanodes from some K8s cluster nodes

You may want to exclude some K8s cluster nodes from datanodes launch target.
For instance, some K8s clusters may let the K8s cluster master node launch
a datanode. To prevent this, label the cluster nodes with
`hdfs-datanode-exclude`.

```
  $ kubectl label node YOUR-CLUSTER-NODE hdfs-datanode-exclude=yes
```

### Launching with a non-HA namenode

You may want non-HA namenode since it is the simplest possible setup.
Note this won't launch zookeepers nor journalnodes.

The single namenode is supposed to be pinned to a cluster host using a node
label.  Attach a label to one of your K8s cluster node.

```
  $ kubectl label nodes YOUR-CLUSTER-NODE hdfs-namenode-selector=hdfs-namenode-0
```

The non-HA setup does not even use persistent vlumes. So you don't even
need to prepare persistent volumes. Instead, it is using hostPath volume
of the pinned cluster node. So, just launch the chart while
setting options to turn off HA. You should add the nodeSelector option
so that the single namenode would find the hostPath volume of the same cluster
node when the pod restarts.

```
  $ helm install -n my-hdfs charts/hdfs-k8s  \
      --set tags.ha=false  \
      --set tags.simple=true  \
      --set global.namenodeHAEnabled=false  \
      --set hdfs-simple-namenode-k8s.nodeSelector.hdfs-namenode-selector=hdfs-namenode-0
```

# Security

## K8s secret containing Kerberos keytab files

The Kerberos setup creates a K8s secret containing all the keytab files of HDFS
daemon service princialps. This will be mounted onto HDFS daemon pods. You may
want to restrict access to this secret using k8s
[RBAC](https://kubernetes.io/docs/admin/authorization/rbac/), to minimize
exposure of the keytab files.

## HostPath volumes
`Datanode` daemons run on every cluster node. They also mount k8s `hostPath`
local disk volumes.  You may want to restrict access of `hostPath`
using `pod security policy`.
See [reference](https://github.com/kubernetes/examples/blob/master/staging/podsecuritypolicy/rbac/README.md))

## Credits

Many charts are using public Hadoop docker images hosted by
[uhopper](https://hub.docker.com/u/uhopper/).
