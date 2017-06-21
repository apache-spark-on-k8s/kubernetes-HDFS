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

import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.Executors;
import javax.annotation.Nullable;
import javax.annotation.concurrent.GuardedBy;

import com.google.common.collect.ImmutableList;
import com.google.common.collect.ImmutableMap;
import com.google.common.collect.ImmutableSet;
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
import org.apache.commons.lang3.tuple.ImmutablePair;
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
 * For details on installation instruction, see README.md at the project directory.
 */
@SuppressWarnings("unused")
public class PodCIDRToNodeMapping extends AbstractDNSToSwitchMapping {

  private static final String DEFAULT_NETWORK_LOCATION = NetworkTopology.DEFAULT_RACK +
      NetworkTopologyWithNodeGroup.DEFAULT_NODEGROUP;

  private static Log log = LogFactory.getLog(PodCIDRToNodeMapping.class);

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

  @Override
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

  @Override
  public void reloadCachedMappings() {
    // Do nothing.
  }

  @Override
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

  /**
   * Looks up a node that runs the pod with a given pod IP address.
   *
   * Each K8s node runs a number of pods. K8s pods have unique virtual IP addresses. In kubenet,
   * each node is assigned a pod IP subnet distinct from other nodes, which can be denoted by
   * a pod CIDR. For instance, node A can be assigned 10.0.0.0/24 while node B gets 10.0.1.0/24.
   * When a pod has an IP value, say 10.0.1.10, it should match node B.
   *
   * The key lookup data structure is the podSubnetToNode list below. The list contains 2-entry
   * tuples.
   *  - The first entry is netmask values of pod subnets. e.g. ff.ff.ff.00 for /24.
   *    (We expect only one netmask key for now, but the list can have multiple entries to support
   *    general cases)
   *  - The second entry is a map of a pod network address, associated with the netmask, to the
   *    cluster node. e.g. 10.0.0.0 -> node A and 10.0.1.0 -> node B.
   */
  private static class PodCIDRLookup {

    // See the class comment above.
    private final ImmutableList<ImmutablePair<Netmask,
        ImmutableMap<NetworkAddress, String>>> podSubnetToNode;
    // K8s cluster node names.
    private final ImmutableSet<String> nodeNames;

    PodCIDRLookup() {
      this(ImmutableList.<ImmutablePair<Netmask, ImmutableMap<NetworkAddress, String>>>of(),
          ImmutableSet.<String>of());
    }

    private PodCIDRLookup(
        ImmutableList<ImmutablePair<Netmask, ImmutableMap<NetworkAddress, String>>> podSubnetToNode,
        ImmutableSet<String> nodeNames) {
      this.nodeNames = nodeNames;
      this.podSubnetToNode = podSubnetToNode;
    }

    boolean containsNode(String nodeName) {
      return nodeNames.contains(nodeName);
    }

    String findNodeByPodIP(String podIP) {
      for (ImmutablePair<Netmask, ImmutableMap<NetworkAddress, String>> entry : podSubnetToNode) {
        Netmask netmask = entry.getLeft();
        ImmutableMap<NetworkAddress, String> networkToNode = entry.getRight();
        // Computes the subnet that results from the netmask applied to the pod IP.
        SubnetInfo podSubnetToCheck;
        try {
          podSubnetToCheck = new SubnetUtils(podIP, netmask.getValue()).getInfo();
        } catch (IllegalArgumentException e) {
          log.warn(e);
          continue;
        }
        String networkAddress = podSubnetToCheck.getNetworkAddress();
        String nodeName = networkToNode.get(new NetworkAddress(networkAddress));
        if (nodeName != null) {  // The cluster node is in charge of this pod IP subnet.
          return nodeName;
        }
      }
      return "";
    }

    static PodCIDRLookup fetchPodCIDR(KubernetesClient kubernetesClient) {
      Set<String> nodeNames = Sets.newHashSet();
      Map<String, Map<String, String>> netmaskToNetworkToNode = Maps.newHashMap();
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
        Map<String, String> networkToNode = netmaskToNetworkToNode.get(netmask);
        if (networkToNode == null) {
          networkToNode = Maps.newHashMap();
          netmaskToNetworkToNode.put(netmask, networkToNode);
        }
        networkToNode.put(networkAddress, nodeName);
      }
      return buildLookup(nodeNames, netmaskToNetworkToNode);
    }

    private static PodCIDRLookup buildLookup(Set<String> nodeNames,
        Map<String, Map<String, String>> netmaskToNetworkToNode) {
      ImmutableList.Builder<ImmutablePair<Netmask, ImmutableMap<NetworkAddress, String>>> builder =
          ImmutableList.builder();
      for (Map.Entry<String, Map<String, String>> entry : netmaskToNetworkToNode.entrySet()) {
        Netmask netmask = new Netmask(entry.getKey());
        ImmutableMap.Builder<NetworkAddress, String> networkToNodeBuilder = ImmutableMap.builder();
        for (Map.Entry<String, String> networkToNode : entry.getValue().entrySet()) {
          networkToNodeBuilder.put(new NetworkAddress(networkToNode.getKey()),
              networkToNode.getValue());
        }
        builder.add(ImmutablePair.of(netmask, networkToNodeBuilder.build()));
      }
      return new PodCIDRLookup(builder.build(), ImmutableSet.copyOf(nodeNames));
    }
  }

  private static class Netmask {

    private final String netmask;

    Netmask(String netmask) {
      this.netmask = netmask;
    }

    String getValue() {
      return netmask;
    }

    @Override
    public boolean equals(Object o) {
      if (this == o) {
        return true;
      }
      if (o == null || getClass() != o.getClass()) {
        return false;
      }
      Netmask netmask1 = (Netmask)o;
      return netmask.equals(netmask1.netmask);
    }

    @Override
    public int hashCode() {
      return netmask.hashCode();
    }
  }

  private static class NetworkAddress {

    private final String networkAddress;

    NetworkAddress(String networkAddress) {
      this.networkAddress = networkAddress;
    }

    String getValue() {
      return networkAddress;
    }

    @Override
    public boolean equals(Object o) {
      if (this == o) {
        return true;
      }
      if (o == null || getClass() != o.getClass()) {
        return false;
      }
      NetworkAddress that = (NetworkAddress)o;
      return networkAddress.equals(that.networkAddress);
    }

    @Override
    public int hashCode() {
      return networkAddress.hashCode();
    }
  }

  // For debugging purpose.
  public static void main(String[] args) throws ParseException {
    Options options = new Options();
    Option nameOption = new Option("n", true, "Name to resolve");
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
