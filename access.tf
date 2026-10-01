locals {
  access_roles = {
    admin  = { object_ids = var.access.admin_object_ids, cluster_role = "Azure Kubernetes Service RBAC Cluster Admin" }
    reader = { object_ids = var.access.reader_object_ids, cluster_role = "Azure Kubernetes Service RBAC Reader" }
  }
  # Each principal gets its RBAC role plus the Cluster User role it needs to fetch credentials.
  # Keys carry the object id, so removing one principal never touches the others.
  access_grants = var.create_cluster ? merge([
    for group, cfg in local.access_roles : merge([
      for id in cfg.object_ids : {
        "${group}_${id}"      = { principal_id = id, role = cfg.cluster_role }
        "${group}_${id}_user" = { principal_id = id, role = "Azure Kubernetes Service Cluster User Role" }
      }
    ]...)
  ]...) : {}
}

resource "azurerm_role_assignment" "access" {
  for_each             = local.access_grants
  scope                = azurerm_kubernetes_cluster.this[0].id
  role_definition_name = each.value.role
  principal_id         = each.value.principal_id
}

resource "azurerm_role_assignment" "access_admin_key_vault" {
  for_each             = local.kms_enabled ? toset(var.access.admin_object_ids) : toset([])
  scope                = azurerm_key_vault.kms[0].id
  role_definition_name = "Key Vault Crypto Officer"
  principal_id         = each.value
}
