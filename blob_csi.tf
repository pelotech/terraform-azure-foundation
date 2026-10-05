locals {
  create_blob_storage_account = var.blob_csi.enabled && var.blob_csi.create_storage_account
  blob_csi_node_subnet_only   = local.create_blob_storage_account && var.blob_csi.network_access == "NodeSubnet"
}

resource "azurerm_storage_account" "blob_csi" {
  count                           = local.create_blob_storage_account ? 1 : 0
  name                            = coalesce(var.blob_csi.storage_account_name, substr(lower(replace("${try(var.tags.Owner, "")}${var.name}csi", "/[^A-Za-z0-9]/", "")), 0, 24))
  resource_group_name             = local.resource_group_name
  location                        = var.location
  account_kind                    = "StorageV2"
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = var.blob_csi.shared_access_key_enabled
  tags                            = var.tags

  # The block is always set: the provider keeps the account's current rules when it is absent, so Public would never reopen an account.
  network_rules {
    default_action             = local.blob_csi_node_subnet_only ? "Deny" : "Allow"
    bypass                     = ["AzureServices"]
    virtual_network_subnet_ids = local.blob_csi_node_subnet_only ? concat([local.node_subnet_id], var.blob_csi.extra_subnet_ids) : []
  }
}

resource "azurerm_storage_container" "blob_csi" {
  for_each              = local.create_blob_storage_account ? toset(var.blob_csi.containers) : toset([])
  name                  = each.value
  storage_account_id    = azurerm_storage_account.blob_csi[0].id
  container_access_type = "private"
}

resource "azurerm_role_assignment" "kubelet_blob_storage_account" {
  count                            = var.create_cluster && local.create_blob_storage_account ? 1 : 0
  scope                            = azurerm_storage_account.blob_csi[0].id
  role_definition_name             = "Storage Blob Data Contributor"
  principal_id                     = azurerm_user_assigned_identity.kubelet[0].principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}
