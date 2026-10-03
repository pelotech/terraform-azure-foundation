locals {
  # Roles the cluster identity needs before AKS can create the cluster.
  cluster_identity_grants = merge(
    {
      node_subnet      = { scope = local.node_subnet_id, role = "Network Contributor" }
      kubelet_identity = { scope = one(azurerm_user_assigned_identity.kubelet[*].id), role = "Managed Identity Operator" }
    },
    local.kms_enabled ? {
      key_vault = { scope = one(azurerm_key_vault.kms[*].id), role = "Key Vault Crypto User" }
    } : {},
  )
}

resource "azurerm_user_assigned_identity" "cluster" {
  count               = var.create_cluster ? 1 : 0
  name                = "id-${var.name}-cluster"
  location            = var.location
  resource_group_name = local.resource_group_name
  tags                = var.tags
}

resource "azurerm_user_assigned_identity" "kubelet" {
  count               = var.create_cluster ? 1 : 0
  name                = "id-${var.name}-kubelet"
  location            = var.location
  resource_group_name = local.resource_group_name
  tags                = var.tags
}

resource "azurerm_role_assignment" "cluster_identity" {
  for_each                         = var.create_cluster ? local.cluster_identity_grants : {}
  scope                            = each.value.scope
  role_definition_name             = each.value.role
  principal_id                     = azurerm_user_assigned_identity.cluster[0].principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azurerm_kubernetes_cluster" "this" {
  count               = var.create_cluster ? 1 : 0
  name                = var.name
  location            = var.location
  resource_group_name = local.resource_group_name
  dns_prefix          = var.name
  kubernetes_version  = var.cluster_version
  sku_tier            = var.sku_tier
  tags                = var.tags

  private_cluster_enabled   = !var.cluster_endpoint_public_access
  local_account_disabled    = var.local_account_disabled
  oidc_issuer_enabled       = true
  workload_identity_enabled = true
  # azurerm treats an absent channel as none; "none" is not an accepted literal.
  automatic_upgrade_channel = var.automatic_upgrade_channel == "none" ? null : var.automatic_upgrade_channel
  node_os_upgrade_channel   = var.node_os_upgrade_channel

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.cluster[0].id]
  }

  kubelet_identity {
    client_id                 = azurerm_user_assigned_identity.kubelet[0].client_id
    object_id                 = azurerm_user_assigned_identity.kubelet[0].principal_id
    user_assigned_identity_id = azurerm_user_assigned_identity.kubelet[0].id
  }

  default_node_pool {
    name                         = "system"
    vm_size                      = var.system_node_pool.vm_size
    auto_scaling_enabled         = true
    min_count                    = var.system_node_pool.min_count
    max_count                    = var.system_node_pool.max_count
    node_count                   = var.system_node_pool.node_count
    only_critical_addons_enabled = true
    node_labels                  = var.system_node_pool.labels
    max_pods                     = var.system_node_pool.max_pods
    os_disk_size_gb              = var.system_node_pool.os_disk_size_gb
    os_disk_type                 = "Managed"
    os_sku                       = var.system_node_pool.os_sku
    fips_enabled                 = var.system_node_pool.fips_enabled
    zones                        = var.system_node_pool.zones
    vnet_subnet_id               = local.node_subnet_id
    temporary_name_for_rotation  = "systemtmp"
    tags                         = var.tags

    upgrade_settings {
      max_surge = "10%"
    }
  }

  network_profile {
    network_plugin      = local.network_plugin
    network_plugin_mode = local.network_plugin_mode
    network_data_plane  = local.network_data_plane
    pod_cidr            = local.pod_cidr
    service_cidr        = var.service_cidr
    dns_service_ip      = local.dns_service_ip
    outbound_type       = local.outbound_type
    load_balancer_sku   = "standard"
  }

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
    tenant_id          = data.azurerm_client_config.current.tenant_id
  }

  dynamic "api_server_access_profile" {
    for_each = length(var.cluster_endpoint_authorized_ip_ranges) > 0 ? [1] : []
    content {
      authorized_ip_ranges = var.cluster_endpoint_authorized_ip_ranges
    }
  }

  dynamic "key_management_service" {
    for_each = local.kms_enabled ? [1] : []
    content {
      key_vault_key_id         = azurerm_key_vault_key.kms[0].id
      key_vault_network_access = var.kms.key_vault_network_access
    }
  }

  storage_profile {
    disk_driver_enabled         = var.storage_drivers.disk
    file_driver_enabled         = var.storage_drivers.file
    snapshot_controller_enabled = var.storage_drivers.snapshot_controller
    blob_driver_enabled         = var.blob_csi.enabled
  }

  node_provisioning_profile {
    mode = local.karpenter_mode == "node-auto-provisioning" ? "Auto" : "Manual"
  }

  lifecycle {
    # node_count: the autoscaler owns it. pod_cidrs: AKS never returns it with bring-your-own CNI (azurerm #30985).
    ignore_changes = [default_node_pool[0].node_count, network_profile[0].pod_cidrs]
  }

  depends_on = [
    azurerm_role_assignment.cluster_identity,
    azurerm_subnet_nat_gateway_association.nodes,
    azurerm_nat_gateway_public_ip_association.nat,
  ]
}

resource "azurerm_kubernetes_cluster_node_pool" "cni" {
  count                 = var.create_cluster && local.cni_node_pool_enabled ? 1 : 0
  name                  = "cni"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this[0].id
  mode                  = "User"
  vm_size               = coalesce(var.cni_node_pool.vm_size, var.system_node_pool.vm_size)
  node_count            = var.cni_node_pool.node_count
  auto_scaling_enabled  = false
  orchestrator_version  = coalesce(var.cni_node_pool.kubernetes_version, var.cluster_version)
  node_taints           = local.cni_node_pool_taint_strings
  node_labels           = local.cni_node_pool_labels
  zones                 = var.cni_node_pool.zones
  vnet_subnet_id        = local.node_subnet_id
  max_pods              = var.system_node_pool.max_pods
  os_disk_size_gb       = var.system_node_pool.os_disk_size_gb
  os_disk_type          = "Managed"
  os_sku                = var.system_node_pool.os_sku
  fips_enabled          = var.system_node_pool.fips_enabled
  tags                  = var.tags
}

# A self-managed disk CSI driver authenticates with the kubelet identity from the nodes' azure.json
# and needs Contributor where the disks live. AKS grants this itself only for its managed driver.
resource "azurerm_role_assignment" "kubelet_node_resource_group" {
  count                            = var.create_cluster && !var.storage_drivers.disk ? 1 : 0
  scope                            = azurerm_kubernetes_cluster.this[0].node_resource_group_id
  role_definition_name             = "Contributor"
  principal_id                     = azurerm_user_assigned_identity.kubelet[0].principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azurerm_monitor_diagnostic_setting" "cluster" {
  count                      = var.create_cluster && length(var.cluster_enabled_log_types) > 0 ? 1 : 0
  name                       = "${var.name}-control-plane"
  target_resource_id         = azurerm_kubernetes_cluster.this[0].id
  log_analytics_workspace_id = var.cluster_log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = toset(var.cluster_enabled_log_types)
    content {
      category = enabled_log.value
    }
  }
}
