ConfigMap entry storing the resolv.conf file that goes inside HDFS `namenode`
and `datanode` pods.

### Usage

  1. Find the service IP of your `kube-dns` of your k8s cluster.
     Try the following command and find the IP value in the output.
     It will be supplied below as the `clusterDnsIP` parameter.

  ```
  $ kubectl get svc --all-namespaces | grep kube-dns
  ```

  2. Find the domain name of your cluster that is part of
     cluster node host names. e.g. MYCOMPANY.COM in kube-n1.MYCOMPANY.COM.
     Default is "".  This will be supplied below as
     the `hostNetworkDomains` parameter.

  3. Optionally, find the domain name of pod and service host names.
     Default is `cluster.local`. See `values.yaml`
     for additional parameters to change. You can add them below in `--set`,
     as comma-separated entries.

  4. Launch this helm chart, `hdfs-resolv-conf`, while specifying
     the kube-dns name server IP and other parameters. (You can add multiple
     of them below in --set as comma-separated entries)

  ```
  $ helm install -n my-hdfs-resolv-conf --namespace kube-system  \
      --set clusterDnsIP=MY-KUBE-DNS-IP,hostNetworkDomains=MYCOMPANY.COM  \
      hdfs-resolv-conf
  ```
