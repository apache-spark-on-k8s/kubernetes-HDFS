### Prerequisite

Requires Kubernetes 1.6 as the `namenode` and `datanodes` are using `ClusterFirstWithHostNet`, which was introduced in Kubernetes 1.6

### Usage

Helm charts for launching HDFS in a K8s cluster. They should be launched in
the following order.

  1. `hdfs-namenode-k8s`: Launches the hdfs namenodes in HA setup. See
     `hdfs-namenode-k8s/README.md` for how to launch.
  2. `hdfs-datanode-k8s`: Launches the hdfs datanode daemons. See
     `hdfs-datanode-k8s/README.md` for how to launch.

Kerberos is supported. See the `kerberosEnabled` option in the namenode and
datanode charts.
