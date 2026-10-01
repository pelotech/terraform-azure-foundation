# Karpenter: self-hosted identity with the provider's documented role set, or AKS node auto provisioning.

mock_provider "azurerm" {
  source = "./tests/mocks"
}

run "self_hosted_by_default" {
  command = plan
  assert {
    condition     = length(azurerm_user_assigned_identity.karpenter) == 1 && azurerm_user_assigned_identity.karpenter[0].name == "id-platformdev-karpenter"
    error_message = "the karpenter identity exists by default"
  }
  assert {
    condition     = azurerm_federated_identity_credential.karpenter[0].subject == "system:serviceaccount:karpenter:karpenter"
    error_message = "federated to the karpenter/karpenter service account the GitOps layer deploys"
  }
  assert {
    condition     = length(azurerm_role_assignment.karpenter) == 5 && azurerm_role_assignment.karpenter["node_resource_group_vm"].role_definition_name == "Virtual Machine Contributor" && azurerm_role_assignment.karpenter["node_resource_group_network"].role_definition_name == "Network Contributor" && azurerm_role_assignment.karpenter["node_resource_group_identity"].role_definition_name == "Managed Identity Operator"
    error_message = "the three roles karpenter-provider-azure's setup grants, on the node resource group"
  }
  assert {
    condition     = azurerm_role_assignment.karpenter["node_subnet"].role_definition_name == "Network Contributor" && azurerm_role_assignment.karpenter["kubelet_identity"].role_definition_name == "Managed Identity Operator"
    error_message = "the node subnet and the kubelet identity live outside the node resource group and need their own grants"
  }
  assert {
    condition     = azurerm_kubernetes_cluster.this[0].node_provisioning_profile[0].mode == "Manual"
    error_message = "self-hosted leaves AKS node provisioning manual"
  }
  assert {
    condition     = output.karpenter_mode_resolved == "self-hosted"
    error_message = "introspection reports self-hosted"
  }
}

run "nap_mode_uses_aks_node_auto_provisioning" {
  command = plan
  variables {
    karpenter = { mode = "node-auto-provisioning" }
  }
  assert {
    condition     = length(azurerm_user_assigned_identity.karpenter) == 0 && length(azurerm_role_assignment.karpenter) == 0
    error_message = "NAP is Microsoft-managed; no identity of ours"
  }
  assert {
    condition     = azurerm_kubernetes_cluster.this[0].node_provisioning_profile[0].mode == "Auto"
    error_message = "NAP sets node provisioning to Auto"
  }
  assert {
    condition     = output.karpenter_client_id == null && output.karpenter_mode_resolved == "node-auto-provisioning"
    error_message = "no client id under NAP"
  }
}

run "disabled_creates_nothing_and_stays_manual" {
  command = plan
  variables {
    karpenter = { enabled = false }
  }
  assert {
    condition     = length(azurerm_user_assigned_identity.karpenter) == 0 && azurerm_kubernetes_cluster.this[0].node_provisioning_profile[0].mode == "Manual" && output.karpenter_mode_resolved == "disabled" && length(azurerm_role_assignment.karpenter) == 0
    error_message = "disabled means no identity and manual provisioning"
  }
}

run "create_false_creates_no_karpenter_identity" {
  command = plan
  variables {
    create_cluster = false
  }
  assert {
    condition     = length(azurerm_user_assigned_identity.karpenter) == 0 && length(azurerm_federated_identity_credential.karpenter) == 0
    error_message = "create_cluster gates the karpenter identity"
  }
}
