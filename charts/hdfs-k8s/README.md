HDFS `namenode` and `datanodes` running inside a kubernetes cluster.

### Prerequisite

  Requires Kubernetes version 1.5 and beyond, because `namenode` is using
  `StatefulSet`, which is available only in version 1.5 and later.

### Usage

  1. Attach a label to one of your k8s cluster host that will run the `namenode`
     daemon.

  ```
  $ kubectl label nodes YOUR-HOST hdfs-namenode-selector=hdfs-namenode-0
  ```

  2. Find the IP of your `kube-dns` name server that resolves pod and service
     host names in your k8s cluster. Default is 10.96.0.10. It will be supplied
     below as the `clusterDnsIP` parameter. Try this command and find the IP
     value in the output:

  ```
  $ kubectl get services --all-namespaces | grep kube-dns
  kube-system   kube-dns 10.96.0.10 <none> 53/UDP,53/TCP 117d
  ```

  3. Optionally, find the domain name of your k8s cluster that become part of
     pod and service host names. Default is `cluster.local`. See `values.yaml`
     for additional parameters to change. You can add them below in `--set`,
     as comma-separated entries.

  4. Launch this helm chart, `hdfs-k8s`, while specifying the kube-dns name
     server IP and other parameters. (You can add multiple of them below in
     --set as comma-separated entries)

  ```
  $ helm install -n my-hdfs --namespace kube-system --set clusterDnsIP=10.96.0.10 hdfs-k8s
  ```

  5. Confirm the daemons are launched.

  ```
  $ kubectl get pods --all-namespaces | grep hdfs
  kube-system   hdfs-datanode-ajdcz 1/1 Running 0 7m
  kube-system   hdfs-datanode-f1w24 1/1 Running 0 7m
  ...
  kube-system   hdfs-namenode-0 1/1 Running   0 7m
  ```

There will be only one `namenode` instance. i.e. High Availability (HA) is not
supported at the moment. The `namenode` instance is supposed to be pinned to
a cluster host using a node label, as shown in the usage above. `Namenode`
mount a local disk directory using k8s `hostPath` volume.

`Datanode` daemons run on every cluster node. They also mount k8s `hostPath`
local disk volumes.

Note these daemons run under the `kube-system` namespace.

###Credits

This chart is using public Hadoop docker images hosted by
  [uhopper](https://hub.docker.com/u/uhopper/).
