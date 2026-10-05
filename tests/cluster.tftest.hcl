# AKS cluster settings, KMS, node pools and diagnostics.

mock_provider "azurerm" {
  source = "./tests/mocks"
}

run "defaults" {
  command = plan
  assert {
    condition     = length(azurerm_key_vault.kms) == 1 && azurerm_key_vault.kms[0].name == "kv-platformdev"
    error_message = "KMS is on by default with a vault named kv-<name>"
  }
  assert {
    condition     = azurerm_key_vault.kms[0].rbac_authorization_enabled == true && azurerm_key_vault.kms[0].purge_protection_enabled == true && azurerm_key_vault.kms[0].soft_delete_retention_days == 90
    error_message = "the vault must use RBAC authorization, purge protection and 90-day soft delete"
  }
  assert {
    condition     = azurerm_key_vault.kms[0].public_network_access_enabled == true
    error_message = "key_vault_network_access Public keeps the vault reachable from AKS"
  }
  assert {
    condition     = azurerm_key_vault_key.kms[0].key_type == "RSA" && azurerm_key_vault_key.kms[0].key_size == 2048 && azurerm_key_vault_key.kms[0].name == "platformdev-etcd"
    error_message = "an RSA 2048 key named <name>-etcd must exist"
  }
  assert {
    condition     = length(azurerm_kubernetes_cluster.this) == 1 && azurerm_kubernetes_cluster.this[0].name == "platformdev" && azurerm_kubernetes_cluster.this[0].dns_prefix == "platformdev"
    error_message = "the cluster and its dns prefix take the stack name"
  }
  assert {
    condition     = azurerm_kubernetes_cluster.this[0].kubernetes_version == "1.35" && azurerm_kubernetes_cluster.this[0].sku_tier == "Standard"
    error_message = "version and tier defaults"
  }
  assert {
    condition     = azurerm_kubernetes_cluster.this[0].private_cluster_enabled == false && azurerm_kubernetes_cluster.this[0].local_account_disabled == true
    error_message = "public endpoint with local accounts off by default"
  }
  assert {
    condition     = azurerm_kubernetes_cluster.this[0].oidc_issuer_enabled == true && azurerm_kubernetes_cluster.this[0].workload_identity_enabled == true
    error_message = "OIDC issuer and workload identity are always on"
  }
  assert {
    condition     = azurerm_kubernetes_cluster.this[0].azure_active_directory_role_based_access_control[0].azure_rbac_enabled == true && azurerm_kubernetes_cluster.this[0].azure_active_directory_role_based_access_control[0].tenant_id == "00000000-0000-0000-0000-000000000001"
    error_message = "Azure RBAC for Kubernetes must be on in the current tenant"
  }
  assert {
    # automatic_upgrade_channel is computed when unset, so only the OS channel is asserted here; the pass-through run covers the other.
    condition     = azurerm_kubernetes_cluster.this[0].node_os_upgrade_channel == "None"
    error_message = "no node OS image auto-upgrade by default"
  }
  assert {
    condition     = azurerm_kubernetes_cluster.this[0].identity[0].type == "UserAssigned" && length(azurerm_kubernetes_cluster.this[0].identity[0].identity_ids) == 1
    error_message = "the cluster runs as the module's user-assigned identity"
  }
  assert {
    condition     = length(azurerm_kubernetes_cluster.this[0].kubelet_identity) == 1
    error_message = "a separate kubelet identity must be passed"
  }
  assert {
    condition     = length(azurerm_kubernetes_cluster.this[0].key_management_service) == 1 && azurerm_kubernetes_cluster.this[0].key_management_service[0].key_vault_network_access == "Public"
    error_message = "KMS on by default must attach the key management block"
  }
  assert {
    condition     = !azurerm_kubernetes_cluster.this[0].storage_profile[0].disk_driver_enabled && !azurerm_kubernetes_cluster.this[0].storage_profile[0].file_driver_enabled && !azurerm_kubernetes_cluster.this[0].storage_profile[0].snapshot_controller_enabled && !azurerm_kubernetes_cluster.this[0].storage_profile[0].blob_driver_enabled
    error_message = "every AKS-managed CSI driver is off by default"
  }
  assert {
    condition     = length(azurerm_kubernetes_cluster.this[0].api_server_access_profile) == 0
    error_message = "no api server allow list unless cluster_endpoint_authorized_ip_ranges is set"
  }
  assert {
    condition     = azurerm_kubernetes_cluster.this[0].network_profile[0].network_plugin == "none" && azurerm_kubernetes_cluster.this[0].network_profile[0].pod_cidr == "10.244.0.0/16"
    error_message = "BYO CNI with the pod cidr the control plane routes with"
  }
  assert {
    condition     = azurerm_kubernetes_cluster.this[0].network_profile[0].service_cidr == "10.96.0.0/16" && azurerm_kubernetes_cluster.this[0].network_profile[0].dns_service_ip == "10.96.0.10"
    error_message = "service cidr and dns ip"
  }
  assert {
    condition     = azurerm_kubernetes_cluster.this[0].network_profile[0].outbound_type == "userAssignedNATGateway" && azurerm_kubernetes_cluster.this[0].network_profile[0].load_balancer_sku == "standard"
    error_message = "egress through the NAT Gateway on a standard load balancer"
  }
  assert {
    condition     = azurerm_kubernetes_cluster.this[0].default_node_pool[0].name == "system" && azurerm_kubernetes_cluster.this[0].default_node_pool[0].vm_size == "Standard_D4s_v5"
    error_message = "system pool takes system_node_pool.vm_size"
  }
  assert {
    condition     = azurerm_kubernetes_cluster.this[0].default_node_pool[0].auto_scaling_enabled == true && azurerm_kubernetes_cluster.this[0].default_node_pool[0].min_count == 2 && azurerm_kubernetes_cluster.this[0].default_node_pool[0].max_count == 6 && azurerm_kubernetes_cluster.this[0].default_node_pool[0].node_count == 3
    error_message = "autoscaling between min_count and max_count, starting at node_count"
  }
  assert {
    condition     = azurerm_kubernetes_cluster.this[0].default_node_pool[0].only_critical_addons_enabled == true
    error_message = "CriticalAddonsOnly is the one taint the default pool accepts, and it is always set"
  }
  assert {
    condition     = azurerm_kubernetes_cluster.this[0].default_node_pool[0].max_pods == 110 && azurerm_kubernetes_cluster.this[0].default_node_pool[0].os_disk_size_gb == 100 && azurerm_kubernetes_cluster.this[0].default_node_pool[0].os_disk_type == "Managed"
    error_message = "pod density and disk defaults"
  }
  assert {
    condition     = azurerm_kubernetes_cluster.this[0].default_node_pool[0].os_sku == "AzureLinux3" && azurerm_kubernetes_cluster.this[0].default_node_pool[0].fips_enabled == false && tolist(azurerm_kubernetes_cluster.this[0].default_node_pool[0].zones) == tolist(["1", "2", "3"])
    error_message = "Azure Linux 3 across three zones"
  }
  assert {
    condition     = azurerm_kubernetes_cluster.this[0].default_node_pool[0].temporary_name_for_rotation == "systemtmp" && azurerm_kubernetes_cluster.this[0].default_node_pool[0].upgrade_settings[0].max_surge == "10%"
    error_message = "rotation name and surge settings"
  }
  assert {
    condition     = length(azurerm_kubernetes_cluster_node_pool.cni) == 0
    error_message = "no cni pool for cilium"
  }
  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.cluster) == 0
    error_message = "no diagnostic setting without log types"
  }
}

