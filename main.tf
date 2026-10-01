data "azurerm_client_config" "current" {}

locals {
  resource_group_name_wanted = coalesce(var.resource_group_name, "rg-${var.name}")
  # Read through the resource so everything that uses the name waits for the group to exist.
  resource_group_name = var.create_resource_group ? azurerm_resource_group.this[0].name : local.resource_group_name_wanted

  kubelogin_environment = {
    public       = "AzurePublicCloud"
    usgovernment = "AzureUSGovernmentCloud"
  }[var.azure_cloud]

  # AKS Microsoft Entra server application id from Microsoft's kubelogin docs.
  aks_entra_server_id = "6dae42f8-4368-4678-94ff-3960e28e3630"

  kube_exec = {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "kubelogin"
    args        = ["get-token", "--login", var.kube_exec_login_mode, "--server-id", local.aks_entra_server_id, "--environment", local.kubelogin_environment]
    env         = {}
  }
}

resource "azurerm_resource_group" "this" {
  count    = var.create_resource_group ? 1 : 0
  name     = local.resource_group_name_wanted
  location = var.location
  tags     = var.tags
}
