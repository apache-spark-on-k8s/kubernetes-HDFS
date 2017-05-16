/*
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package org.apache.hadoop.net;

import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.Executors;
import javax.annotation.Nullable;
import javax.annotation.concurrent.GuardedBy;

import com.google.common.collect.ImmutableList;
import com.google.common.collect.Lists;
import com.google.common.collect.Maps;
import com.google.common.collect.Sets;
import com.google.common.net.InetAddresses;
import com.google.common.util.concurrent.ThreadFactoryBuilder;
import io.fabric8.kubernetes.api.model.Node;
import io.fabric8.kubernetes.api.model.NodeList;
import io.fabric8.kubernetes.client.Config;
import io.fabric8.kubernetes.client.ConfigBuilder;
import io.fabric8.kubernetes.client.DefaultKubernetesClient;
import io.fabric8.kubernetes.client.KubernetesClient;
import io.fabric8.kubernetes.client.utils.HttpClientUtils;
import okhttp3.Dispatcher;
import okhttp3.OkHttpClient;
import org.apache.commons.cli.BasicParser;
import org.apache.commons.cli.CommandLine;
import org.apache.commons.cli.CommandLineParser;
import org.apache.commons.cli.Option;
import org.apache.commons.cli.Options;
import org.apache.commons.cli.ParseException;
import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.apache.commons.net.util.SubnetUtils;
import org.apache.commons.net.util.SubnetUtils.SubnetInfo;
import org.apache.hadoop.conf.Configuration;
import org.apache.log4j.BasicConfigurator;
import org.apache.log4j.Level;
import org.apache.log4j.Logger;

/**
 * A namenode topology plugin mapping pods to cluster nodes for a K8s configured with pod CIDR.
 *
 * For each k8s pod, determines a network path with three components. The full path would look like:
 *
 *     RACK-NAME '/' NODE-NAME '/' POD-HOST
 *
 * , where NODE-NAME is the cluster node that the pod is running on.
 *
 * To comply with this, datanodes will be also put the node name into the same hierarchy.
 *
 *     RACK-NAME '/' NODE-NAME '/' NODE-NAME
 *
 * This way, the namenode will see the datanode and pods in the same node are closer than otherwise.
 *
 * The resolve method below only returns the first parts for input entries.
 *
 * Note this three level hierarchy requires NetworkTopologyWithNodeGroup to be used in namenode.
 * To use this plugin, add the followings to the hdfs-site.xml:
 * <pre>
 * {@code
 * <property>
 *   <name>net.topology.node.switch.mapping.impl</name>
 *   <value>org.apache.hadoop.net.PodCIDRToNodeMapping</value>
 * </property>
 * <property>
 *   <name>net.topology.impl</name>
 *   <value>org.apache.hadoop.net.NetworkTopologyWithNodeGroup</value>
 * </property>
 * <property>
 *   <name>net.topology.nodegroup.aware</name>
 *   <value>true</value>
 * </property>
 * <property>
 *   <name>dfs.block.replicator.classname</name>
 *   <value>org.apache.hadoop.hdfs.server.blockmanagement.BlockPlacementPolicyWithNodeGroup</value>
 * </property>
 * }
 * </pre>
 */
@SuppressWarnings("unused")
public class PodCIDRToNodeMapping extends AbstractDNSToSwitchMapping {

  private static final String DEFAULT_NETWORK_LOCATION = NetworkTopology.DEFAULT_RACK +
      NetworkTopologyWithNodeGroup.DEFAULT_NODEGROUP;

  private static Log log = LogFactory.getLog(PodCIDRToNodeMapping.class);
  private static Option nameOption = new Option("n", true, "Name to resolve");

  @GuardedBy("this")
  @Nullable private KubernetesClient kubernetesClient;
  @GuardedBy("this")
  @Nullable private PodCIDRLookup podCIDRLookup;

  @SuppressWarnings("unused")
  public PodCIDRToNodeMapping() {
    // Do nothing.
  }

  @SuppressWarnings("unused")
  public PodCIDRToNodeMapping(Configuration conf) {
    super(conf);
  }

  public List<String> resolve(List<String> names) {
    List<String> networkPathDirList = Lists.newArrayList();
    for (String name : names) {
      String networkPathDir = resolveName(name);
      networkPathDirList.add(networkPathDir);
    }
    if (log.isDebugEnabled()) {
      log.debug("Resolved " + names + " to " + networkPathDirList);
    }
    return ImmutableList.copyOf(networkPathDirList);
  }

  public void reloadCachedMappings() {
    // Do nothing.
  }

  public void reloadCachedMappings(List<String> list) {
    // Do nothing.
  }

  private String resolveName(String name) {
    String networkPathDir = resolveClusterNode(name);
    if (!DEFAULT_NETWORK_LOCATION.equals(networkPathDir)) {
      return networkPathDir;
    }
    return resolvePodIP(name);
  }

  private String resolveClusterNode(String clusterNodeName) {
    if (InetAddresses.isInetAddress(clusterNodeName)) {
      return DEFAULT_NETWORK_LOCATION;
    }
    String hostName = clusterNodeName.split("\\.")[0];
    PodCIDRLookup lookup = getOrFetchPodCIDR();
    if (lookup.containsNode(clusterNodeName) || lookup.containsNode(hostName)) {
      return getNetworkPathDir(hostName);
    }
    return DEFAULT_NETWORK_LOCATION;
  }

  private String resolvePodIP(String podIP) {
    if (!InetAddresses.isInetAddress(podIP)) {
      return DEFAULT_NETWORK_LOCATION;
    }
    PodCIDRLookup lookup = getOrFetchPodCIDR();
    String nodeName = lookup.findNodeByPodIP(podIP);
    if (nodeName.length() > 0) {
      return getNetworkPathDir(nodeName);
    }
    return DEFAULT_NETWORK_LOCATION;
  }

