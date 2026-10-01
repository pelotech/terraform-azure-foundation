locals {
  # What each CNI choice changes. cilium and kube-ovn are installed by cni-bootstrap after this module.
  cni_profiles = {
    cilium = {
      network_plugin = "none"
      cni_node_pool  = null
    }
    "kube-ovn" = {
      network_plugin = "none"
      cni_node_pool = {
        labels = { "kube-ovn/role" = "master" }
        taints = {
          kube_ovn_control_plane = { key = "kube-ovn.io/control-plane", value = "true", effect = "NoSchedule" }
        }
      }
    }
    "azure-cni" = {
      network_plugin = "azure"
      cni_node_pool  = null
    }
  }
  cni_profile = local.cni_profiles[var.cni]

  cni_node_pool_enabled = local.cni_profile.cni_node_pool != null && coalesce(var.cni_node_pool.enabled, true)
  cni_node_pool_labels  = try(local.cni_profile.cni_node_pool.labels, {})
  cni_node_pool_taints  = try(local.cni_profile.cni_node_pool.taints, {})
  # AKS takes taints as "key=value:Effect" strings.
  cni_node_pool_taint_strings = [for t in values(local.cni_node_pool_taints) : "${t.key}=${t.value}:${t.effect}"]
  cni_node_pool_selector      = join(",", [for k, v in local.cni_node_pool_labels : "${k}=${v}"])

  network_plugin      = local.cni_profile.network_plugin
  network_plugin_mode = local.network_plugin == "azure" && var.azure_cni.network_plugin_mode == "overlay" ? "overlay" : null
  network_data_plane  = local.network_plugin == "azure" ? var.azure_cni.network_data_plane : null
  # azurerm accepts pod_cidr with network_plugin none, and with azure only in overlay mode.
  pod_cidr       = local.network_plugin == "none" || local.network_plugin_mode == "overlay" ? var.pod_cidr : null
  dns_service_ip = coalesce(var.dns_service_ip, cidrhost(var.service_cidr, 10))
}
