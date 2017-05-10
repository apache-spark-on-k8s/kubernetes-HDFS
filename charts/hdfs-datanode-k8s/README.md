HDFS `datanodes` running inside a kubernetes cluster. See the other chart for
`namenode`.

### Prerequisite

  Requires Kubernetes version 1.5 and beyond, because `namenode` is using
  `StatefulSet`, which is available only in version 1.5 and later.

  Make sure the `hdfs-resolv-conf` chart is launched. Also ensure `namenode` is
  fully launched using the corresponding chart. `Datanodes` rely
  on DNS to resolve the hostname of the namenode when they start up.

### Usage

  1. Optionally, find the domain name of your k8s cluster that becomes part of
     pod and service host names. Default is `cluster.local`. See `values.yaml`
     for additional parameters to change. You can add them below in `--set`,
     as comma-separated entries.

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
