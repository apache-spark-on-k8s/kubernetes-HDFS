---
layout: global
title: HDFS charts
---

# HDFS charts
Helm charts for launching HDFS daemons in a K8s cluster. Note that the HDFS
charts are currently being heavily revised and are subject to change.

# Prerequisite

Requires Kubernetes 1.6+ as the `namenode` and `datanodes` are using
`ClusterFirstWithHostNet`, which was introduced in Kubernetes 1.6

# Usage

The HDFS daemons should be launched in the following order.

  1. hdfs namenode daemons. For the High Availity (HA)
     setup, follow instructions in
     [hdfs-namenode-k8s/README.md](hdfs-namenode-k8s/README.md)
     Or if you do not want the HA setup, follow
     [hdfs-simple-namenode-k8s/README.md](hdfs-simple-namenode-k8s/README.md)
     instead.
  2. hdfs datanode daemons. See
     [hdfs-datanode-k8s/README.md](hdfs-datanode-k8s/README.md)
     for how to launch.

Kerberos is supported. See the `kerberosEnabled` option in the namenode and
datanode charts.

There is also a HDFS client chart `hdfs-client` that can be convenient for
testing.