run "kms_disabled" {
  command = plan
  variables {
    kms = { enabled = false }
  }
  assert {
    condition     = length(azurerm_key_vault.kms) == 0 && length(azurerm_key_vault_key.kms) == 0 && length(azurerm_role_assignment.access_admin_key_vault) == 0
    error_message = "kms.enabled = false must create no vault, key or assignment"
  }
  assert {
    condition     = length(azurerm_kubernetes_cluster.this[0].key_management_service) == 0
    error_message = "no key_management_service block without KMS"
  }
}

run "kms_private_network_access_closes_the_vault" {
  command = plan
  variables {
    kms = { key_vault_network_access = "Private" }
  }
  assert {
    condition     = azurerm_key_vault.kms[0].public_network_access_enabled == false
    error_message = "Private must disable public network access on the vault"
  }
}

run "long_names_never_end_the_vault_name_with_a_hyphen" {
  command = plan
  variables {
    name = "abcdefghijklmnopqrst-uvw"
  }
  assert {
    condition     = azurerm_key_vault.kms[0].name == "kv-abcdefghijklmnopqrst" && length(azurerm_key_vault.kms[0].name) <= 24
    error_message = "the generated vault name must be cut at 24 chars and not end with a hyphen"
  }
}

run "kms_key_vault_name_override" {
  command = plan
  variables {
    kms = { key_vault_name = "kv-custom-etcd" }
  }
  assert {
    condition     = azurerm_key_vault.kms[0].name == "kv-custom-etcd"
    error_message = "kms.key_vault_name must win over the generated name"
  }
}

