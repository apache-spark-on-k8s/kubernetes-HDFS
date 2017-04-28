Helm charts for launching HDFS in a K8s cluster. They should be launched in
the following order.

  1. `hdfs-resolv-conf`: Creates a config map containing resolv.conf used by
     the HDFS daemons. See `hdfs-resolv-conf/README.md` for how to launch.
  2. `hdfs-namenode-k8s`: Launches the hdfs namenode. See
     `hdfs-namenode-k8s/README.md` for how to launch.
  3. `hdfs-datanode-k8s`: Launches the hdfs datanode daemons. See
     `hdfs-datanode-k8s/README.md` for how to launch.
