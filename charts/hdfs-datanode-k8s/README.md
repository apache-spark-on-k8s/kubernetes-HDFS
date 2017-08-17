HDFS `datanodes` running inside a kubernetes cluster. See the other chart for
`namenode`.

### Usage

  1. In some setup, the master node may launch a datanode. To prevent this,
     label the master node with `hdfs-datanode-exclude`.
  ```
  $ kubectl label node YOUR-MASTER-NAME hdfs-datanode-exclude=yes
  ```

  2. Launch this helm chart, `hdfs-datanode-k8s`.

  ```
  $ helm install -n my-hdfs-datanode hdfs-datanode-k8s
  ```

  3. Confirm the daemons are launched.

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
  [uhopper](https://hub.docker.com/u/uhopper/).
