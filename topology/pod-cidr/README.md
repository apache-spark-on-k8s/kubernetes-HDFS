A namenode topology plugin mapping pods to cluster nodes for a K8s configured
with pod CIDR. Currently, this is known to work only with the `kubenet` network
provider. For more details, see README.md of the parent directory.

## Installation
To use this plugin, add the followings to the hdfs-site.xml:

```
  <property>
    <name>net.topology.node.switch.mapping.impl</name>
    <value>org.apache.hadoop.net.PodCIDRToNodeMapping</value>
  </property>
  <property>
    <name>net.topology.impl</name>
    <value>org.apache.hadoop.net.NetworkTopologyWithNodeGroup</value>
  </property>
  <property>
    <name>net.topology.nodegroup.aware</name>
    <value>true</value>
  </property>
  <property>
    <name>dfs.block.replicator.classname</name>
    <value>org.apache.hadoop.hdfs.server.blockmanagement.BlockPlacementPolicyWithNodeGroup</value>
  </property>
```
