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

# The identity running terraform needs this to create the key under RBAC authorization.
resource "azurerm_role_assignment" "deployer_key_vault" {
  count                = local.kms_enabled ? 1 : 0
  scope                = azurerm_key_vault.kms[0].id
  role_definition_name = "Key Vault Crypto Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_key_vault_key" "kms" {
  count        = local.kms_enabled ? 1 : 0
  name         = "${var.name}-etcd"
  key_vault_id = azurerm_key_vault.kms[0].id
  key_type     = "RSA"
  key_size     = 2048
  key_opts     = ["decrypt", "encrypt", "sign", "unwrapKey", "verify", "wrapKey"]

  depends_on = [azurerm_role_assignment.deployer_key_vault]
}