run "private_cluster" {
  command = plan
  variables {
    cluster_endpoint_public_access = false
  }
  assert {
    condition     = azurerm_kubernetes_cluster.this[0].private_cluster_enabled == true
    error_message = "public access off must make a private cluster"
  }
}

run "authorized_ip_ranges_render_the_access_profile" {
  command = plan
  variables {
    cluster_endpoint_authorized_ip_ranges = ["203.0.113.0/24", "198.51.100.7/32"]
  }
  assert {
    condition     = length(azurerm_kubernetes_cluster.this[0].api_server_access_profile) == 1 && length(azurerm_kubernetes_cluster.this[0].api_server_access_profile[0].authorized_ip_ranges) == 2
    error_message = "the allow list must reach the api server access profile"
  }
}

run "fips_and_upgrade_channels_pass_through" {
  command = plan
  variables {
    system_node_pool          = { vm_size = "Standard_D8s_v5", fips_enabled = true, zones = [], os_sku = "AzureLinux" }
    automatic_upgrade_channel = "patch"
    node_os_upgrade_channel   = "NodeImage"
  }
  assert {
    condition     = azurerm_kubernetes_cluster.this[0].default_node_pool[0].fips_enabled == true && length(coalesce(azurerm_kubernetes_cluster.this[0].default_node_pool[0].zones, [])) == 0 && azurerm_kubernetes_cluster.this[0].default_node_pool[0].os_sku == "AzureLinux"
    error_message = "FIPS, no zones and os_sku must pass through"
  }
  assert {
    condition     = azurerm_kubernetes_cluster.this[0].automatic_upgrade_channel == "patch" && azurerm_kubernetes_cluster.this[0].node_os_upgrade_channel == "NodeImage"
    error_message = "upgrade channels must pass through"
  }
}

