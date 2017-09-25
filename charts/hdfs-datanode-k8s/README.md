HDFS `datanodes` running inside a kubernetes cluster. See the other chart for
`namenode`.

### Usage

  1. In some setup, the master node may launch a datanode. To prevent this,
     label the master node with `hdfs-datanode-exclude`.
  ```
  $ kubectl label node YOUR-MASTER-NAME hdfs-datanode-exclude=yes
  ```

  2. (Skip this if you do not plan to enable Kerberos)
     Conduct the Kerberos setups described in the namenode
     [README.md](../hdfs-namenode-k8s/README.md), if you have not done that
     already.

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
local disk volumes.  You may want to restrict access of `hostPath`
using `pod security policy`.
See [reference](https://github.com/kubernetes/examples/blob/master/staging/podsecuritypolicy/rbac/README.md))


`Datanodes` are using `hostNetwork` to register to `namenode` using
physical IPs.

Note they run under the `default` namespace.

###Credits

This chart is using public Hadoop docker images hosted by
[uhopper](https://hub.docker.com/u/uhopper/).
