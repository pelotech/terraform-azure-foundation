locals {
  kms_enabled = var.create_cluster && var.kms.enabled
}

resource "azurerm_key_vault" "kms" {
  count                         = local.kms_enabled ? 1 : 0
  name                          = coalesce(var.kms.key_vault_name, trimsuffix(substr("kv-${var.name}", 0, 24), "-"))
  location                      = var.location
  resource_group_name           = local.resource_group_name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  purge_protection_enabled      = true
  soft_delete_retention_days    = 90
  public_network_access_enabled = var.kms.key_vault_network_access == "Public"
  tags                          = var.tags
}

resource "azurerm_key_vault_key" "kms" {
  count        = local.kms_enabled ? 1 : 0
  name         = "${var.name}-etcd"
  key_vault_id = azurerm_key_vault.kms[0].id
  key_type     = "RSA"
  key_size     = 2048
  key_opts     = ["decrypt", "encrypt", "sign", "unwrapKey", "verify", "wrapKey"]

  # Creating the key under RBAC needs Crypto Officer, so the applying principal must be in access.admin_object_ids.
  depends_on = [azurerm_role_assignment.access_admin_key_vault]
}
