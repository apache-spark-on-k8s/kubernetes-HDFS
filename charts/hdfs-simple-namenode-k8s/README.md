A simple HDFS `namenode` setup running inside a kubernetes cluster. As a simple
setup, this does not support Kerberos or HA.
See the other chart for `datanodes`.

### Usage

  1. Attach a label to one of your k8s cluster host that will run the `namenode`
     daemon. (This is required as `namenode` currently mounts a local disk
     `hostPath` volume. We will switch to persistent volume in the future, so
     we can skip this step.)

  ```
  $ kubectl label nodes YOUR-HOST hdfs-namenode-selector=hdfs-namenode-0
  ```

  2. Launch this namenode helm chart, `hdfs-simple-namenode-k8s`.

  ```
  $ helm install -n my-hdfs-namenode hdfs-simple-namenode-k8s
  ```

  3. Confirm the daemon is launched.

  ```
  $ kubectl get pods | grep hdfs-namenode
  hdfs-namenode-0 1/1 Running   0 7m
  ```

There will be only one `namenode` instance. i.e. High Availability (HA) is not
supported in this setup. See the other chart `hdfs-namenode-k8s` for HA.
The single `namenode` instance is supposed to be pinned to
a cluster host using a node label, as shown in the usage above. `Namenode`
mount a local disk directory using k8s `hostPath` volume. You may want to
restrict access of `hostPath` using `pod security policy`.
See [reference](https://github.com/kubernetes/examples/blob/master/staging/podsecuritypolicy/rbac/README.md)

`namenode` is using `hostNetwork` so it can see physical IPs of datanodes
without an overlay network such as weave-net masking them.

###Credits

This chart is using public Hadoop docker images hosted by
  [uhopper](https://hub.docker.com/u/uhopper/).
