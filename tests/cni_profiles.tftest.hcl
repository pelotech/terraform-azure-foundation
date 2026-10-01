# The cni profile drives the network plugin and the dedicated CNI pool,
# and the contract outputs cni-bootstrap reads. Resource-level checks land in cluster.tftest.hcl.

mock_provider "azurerm" {
  source = "./tests/mocks"
}

run "cilium_is_byo_cni_without_a_cni_pool" {
  command = plan
  variables {
    cni = "cilium"
  }
  assert {
    condition     = output.network_plugin_resolved == "none" && output.network_plugin_mode_resolved == null && output.network_data_plane_resolved == null
    error_message = "cilium must select network_plugin none with no plugin mode or data plane"
  }
  assert {
    condition     = output.cni_node_pool_enabled == false && output.cni_node_size == 0 && output.cni_node_selector == ""
    error_message = "cilium has no dedicated CNI pool"
  }
  assert {
    condition     = output.cluster_pod_cidr == "10.244.0.0/16" && output.cluster_service_cidr == "10.96.0.0/16" && output.dns_service_ip_resolved == "10.96.0.10"
    error_message = "BYO CNI must carry the pod cidr and the default service cidr with dns at .10"
  }
}

run "kube_ovn_adds_the_master_pool" {
  command = plan
  variables {
    cni           = "kube-ovn"
    cni_node_pool = { kubernetes_version = "1.34" }
  }
  assert {
    condition     = output.network_plugin_resolved == "none"
    error_message = "kube-ovn is BYO CNI"
  }
  assert {
    condition     = output.cni_node_pool_enabled == true && output.cni_node_size == 1
    error_message = "kube-ovn must enable a 1-node CNI pool by default"
  }
  assert {
    condition     = output.cni_node_selector == "kube-ovn/role=master"
    error_message = "the selector cni-bootstrap waits on must come from the profile label"
  }
  assert {
    condition     = output.cni_node_labels_resolved == { "kube-ovn/role" = "master" }
    error_message = "the CNI pool must carry the master label"
  }
  assert {
    condition     = output.cni_node_taints_resolved["kube_ovn_control_plane"].key == "kube-ovn.io/control-plane" && output.cni_node_taints_resolved["kube_ovn_control_plane"].effect == "NoSchedule"
    error_message = "the CNI pool must carry the control-plane taint with AKS effect casing"
  }
}

run "kube_ovn_pool_can_be_disabled_for_a_recycle" {
  command = plan
  variables {
    cni           = "kube-ovn"
    cni_node_pool = { kubernetes_version = "1.34", enabled = false }
  }
  assert {
    condition     = output.cni_node_pool_enabled == false && output.cni_node_size == 0
    error_message = "cni_node_pool.enabled = false must drop the pool and report size 0"
  }
  assert {
    condition     = output.cni_node_selector == "kube-ovn/role=master" && output.cni_node_labels_resolved == { "kube-ovn/role" = "master" }
    error_message = "selector and labels derive from the profile alone and survive the toggle"
  }
}

run "azure_cni_overlay_with_cilium_data_plane" {
  command = plan
  variables {
    cni       = "azure-cni"
    azure_cni = { network_data_plane = "cilium" }
  }
  assert {
    condition     = output.network_plugin_resolved == "azure" && output.network_plugin_mode_resolved == "overlay" && output.network_data_plane_resolved == "cilium"
    error_message = "azure-cni must render the managed plugin in overlay mode with the chosen data plane"
  }
  assert {
    condition     = output.cluster_pod_cidr == "10.244.0.0/16"
    error_message = "overlay mode keeps the pod cidr"
  }
}

run "azure_cni_node_subnet_mode_drops_the_pod_cidr" {
  command = plan
  variables {
    cni       = "azure-cni"
    azure_cni = { network_plugin_mode = "node-subnet" }
  }
  assert {
    condition     = output.network_plugin_mode_resolved == null && output.cluster_pod_cidr == null
    error_message = "node-subnet mode has no plugin mode and no pod cidr (azurerm rejects it)"
  }
}

run "custom_cidrs_flow_to_the_contract" {
  command = plan
  variables {
    service_cidr   = "172.20.0.0/16"
    dns_service_ip = "172.20.0.53"
    pod_cidr       = "192.168.0.0/16"
  }
  assert {
    condition     = output.cluster_service_cidr == "172.20.0.0/16" && output.dns_service_ip_resolved == "172.20.0.53" && output.cluster_pod_cidr == "192.168.0.0/16"
    error_message = "cidr inputs must pass through unchanged"
  }
}
