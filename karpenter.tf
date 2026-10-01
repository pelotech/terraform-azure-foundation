locals {
  karpenter_mode         = var.karpenter.enabled ? var.karpenter.mode : "disabled"
  karpenter_self_hosted  = var.create_cluster && local.karpenter_mode == "self-hosted"
  node_resource_group_id = one(azurerm_kubernetes_cluster.this[*].node_resource_group_id)

  # Roles the Karpenter controller needs to create and delete nodes.
  karpenter_grants = {
    node_resource_group_vm       = { scope = local.node_resource_group_id, role = "Virtual Machine Contributor" }
    node_resource_group_network  = { scope = local.node_resource_group_id, role = "Network Contributor" }
    node_resource_group_identity = { scope = local.node_resource_group_id, role = "Managed Identity Operator" }
    node_subnet                  = { scope = local.node_subnet_id, role = "Network Contributor" }
    kubelet_identity             = { scope = one(azurerm_user_assigned_identity.kubelet[*].id), role = "Managed Identity Operator" }
  }
}

resource "azurerm_user_assigned_identity" "karpenter" {
  count               = local.karpenter_self_hosted ? 1 : 0
  name                = "id-${var.name}-karpenter"
  location            = var.location
  resource_group_name = local.resource_group_name
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "karpenter" {
  count                     = local.karpenter_self_hosted ? 1 : 0
  name                      = "${var.name}-karpenter"
  user_assigned_identity_id = azurerm_user_assigned_identity.karpenter[0].id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = azurerm_kubernetes_cluster.this[0].oidc_issuer_url
  subject                   = "system:serviceaccount:karpenter:karpenter"
}

resource "azurerm_role_assignment" "karpenter" {
  for_each                         = local.karpenter_self_hosted ? local.karpenter_grants : {}
  scope                            = each.value.scope
  role_definition_name             = each.value.role
  principal_id                     = azurerm_user_assigned_identity.karpenter[0].principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}
