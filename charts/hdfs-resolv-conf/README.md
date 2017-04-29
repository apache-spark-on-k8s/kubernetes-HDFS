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
     the `hostNetworkDomains` parameter.  You can find these from the `search`
     line in the following `kubectl run` output. `hostNetworkDomains` comes
     after the pod and service domain name such as `cluster.local`.

  ```
  $ kubectl run -i -t --rm busybox --image=busybox --restart=Never  \
      --command -- cat /etc/resolv.conf
  ...
  search default.svc.cluster.local svc.cluster.local cluster.local MYCOMPANY.COM
  ...
  ```

     See `values.yaml`
     for additional parameters to change.

  3. Launch this helm chart, `hdfs-resolv-conf`, while specifying
     the kube-dns name server IP and other parameters. (You can add multiple
     of them below in --set as comma-separated entries)

  ```
  $ helm install -n my-hdfs-resolv-conf \
      --set clusterDnsIP=MY-KUBE-DNS-IP,hostNetworkDomains=MYCOMPANY.COM  \
      hdfs-resolv-conf
  ```
