HDFS namenode topology plugins for various Kubernetes network providers.

HDFS namenode handles RPC requests from clients. Namenode often gets the IP
addresses of clients from the remote endpoints of RPC connections.
In Kubernetes, HDFS clients may run inside pods. The client IP addresses can
be virtual pod IP addresses. This can confuse the namenode when it runs
the data locality optimization code, which requires the comparison of client
IP addresses against the IP addresses associated with datanodes. The latter
are physical IP addresses of cluster nodes that datanodes are running on.
The client pod virtual IP addresses would not match any datanode IP addresses.

We can configure namenode with the topology plugins in this directory to
correct the namenode data locality code. So far, we learned that only
Google Container Engine (GKE) suffers from the data locality issue caused
by the virtual pod IP addresses exposed to namenode. (See below)
GKE uses the native `kubenet` network provider.

  - TODO: Currently, there is no easy way to launch the namenode helm chart
    with a topology plugins configured. Build a new Docker image with
    topology plugins and support the configuration. See plugin README
    for installation/configuration instructions.

Many K8s network providers do not need any topology plugins.  Most K8s network
providers conduct IP masquerading or Network Address Translation (NAT), when pod
packets head outside the pod IP subnet. They rewrite headers of pod packets by
putting the physical IP addresses of the cluster nodes that pods are running on.
The namenode and datanodes use `hostNetwork` and their IP addresses are outside
the pod IP subnet. As the result, namenode will see the physical cluster node
IP address from client RPC connections originating from pods. The data locality
will work fine with them.

Here is the list of network providers that conduct NAT:

  - By design, overlay networks such as weave and flannel conduct NAT for any
    pod packet heading outside a local pod network. This means packets coming to
    a node IP also does NAT. (In overlay, pod packets heading to another pod in
    a different node puts back the pod IPs once they got inside the destination
    node)
  - Calico is a popular non-overlay network provider. It turns out Calico can be
    also configured to do NAT between pod subnet and node subnet thanks to the
    `nat-outgoing` option. The option can be easily turned on and is enabled
    by default.
  - In EC2, the standard tool kops can provision k8s clusters using the same
    native kubenet that GKE uses. Unlike GKE, it turns out kubenet in EC2 does
    NAT between pod subnet to host network. This is because kops sets option
    --non-masquerade-cidr=100.64.0.0/10 to cover only pod IP subnet. Traffic to
    IPs ouside this range will do NAT. In EC2, cluster hosts like 172.20.47.241
    sits outside this CIDR. This means pod packets heading to node IPs will do
    masquerading. (Note GKE kubenet uses the default value of
    --non-masquerade-cidr, 10.0.0.0/8, which covers both pod IP and node IP
    subnets. GKE does not expose any way to override this value)

Over time, we will also check the behaviors of other network providers and
document them here.

Here's how one can check if data locality in the namenode works.
  1. Launch a HDFS client pod and go inside the pod.
  ```
  $ kubectl run -i --tty hadoop --image=uhopper/hadoop:2.7.2  \
      --generator="run-pod/v1" --command -- /bin/bash
  ```
  2. Inside the pod, create a simple text file on HDFS.
  ```
  $ hadoop fs  \
      -fs hdfs://hdfs-namenode-0.hdfs-namenode.default.svc.cluster.local  \
      -cp file:/etc/hosts /hosts
  ```
  3. Set the number of replicas for the file to the number of your cluster
  nodes. This ensures that there will be a copy of the file in the cluster node
  that your client pod is running on. Wait some time until this happens.
  ```
  $ hadoop fs -setrep NUM-REPLICAS /hosts
  ```
  4. Run the following `hdfs cat` command. From the debug messages, see
  which datanode is being used. Make sure it is your local datanode. (You can
  get this from `$ kubectl get pods hadoop -o json | grep hostIP`. Do this
  outside the pod)
  ```
  $ hadoop --loglevel DEBUG fs  \
      -fs hdfs://hdfs-namenode-0.hdfs-namenode.default.svc.cluster.local  \
      -cat /hosts
  ...
  17/04/24 20:51:28 DEBUG hdfs.DFSClient: Connecting to datanode 10.128.0.4:50010
  ...
  ```

  If no, you should check if your local datanode is even in the list from the
  debug messsages above. If it is not, then this is because step (3) did not
  finish yet. Wait more. (You can use a smaller cluster for this test if that
  is possible)
  ```
  17/04/24 20:51:28 DEBUG hdfs.DFSClient: newInfo = LocatedBlocks{
    fileLength=199
      underConstruction=false
        blocks=[LocatedBlock{BP-347555225-10.128.0.2-1493066928989:blk_1073741825_1001;
        getBlockSize()=199; corrupt=false; offset=0;
        locs=[DatanodeInfoWithStorage[10.128.0.4:50010,DS-d2de9d29-6962-4435-a4b4-aadf4ea67e46,DISK],
        DatanodeInfoWithStorage[10.128.0.3:50010,DS-0728ffcf-f400-4919-86bf-af0f9af36685,DISK],
        DatanodeInfoWithStorage[10.128.0.2:50010,DS-3a881114-af08-47de-89cf-37dec051c5c2,DISK]]}]
          lastLocatedBlock=LocatedBlock{BP-347555225-10.128.0.2-1493066928989:blk_1073741825_1001;
  ```
  5. Repeat the `hdfs cat` command multiple times. Check if the same datanode
  is being consistently used.