run "kube_ovn_creates_the_cni_pool" {
  command = plan
  variables {
    cni           = "kube-ovn"
    cni_node_pool = { kubernetes_version = "1.34", zones = ["1"] }
  }
  assert {
    condition     = length(azurerm_kubernetes_cluster_node_pool.cni) == 1 && azurerm_kubernetes_cluster_node_pool.cni[0].name == "cni" && azurerm_kubernetes_cluster_node_pool.cni[0].mode == "User"
    error_message = "a User-mode pool named cni"
  }
  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.cni[0].node_count == 1 && azurerm_kubernetes_cluster_node_pool.cni[0].auto_scaling_enabled == false
    error_message = "fixed size, no autoscaling"
  }
  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.cni[0].orchestrator_version == "1.34" && azurerm_kubernetes_cluster_node_pool.cni[0].vm_size == "Standard_D4s_v5"
    error_message = "pinned version, vm_size inherited from system_node_pool"
  }
  assert {
    condition     = tolist(azurerm_kubernetes_cluster_node_pool.cni[0].node_taints) == tolist(["kube-ovn.io/control-plane=true:NoSchedule"]) && azurerm_kubernetes_cluster_node_pool.cni[0].node_labels == tomap({ "kube-ovn/role" = "master" })
    error_message = "taint string and master label from the profile"
  }
  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.cni[0].temporary_name_for_rotation == "cnitmp" && azurerm_kubernetes_cluster_node_pool.cni[0].upgrade_settings[0].max_surge == "10%"
    error_message = "rotation name, so a vm_size change plans; upgrade_settings declared, so the AKS default never shows as drift"
  }
  assert {
    condition     = tolist(azurerm_kubernetes_cluster_node_pool.cni[0].zones) == tolist(["1"]) && azurerm_kubernetes_cluster_node_pool.cni[0].os_sku == "AzureLinux3" && azurerm_kubernetes_cluster_node_pool.cni[0].max_pods == 110
    error_message = "zone pin and OS settings shared with the system pool"
  }
}

run "cni_pool_vm_size_override" {
  command = plan
  variables {
    cni           = "kube-ovn"
    cni_node_pool = { kubernetes_version = "1.34", vm_size = "Standard_D8s_v5", node_count = 3 }
  }
  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.cni[0].vm_size == "Standard_D8s_v5" && azurerm_kubernetes_cluster_node_pool.cni[0].node_count == 3
    error_message = "cni_node_pool.vm_size and node_count must win"
  }
}

run "diagnostics_follow_log_types" {
  command = plan
  variables {
    cluster_enabled_log_types          = ["kube-apiserver", "kube-audit-admin"]
    cluster_log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-ops/providers/Microsoft.OperationalInsights/workspaces/law-ops"
  }
  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.cluster) == 1 && length(azurerm_monitor_diagnostic_setting.cluster[0].enabled_log) == 2
    error_message = "one diagnostic setting with one enabled_log per category"
  }
}

run "create_false_keeps_only_the_network" {
  command = plan
  variables {
    create_cluster = false
  }
  assert {
    condition     = length(azurerm_kubernetes_cluster.this) == 0 && length(azurerm_user_assigned_identity.cluster) == 0 && length(azurerm_user_assigned_identity.kubelet) == 0 && length(azurerm_key_vault.kms) == 0
    error_message = "create_cluster = false must skip the cluster, its identities and KMS"
  }
  assert {
    condition     = length(azurerm_virtual_network.this) == 1 && length(azurerm_nat_gateway.this) == 1
    error_message = "create_cluster = false does not gate the network"
  }
}

run "storage_drivers_can_be_enabled" {
  command = plan
  variables {
    storage_drivers = { disk = true, file = true, snapshot_controller = true }
  }
  assert {
    condition     = azurerm_kubernetes_cluster.this[0].storage_profile[0].disk_driver_enabled && azurerm_kubernetes_cluster.this[0].storage_profile[0].file_driver_enabled && azurerm_kubernetes_cluster.this[0].storage_profile[0].snapshot_controller_enabled
    error_message = "storage_drivers must turn the AKS-managed drivers on"
  }
  assert {
    condition     = length(azurerm_role_assignment.kubelet_node_resource_group) == 0
    error_message = "with the managed disk driver on, the kubelet identity needs no grant on the node resource group"
  }
}

run "self_managed_disk_csi_gets_kubelet_contributor" {
  command = plan
  assert {
    condition     = length(azurerm_role_assignment.kubelet_node_resource_group) == 1 && azurerm_role_assignment.kubelet_node_resource_group[0].role_definition_name == "Contributor"
    error_message = "with the managed disk driver off, the kubelet identity gets Contributor on the node resource group for a self-managed CSI driver"
  }
}
