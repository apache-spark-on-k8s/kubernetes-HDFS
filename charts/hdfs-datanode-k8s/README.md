HDFS `datanodes` running inside a kubernetes cluster. See the other chart for
`namenode`.

### Prerequisite

  Requires Kubernetes version 1.5 and beyond, because `namenode` is using
  `StatefulSet`, which is available only in version 1.5 and later.

  Make sure `namenode` is fully launched using the other chart. `Datanodes` rely
  on DNS to resolve the hostname of the namenode when they start up.

### Usage

  1. Find the IP of your `kube-dns` name server that resolves pod and service
     host names in your k8s cluster. Default is 10.96.0.10. It will be supplied
     below as the `clusterDnsIP` parameter. Try this command and find the IP
     value in the output:

  ```
  $ kubectl get services --all-namespaces | grep kube-dns
  kube-system   kube-dns 10.96.0.10 <none> 53/UDP,53/TCP 117d
  ```

  2. Optionally, find the domain name of your k8s cluster that become part of
     pod and service host names. Default is `cluster.local`. See `values.yaml`
     for additional parameters to change. You can add them below in `--set`,
     as comma-separated entries.

  3. Launch this helm chart, `hdfs-datanode-k8s`, while specifying
     the kube-dns name server IP and other parameters. (You can add multiple
     of them below in --set as comma-separated entries)

  ```
  $ helm install -n my-hdfs-datanode --namespace kube-system  \
      --set clusterDnsIP=10.96.0.10 hdfs-datanode-k8s
  ```

  5. Confirm the daemons are launched.

  ```
  $ kubectl get pods --all-namespaces | grep hdfs-datanode-
  kube-system   hdfs-datanode-ajdcz 1/1 Running 0 7m
  kube-system   hdfs-datanode-f1w24 1/1 Running 0 7m
  ```

`Datanode` daemons run on every cluster node. They also mount k8s `hostPath`
local disk volumes.

`Datanodes` are using `hostNetwork` to register to `namenode` using
physical IPs.

Note they run under the `kube-system` namespace.

###Credits

This chart is using public Hadoop docker images hosted by
  [uhopper](https://hub.docker.com/u/uhopper/).