  private static String getNetworkPathDir(String node) {
    return NetworkTopology.DEFAULT_RACK + NodeBase.PATH_SEPARATOR_STR + node;
  }

  private synchronized PodCIDRLookup getOrFetchPodCIDR() {
    if (podCIDRLookup != null) {
      // TODO. Support refresh.
      return podCIDRLookup;
    }
    podCIDRLookup = PodCIDRLookup.fetchPodCIDR(getOrCreateKubernetesClient());
    if (log.isDebugEnabled()) {
      log.debug("Fetched pod CIDR per node and built a lookup" + podCIDRLookup);
    }
    return podCIDRLookup;
  }

  private synchronized KubernetesClient getOrCreateKubernetesClient() {
    if (kubernetesClient != null) {
      return kubernetesClient;
    }
    // Disable the ping thread that is not daemon, in order to allow the main thread to shut down
    // upon errors. Otherwise, the namenode will hang indefinitely.
    Config config = new ConfigBuilder()
        .withWebsocketPingInterval(0)
        .build();
    // Use a Dispatcher with a custom executor service that creates daemon threads. The default
    // executor service used by Dispatcher creates non-daemon threads.
    OkHttpClient httpClient = HttpClientUtils.createHttpClient(config).newBuilder()
        .dispatcher(new Dispatcher(
            Executors.newCachedThreadPool(
                new ThreadFactoryBuilder().setDaemon(true)
                    .setNameFormat("k8s-topology-plugin-%d")
                    .build())))
        .build();
    kubernetesClient = new DefaultKubernetesClient(httpClient, config);
    return kubernetesClient;
  }

  private static class PodCIDRLookup {

    // K8s cluster node names.
    private final Set<String> nodeNames;
    // K8s cluster node names indexed by pod subnet information. The top level map contains
    // netmask strings as keys. The second level map contains network addresses as keys.
    private final Map<String, Map<String, String>> nodeNameBySubnet;

    PodCIDRLookup() {
      this(Collections.<String>emptySet(), Collections.<String, Map<String, String>>emptyMap());
    }

    private PodCIDRLookup(Set<String> nodeNames,
        Map<String, Map<String, String>> nodeNameBySubnet) {
      this.nodeNames = nodeNames;
      this.nodeNameBySubnet = nodeNameBySubnet;
    }

    boolean containsNode(String nodeName) {
      return nodeNames.contains(nodeName);
    }

    String findNodeByPodIP(String podIP) {
      for (Map.Entry<String, Map<String, String>> entry : nodeNameBySubnet.entrySet()) {
        String netmask = entry.getKey();
        SubnetInfo subnetInfo;
        try {
          subnetInfo = new SubnetUtils(podIP, netmask).getInfo();
        } catch (IllegalArgumentException e) {
          log.warn(e);
          continue;
        }
        String networkAddress = subnetInfo.getNetworkAddress();
        Map<String, String> nodeNameByNetworkAddress = entry.getValue();
        String nodeName = nodeNameByNetworkAddress.get(networkAddress);
        if (nodeName != null) {
          return nodeName;
        }
      }
      return "";
    }

    static PodCIDRLookup fetchPodCIDR(KubernetesClient kubernetesClient) {
      Set<String> nodeNames = Sets.newHashSet();
      Map<String, Map<String, String>> nodeNameBySubnetInfo = Maps.newHashMap();
      NodeList nodes = kubernetesClient.nodes().list();
      for (Node node : nodes.getItems()) {
        String nodeName = node.getMetadata().getName();
        @Nullable String podCIDR = node.getSpec().getPodCIDR();
        if (podCIDR == null || podCIDR.length() == 0) {
          log.warn("Could not get pod CIDR for node " + nodeName);
          continue;
        }
        if (log.isDebugEnabled()) {
          log.debug("Found pod CIDR " + podCIDR + " for node " + nodeName);
        }
        nodeNames.add(nodeName);
        SubnetInfo subnetInfo;
        try {
          subnetInfo = new SubnetUtils(podCIDR).getInfo();
        } catch (IllegalArgumentException e) {
          log.debug(e);
          continue;
        }
        String netmask = subnetInfo.getNetmask();
        String networkAddress = subnetInfo.getNetworkAddress();
        Map<String, String> nodeNameByNetworkAddress = nodeNameBySubnetInfo.get(netmask);
        if (nodeNameByNetworkAddress == null) {
          nodeNameByNetworkAddress = Maps.newHashMap();
          nodeNameBySubnetInfo.put(netmask, nodeNameByNetworkAddress);
        }
        nodeNameByNetworkAddress.put(networkAddress, nodeName);
      }
      return new PodCIDRLookup(nodeNames, nodeNameBySubnetInfo);
    }
  }

  // For debugging purpose.
  public static void main(String[] args) throws ParseException {
    Options options = new Options();
    nameOption.setRequired(true);
    options.addOption(nameOption);
    CommandLineParser parser = new BasicParser();
    CommandLine cmd = parser.parse(options, args);

    BasicConfigurator.configure();
    Logger.getRootLogger().setLevel(Level.DEBUG);
    PodCIDRToNodeMapping plugin = new PodCIDRToNodeMapping();
    Configuration conf = new Configuration();
    plugin.setConf(conf);

    String nameToResolve = cmd.getOptionValue(nameOption.getOpt());
    List<String> networkPathDirs = plugin.resolve(Lists.newArrayList(nameToResolve));
    log.info("Resolved " + nameToResolve + " to " + networkPathDirs);
  }
}
