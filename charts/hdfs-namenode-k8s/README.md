---
layout: global
title: HDFS namenodes
---
HDFS `namenodes` in HA setup running inside a Kubernetes cluster.
See the other chart for `datanodes`.

### Usage

  1. Launch a zookeeper quorum. Zookeeper is needed to decide
     which namenode instance is active.
     You would need to provide persistent volumes for zookeeper.
     If your quorum is size 3 (default), you need 3 volumes.

     You can run Zookeeper in two different ways. Here, you can use
     `kubectl create` using a single StatefulSet yaml file.

     ```
     $ kubectl create -f  \
         https://raw.githubusercontent.com/kubernetes/contrib/master/statefulsets/zookeeper/zookeeper.yaml
     ```

     Alternatively, you can use a helm chart.

     ```
     $ helm install zookeeper  \
         --name my-zk  \
         --version 0.6.3 \
         --repo https://kubernetes-charts-incubator.storage.googleapis.com/
     ```

  2. Launch a journal node quorum. The journal node quorum is needed to
     synchronize metadata updates from the active namenode to the standby
     namenode. You would need to provide persistent volumes for journal node
     quorums. If your quorum is size 3 (default), you need 3 volumes.

     ```
     $ helm install -n my-hdfs-journalnode hdfs-journalnode
     ```

  3. (Skip this if you do not plan to enable Kerberos)
     Prepare Kerberos setup, following the steps below.

     - Create a config map containing your Kerberos config file. This will be
       mounted onto the namenode and datanode pods.

       ```
        $ kubectl create configmap kerberos-config --from-file=/etc/krb5.conf
       ```

       We have our own kerberos server in the `krb5-server` helm chart.
       Currently, this is used mainly by the integration tests. But you may
       choose to use this for your cluster as well. For details, see
       the integration test case `tests/cases/_kerberos.sh`.

     - Generate per-host principal accounts and password keytab files for the namenode
       and datanode daemons. This is typically done in your Kerberos KDC host. For example,
       suppose the namenode will run on the k8s cluster node kube-n1.mycompany.com,
       and your datanodes will run on kube-n1.mycompany.com and kube-n2.mycompany.com.
       And your Kerberos realm is MYCOMPANY.COM, then

       ```
        $ kadmin.local -q "addprinc -randkey hdfs/kube-n1.mycompany.com@MYCOMPANY.COM"
        $ kadmin.local -q "addprinc -randkey HTTP/kube-n1.mycompany.com@MYCOMPANY.COM"
        $ mkdir hdfs-keytabs
        $ kadmin.local -q "ktadd -norandkey  \
                  -k hdfs-keytabs/kube-n1.mycompany.com.keytab  \
                  hdfs/kube-n1.mycompany.com@MYCOMPANY.COM  \
                  HTTP/kube-n1.mycompany.com@MYCOMPANY.COM"

        $ kadmin.local -q "addprinc -randkey hdfs/kube-n2.mycompany.com@MYCOMPANY.COM"
        $ kadmin.local -q "addprinc -randkey HTTP/kube-n2.mycompany.com@MYCOMPANY.COM"
        $ kadmin.local -q "ktadd -norandkey  \
                  -k hdfs-keytabs/kube-n2.mycompany.com.keytab  \
                  hdfs/kube-n2.mycompany.com@MYCOMPANY.COM  \
                  HTTP/kube-n2.mycompany.com@MYCOMPANY.COM"
        $ kadmin.local -q "ktadd -norandkey  \
                  -k hdfs-keytabs/kube-n2.mycompany.com.keytab  \
                  hdfs/kube-n2.mycompany.com@MYCOMPANY.COM  \
                  HTTP/kube-n2.mycompany.com@MYCOMPANY.COM"
       ```

     - Create a k8s secret containing all the keytab files. This will be mounted
       onto the namenode and datanode pods. (You may want to restrict access to
       this secret using k8s
       [RBAC](https://kubernetes.io/docs/admin/authorization/rbac/),
       to minimize exposure of the keytab files.

       ```
        $ kubectl create secret generic hdfs-kerberos-keytabs  \
              --from-file=kube-n1.mycompany.com.keytab  \
              --from-file=kube-n2.mycompany.com.keytab
       ```

     Optionally, attach a label to some of your k8s cluster hosts that will
     run the `namenode` daemons. This can allow your HDFS client outside
     the Kubernetes cluster to expect stable IP addresses. When used by
     those outside clients, Kerberos expects the namenode addresses to be
     stable.

     ```
     $ kubectl label nodes YOUR-HOST-1 hdfs-namenode-selector=hdfs-namenode
     $ kubectl label nodes YOUR-HOST-2 hdfs-namenode-selector=hdfs-namenode
     ```

  4. Now it's time to launch namenodes using the helm chart, `hdfs-namenode-k8s`.
     But, you need to first provide two persistent volumes for storing
     metadata. Each volume should have at least 100 GB. (Can be overriden by
     the metadataVolumeSize helm option).

     With the volumes provided, you can launch the namenode HA with:

     ```
     $ helm install -n my-hdfs-namenode hdfs-namenode-k8s
     ```

     If you launched Zookeeper using the helm chart in step (2), the command
     line will be slightly different:

     ```
     $ helm install -n my-hdfs-namenode hdfs-namenode-k8s  \
         --set zookeeperQuorum=my-zk-zookeeper-0.my-zk-zookeeper-headless.default.svc.cluster.local:2181,my-zk-zookeeper-1.my-zk-zookeeper-headless.default.svc.cluster.local:2181,my-zk-zookeeper-2.my-zk-zookeeper-headless.default.svc.cluster.local:2181
     ```

     If enabling Kerberos, specify necessary options. For instance,
     ```
     $ helm install -n my-hdfs-namenode  \
         --set kerberosEnabled=true  \
         --set kerberosRealm=MYCOMPANY.COM  \
         hdfs-namenode-k8s
     ```
     The two variables above are required. For other variables, see values.yaml.

     If also using namenode labels for Kerberos, add
     the nodeSelector option:
     ```
     $ helm install -n my-hdfs-namenode  \
         --set kerberosEnabled=true  \
         --set kerberosRealm=MYCOMPANY.COM  \
         --set nodeSelector.hdfs-namenode-selector=hdfs-namenode \
         hdfs-namenode-k8s
     ```

  5. Confirm the daemons are launched.

     ```
     $ kubectl get pods | grep hdfs-namenode
     hdfs-namenode-0 1/1 Running   0 7m
     hdfs-namenode-1 1/1 Running   0 7m
     ```

`namenode` is using `hostNetwork` so it can see physical IPs of datanodes
without an overlay network such as weave-net masking them.

### Credits

This chart is using public Hadoop docker images hosted by
  [uhopper](https://hub.docker.com/u/uhopper/).
