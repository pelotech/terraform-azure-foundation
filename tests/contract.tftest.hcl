# The stack-to-CNI contract: every output cni-bootstrap and the helm provider consume.

mock_provider "azurerm" {
  source = "./tests/mocks"
}

run "kube_exec_targets_azure_government" {
  command = plan
  variables {
    azure_cloud = "usgovernment"
  }
  assert {
    condition     = output.cloud == "azure"
    error_message = "cloud must be azure"
  }
  assert {
    condition     = output.kube_exec.command == "kubelogin" && output.kube_exec.api_version == "client.authentication.k8s.io/v1beta1"
    error_message = "kube_exec must run kubelogin with the v1beta1 exec api"
  }
  assert {
    condition     = contains(output.kube_exec.args, "AzureUSGovernmentCloud") && contains(output.kube_exec.args, "6dae42f8-4368-4678-94ff-3960e28e3630")
    error_message = "kube_exec must pass the Gov environment and the AKS Entra server id"
  }
  assert {
    condition     = output.kube_exec.args[2] == "azurecli"
    error_message = "kube_exec login mode defaults to azurecli"
  }
}

run "kube_exec_targets_public_cloud_with_spn_login" {
  command = plan
  variables {
    azure_cloud          = "public"
    kube_exec_login_mode = "spn"
  }
  assert {
    condition     = contains(output.kube_exec.args, "AzurePublicCloud") && output.kube_exec.args[2] == "spn"
    error_message = "kube_exec must map azure_cloud=public to AzurePublicCloud and honour kube_exec_login_mode"
  }
}

run "resource_group_name_defaults_from_name" {
  command = plan
  assert {
    condition     = output.resource_group_name == "rg-platformdev" && azurerm_resource_group.this[0].location == "usgovvirginia"
    error_message = "resource group must default to rg-<name> in var.location"
  }
  assert {
    condition     = output.region == "usgovvirginia"
    error_message = "region is an alias of location for consumers that expect an output named region"
  }
}

run "existing_resource_group_is_not_created" {
  command = plan
  variables {
    create_resource_group = false
    resource_group_name   = "rg-shared"
  }
  assert {
    condition     = length(azurerm_resource_group.this) == 0 && output.resource_group_name == "rg-shared"
    error_message = "create_resource_group = false must reuse the named group"
  }
}

run "every_contract_output_is_populated" {
  command = apply

  override_resource {
    target = azurerm_kubernetes_cluster.this[0]
    values = {
      id   = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-platformdev/providers/Microsoft.ContainerService/managedClusters/platformdev"
      fqdn = "platformdev-abc123.hcp.usgovvirginia.cx.aks.containerservice.azure.us"
      kube_config = [{
        host                   = "https://platformdev-abc123.hcp.usgovvirginia.cx.aks.containerservice.azure.us:443"
        cluster_ca_certificate = "Y2VydA=="
        client_certificate     = ""
        client_key             = ""
        username               = ""
        password               = ""
      }]
      oidc_issuer_url        = "https://usgovvirginia.oic.prod-aks.azure.us/00000000-0000-0000-0000-000000000001/11111111-1111-1111-1111-111111111111/"
      node_resource_group    = "MC_platformdev"
      node_resource_group_id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/MC_platformdev"
    }
  }

  override_resource {
    target = azurerm_key_vault.kms[0]
    values = { id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-platformdev/providers/Microsoft.KeyVault/vaults/kvplatformdev" }
  }

  override_resource {
    target = azurerm_storage_account.blob_csi[0]
    values = { id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-platformdev/providers/Microsoft.Storage/storageAccounts/platformdevblobcsi" }
  }

  override_resource {
    target = azurerm_user_assigned_identity.kubelet[0]
    values = { id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-platformdev/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-platformdev-kubelet" }
  }

  override_resource {
    target = azurerm_subnet.nodes[0]
    values = { id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-platformdev/providers/Microsoft.Network/virtualNetworks/vnet-platformdev/subnets/nodes" }
  }

  override_resource {
    target = azurerm_nat_gateway.this[0]
    values = { id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-platformdev/providers/Microsoft.Network/natGateways/natgw-platformdev" }
  }

  override_resource {
    target = azurerm_key_vault_key.kms[0]
    values = { id = "https://kvplatformdev.vault.usgovcloudapi.net/keys/etcd/0123456789abcdef0123456789abcdef" }
  }

  override_resource {
    target = azurerm_user_assigned_identity.cluster[0]
    values = { id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-platformdev/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-platformdev-cluster" }
  }

  override_resource {
    target = azurerm_public_ip.nat[0]
    values = { id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-platformdev/providers/Microsoft.Network/publicIPAddresses/pip-platformdev-nat" }
  }

  override_resource {
    target = azurerm_user_assigned_identity.karpenter[0]
    values = { id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-platformdev/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-platformdev-karpenter" }
  }

  override_resource {
    target = azurerm_user_assigned_identity.workload["external_dns"]
    values = { id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-platformdev/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-platformdev-external-dns" }
  }

  override_resource {
    target = azurerm_user_assigned_identity.workload["cert_manager"]
    values = { id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-platformdev/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-platformdev-cert-manager" }
  }

  variables {
    azure_cloud   = "usgovernment"
    cni           = "kube-ovn"
    cni_node_pool = { kubernetes_version = "1.34" }
  }

  assert {
    condition     = output.cluster_name == "platformdev"
    error_message = "cluster_name"
  }
  assert {
    condition     = output.cluster_endpoint == "https://platformdev-abc123.hcp.usgovvirginia.cx.aks.containerservice.azure.us:443"
    error_message = "cluster_endpoint is the kube_config host"
  }
  assert {
    condition     = output.cluster_ca_certificate == "Y2VydA=="
    error_message = "cluster_ca_certificate is the kube_config CA, base64 as AKS returns it"
  }
  assert {
    condition     = output.cluster_api_host == "platformdev-abc123.hcp.usgovvirginia.cx.aks.containerservice.azure.us"
    error_message = "cluster_api_host is the cluster fqdn without scheme or port, for Cilium k8sServiceHost"
  }
  assert {
    condition     = output.cloud == "azure" && output.cluster_service_cidr == "10.96.0.0/16" && output.cluster_pod_cidr == "10.244.0.0/16"
    error_message = "cloud and cidrs"
  }
  assert {
    condition     = output.cni_node_size == 1 && output.cni_node_selector == "kube-ovn/role=master"
    error_message = "cni node contract for kube-ovn"
  }
  assert {
    condition     = output.kube_exec.args == ["get-token", "--login", "azurecli", "--server-id", "6dae42f8-4368-4678-94ff-3960e28e3630", "--environment", "AzureUSGovernmentCloud"]
    error_message = "kube_exec args must be exactly the kubelogin invocation for Azure Government"
  }
  assert {
    condition     = length(output.kube_exec.env) == 0
    error_message = "kube_exec env is empty by default"
  }
  assert {
    condition     = output.oidc_issuer_url != null && output.node_resource_group_name == "MC_platformdev"
    error_message = "issuer and node resource group pass through"
  }
  assert {
    condition     = output.external_dns_client_id != null && output.cert_manager_client_id != null && output.karpenter_client_id != null
    error_message = "the GitOps layer's client ids are populated by default"
  }
}
