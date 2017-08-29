HDFS `namenode` running inside a kubernetes cluster. See the other chart for
`datanodes`.

### Usage

  1. Attach a label to one of your k8s cluster host that will run the `namenode`
     daemon. (This is required as `namenode` currently mounts a local disk
     `hostPath` volume. We will switch to persistent volume in the future, so
     we can skip this step.)

  ```
  $ kubectl label nodes YOUR-HOST hdfs-namenode-selector=hdfs-namenode-0
  ```

  2. (Skip this if you do not plan to enable Kerberos)
     Prepare Kerberos setup, following the steps below.

     - Create a config map containg your Kerberos config file. This will be
       mounted onto the namenode and datanode pods.

     ```
      $ kubectl create configmap kerberos-config --from-file=/etc/krb5.conf
     ```

     - Generate the principal account and password keytab file for the namenode
       daemon. This is typically done in your Kerberos KDC host. For example,
       if the namenode will run on the k8s cluster node kube-n1.mycompany.com,
       and your Kerberos realm is MYCOMPANY.COM, then

     ```
      $ kadmin.local -q "addprinc -randkey hdfs/kube-n1.mycompany.com@MYCOMPANY.COM"
      $ kadmin.local -q "addprinc -randkey http/kube-n1.mycompany.com@MYCOMPANY.COM"
      $ kadmin.local -q "ktadd -norandkey -k kube-n1.hdfs.keytab  \
                hdfs/kube-n1.mycompany.com@MYCOMPANY.COM  \
                http/kube-n1.mycompany.com@MYCOMPANY.COM"
     ```

     - Copy the keytab file to the k8s cluster node. This will be mounted
       onto the namenode pod as `hostPath`. (You may want to restrict which
       pods can use `hostPath` using k8s `PodSecurityPolicy` and `RBAC`
       to minimize exposure of the keytab files. See [reference](
       https://github.com/kubernetes/examples/blob/master/staging/podsecuritypolicy/rbac/README.md))
     ```
      $ ssh root@kube-n1.mycompany.com mkdir /hdfs-credentials
      $ scp root@kube-n1.hdfs.keytab kube-n1.mycompany.com:/hdfs-credentials/hdfs.keytab
      $ ssh root@kube-n1.mycompany.com chmod 0600 /hdfs-credentials/hdfs.keytab
     ```

  3. Launch this namenode helm chart, `hdfs-namenode-k8s`.

  ```
  $ helm install -n my-hdfs-namenode hdfs-namenode-k8s
  ```

  If enabling Kerberos, specify necessary options. For instance,
  ```
  $ helm install -n my-hdfs-namenode  \
      --set kerberosEnabled=true,kerberosRealm=MYCOMPANY.COM hdfs-namenode-k8s
  ```
  The two variables above are required. For other variables, see values.yaml.

  4. Confirm the daemon is launched.

  ```
  $ kubectl get pods | grep hdfs-namenode
  hdfs-namenode-0 1/1 Running   0 7m
  ```

There will be only one `namenode` instance. i.e. High Availability (HA) is not
supported at the moment. The `namenode` instance is supposed to be pinned to
a cluster host using a node label, as shown in the usage above. `Namenode`
mount a local disk directory using k8s `hostPath` volume.

`namenode` is using `hostNetwork` so it can see physical IPs of datanodes
without an overlay network such as weave-net mask them.

###Credits

This chart is using public Hadoop docker images hosted by
  [uhopper](https://hub.docker.com/u/uhopper/).
