HDFS `namenode` running inside a kubernetes cluster. See the other chart for
`datanodes`.

### Prerequisite

  Requires Kubernetes version 1.5 and beyond, because `namenode` is using
  `StatefulSet`, which is available only in version 1.5 and later.

### Usage

  1. Attach a label to one of your k8s cluster host that will run the `namenode`
     daemon.

  ```
  $ kubectl label nodes YOUR-HOST hdfs-namenode-selector=hdfs-namenode-0
  ```

  2. Launch this helm chart, `hdfs-namenode-k8s`.

  ```
  $ helm install -n my-hdfs-namenode --namespace kube-system hdfs-k8s
  ```

  3. Confirm the daemon is launched.

  ```
  $ kubectl get pods --all-namespaces | grep hdfs-namenode
  kube-system   hdfs-namenode-0 1/1 Running   0 7m
  ```

There will be only one `namenode` instance. i.e. High Availability (HA) is not
supported at the moment. The `namenode` instance is supposed to be pinned to
a cluster host using a node label, as shown in the usage above. `Namenode`
mount a local disk directory using k8s `hostPath` volume.

`namenode` is using `hostNetwork` so it can see physical IPs of datanodes
without an overlay network such as weave-net mask them.

Note it runs under the `kube-system` namespace.

###Credits

This chart is using public Hadoop docker images hosted by
  [uhopper](https://hub.docker.com/u/uhopper/).
