HDFS `datanodes` running inside a kubernetes cluster. See the other chart for
`namenode`.

### Usage

  1. In some setup, the master node may launch a datanode. To prevent this,
     label the master node with `hdfs-datanode-exclude`.
  ```
  $ kubectl label node YOUR-MASTER-NAME hdfs-datanode-exclude=yes
  ```

  2. (Skip this if you do not plan to enable Kerberos)
     Prepare Kerberos setup, following the steps below.

     - Create a config map containg your Kerberos config file, if you have
       not done this already as part of the namenode launch. The config
       map will be mounted onto the namenode and datanode pods.

     ```
      $ kubectl create configmap kerberos-config --from-file=/etc/krb5.conf
     ```

     - Generate the principal account and password keytab file for your datanode
       daemons. This is typically done in your Kerberos KDC host. For example,
       if one of your datanodes will run on the k8s cluster node
       kube-n2.mycompany.com, and your Kerberos realm is MYCOMPANY.COM, then

     ```
      $ kadmin.local -q "addprinc -randkey hdfs/kube-n2.mycompany.com@MYCOMPANY.COM"
      $ kadmin.local -q "addprinc -randkey http/kube-n2.mycompany.com@MYCOMPANY.COM"
      $ kadmin.local -q "ktadd -norandkey -k kube-n2.hdfs.keytab  \
                hdfs/kube-n2.mycompany.com@MYCOMPANY.COM  \
                http/kube-n2.mycompany.com@MYCOMPANY.COM"
     ```
     Repeat the above for all of your other datanodes, applying different k8s
     cluster node names.

     - Copy the keytab files to the k8s cluster nodes. The keytab files will be
       mounted onto the datanode pods. (You may want to restrict which
       pods can use `hostPath` using k8s `PodSecurityPolicy` and `RBAC`
       to minimize exposure of the keytab files. See [reference](
       https://github.com/kubernetes/examples/blob/master/staging/podsecuritypolicy/rbac/README.md))

     ```
      $ ssh root@kube-n2.mycompany.com mkdir /hdfs-credentials
      $ scp root@kube-n2.hdfs.keytab kube-n2.mycompany.com:/hdfs-credentials/hdfs.keytab
      $ ssh root@kube-n2.mycompany.com chmod 0600 /hdfs-credentials/hdfs.keytab
     ```
     Repeat the above for all of your other datanodes, applying different k8s
     cluster node names.

  3. Launch this helm chart, `hdfs-datanode-k8s`.

  ```
  $ helm install -n my-hdfs-datanode hdfs-datanode-k8s
  ```

  If enabling Kerberos, specify necessary options. For instance,

  ```
  $ helm install -n my-hdfs-datanode  \
      --set kerberosEnabled=true,kerberosRealm=MYCOMPANY.COM hdfs-datanode-k8s
  ```
  The two variables above are required. For other variables, see values.yaml.

  4. Confirm the daemons are launched.

  ```
  $ kubectl get pods | grep hdfs-datanode-
  hdfs-datanode-ajdcz 1/1 Running 0 7m
  hdfs-datanode-f1w24 1/1 Running 0 7m
  ```

`Datanode` daemons run on every cluster node. They also mount k8s `hostPath`
local disk volumes.

`Datanodes` are using `hostNetwork` to register to `namenode` using
physical IPs.

Note they run under the `default` namespace.

###Credits

This chart is using public Hadoop docker images hosted by
[uhopper](https://hub.docker.com/u/uhopper/). When Kerberos is enabled,
we also use `jsvc` in a public docker image hosted by
[mschlimb](https://hub.docker.com/r/mschlimb).
