# Inputs for the helm provider and the cni-bootstrap module.
output "cloud" {
  description = "Cloud this stack runs on. Pass it to cni-bootstrap cloud."
  value       = "azure"
}

output "kube_exec" {
  description = "kubelogin exec block for the helm provider and cni-bootstrap."
  value       = local.kube_exec
}

output "cluster_name" {
  description = "Name of the AKS cluster, null when create_cluster = false."
  value       = one(azurerm_kubernetes_cluster.this[*].name)
}

# The API host and CA certificate are public; only the client key inside kube_config is secret.
output "cluster_endpoint" {
  description = "API server URL for the helm provider and cni-bootstrap."
  value       = try(nonsensitive(azurerm_kubernetes_cluster.this[0].kube_config[0].host), null)
}

output "cluster_ca_certificate" {
  description = "Base64 encoded cluster CA certificate for the helm provider and cni-bootstrap."
  value       = try(nonsensitive(azurerm_kubernetes_cluster.this[0].kube_config[0].cluster_ca_certificate), null)
}

output "cluster_api_host" {
  description = "API server host without scheme or port, for Cilium k8sServiceHost. Use port 443."
  value       = one(var.cluster_endpoint_public_access ? azurerm_kubernetes_cluster.this[*].fqdn : azurerm_kubernetes_cluster.this[*].private_fqdn)
}

output "cluster_service_cidr" {
  description = "Kubernetes service CIDR. Pass it to cni-bootstrap service_cidr."
  value       = var.service_cidr
}

output "cluster_pod_cidr" {
  description = "Pod CIDR the AKS control plane routes to, null for azure-cni in node-subnet mode. Pass it to cni-bootstrap pod_cidr."
  value       = local.pod_cidr
}

output "cni_node_size" {
  description = "Node count of the CNI node pool, 0 when the pool is not created. Pass it to cni-bootstrap wait_for_nodes_count."
  value       = local.cni_node_pool_enabled ? var.cni_node_pool.node_count : 0
}

output "cni_node_selector" {
  description = "Label selector of the CNI node pool, empty when the profile has none. Pass it to cni-bootstrap wait_for_nodes_selector."
  value       = local.cni_node_pool_selector
}

# Subscription and tenant, for charts that need them next to the identities: external-dns, cert-manager, Karpenter.
output "subscription_id" {
  description = "Azure subscription the stack runs in."
  value       = data.azurerm_client_config.current.subscription_id
}

output "tenant_id" {
  description = "Entra tenant of the subscription."
  value       = data.azurerm_client_config.current.tenant_id
}

# Resource group, network and cluster.
output "resource_group_name" {
  description = "Resource group holding the module's resources."
  value       = local.resource_group_name
}

output "location" {
  description = "Azure region of the stack."
  value       = var.location
}

output "region" {
  description = "Same value as location, for consumers that expect an output named region."
  value       = var.location
}

output "vnet_id" {
  description = "ID of the VNet, created or taken from existing_vnet."
  value       = local.create_vnet ? azurerm_virtual_network.this[0].id : var.existing_vnet.vnet_id
}

output "node_subnet_id" {
  description = "ID of the subnet every node pool and private endpoint uses."
  value       = local.node_subnet_id
}

output "database_subnet_id" {
  description = "ID of the database subnet, null unless vnet.database_subnet_cidr is set."
  value       = one(azurerm_subnet.database[*].id)
}

output "nat_gateway_public_ips" {
  description = "Public IP addresses of the NAT Gateway, for allow lists. Empty when the gateway is not created."
  value       = azurerm_public_ip.nat[*].ip_address
}

output "outbound_type_resolved" {
  description = "AKS outbound_type after resolving nat_gateway and existing_vnet."
  value       = local.outbound_type
}

output "cluster_id" {
  description = "Resource ID of the AKS cluster, the scope for extra role assignments."
  value       = one(azurerm_kubernetes_cluster.this[*].id)
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL of the cluster, for federated identity credentials you create yourself."
  value       = one(azurerm_kubernetes_cluster.this[*].oidc_issuer_url)
}

output "node_resource_group_name" {
  description = "Name of the resource group AKS creates for the nodes."
  value       = one(azurerm_kubernetes_cluster.this[*].node_resource_group)
}

output "cluster_identity_principal_id" {
  description = "Principal ID of the cluster identity."
  value       = one(azurerm_user_assigned_identity.cluster[*].principal_id)
}

output "kubelet_identity_client_id" {
  description = "Client ID of the kubelet identity, used for image pulls, the CSI drivers and Karpenter nodes."
  value       = one(azurerm_user_assigned_identity.kubelet[*].client_id)
}

output "kubelet_identity_id" {
  description = "Resource ID of the kubelet identity."
  value       = one(azurerm_user_assigned_identity.kubelet[*].id)
}

# CNI profile after resolving cni and azure_cni.
output "cni_node_pool_enabled" {
  description = "Whether the CNI node pool is created."
  value       = local.cni_node_pool_enabled
}

output "cni_node_taints_resolved" {
  description = "Taints of the CNI node pool as key, value and effect objects. Set even when the pool is not created."
  value       = local.cni_node_pool_taints
}

output "cni_node_labels_resolved" {
  description = "Labels of the CNI node pool. Set even when the pool is not created."
  value       = local.cni_node_pool_labels
}

output "network_plugin_resolved" {
  description = "AKS network_plugin: none for cilium and kube-ovn, azure for azure-cni."
  value       = local.network_plugin
}

output "network_plugin_mode_resolved" {
  description = "AKS network_plugin_mode: overlay, or null."
  value       = local.network_plugin_mode
}

output "network_data_plane_resolved" {
  description = "AKS network_data_plane: azure, cilium, or null for bring-your-own CNI."
  value       = local.network_data_plane
}

output "dns_service_ip_resolved" {
  description = "Cluster DNS service IP after resolving dns_service_ip and service_cidr."
  value       = local.dns_service_ip
}

# KMS.
output "kms_key_vault_id" {
  description = "ID of the Key Vault holding the etcd encryption key, null when kms is disabled."
  value       = one(azurerm_key_vault.kms[*].id)
}

output "kms_key_id" {
  description = "Versioned Key Vault key ID used for etcd encryption, null when kms is disabled."
  value       = one(azurerm_key_vault_key.kms[*].id)
}

# Workload identities. The GitOps layer sets each client_id on the azure.workload.identity/client-id annotation.
output "external_dns_client_id" {
  description = "Client ID of the external-dns workload identity, null when disabled."
  value       = try(azurerm_user_assigned_identity.workload["external_dns"].client_id, null)
}

output "external_dns_principal_id" {
  description = "Principal ID of the external-dns workload identity, for role assignments you create yourself."
  value       = try(azurerm_user_assigned_identity.workload["external_dns"].principal_id, null)
}

output "external_dns_identity_id" {
  description = "Resource ID of the external-dns workload identity."
  value       = try(azurerm_user_assigned_identity.workload["external_dns"].id, null)
}

output "cert_manager_client_id" {
  description = "Client ID of the cert-manager workload identity, null when disabled."
  value       = try(azurerm_user_assigned_identity.workload["cert_manager"].client_id, null)
}

output "cert_manager_principal_id" {
  description = "Principal ID of the cert-manager workload identity, for role assignments you create yourself."
  value       = try(azurerm_user_assigned_identity.workload["cert_manager"].principal_id, null)
}

output "cert_manager_identity_id" {
  description = "Resource ID of the cert-manager workload identity."
  value       = try(azurerm_user_assigned_identity.workload["cert_manager"].id, null)
}

output "workload_identity_enabled_resolved" {
  description = "Which workload identities are created, after create_cluster, enabled and overrides."
  value       = local.workload_identity_enabled
}

output "workload_identity_service_accounts_resolved" {
  description = "Namespace and service account each created identity federates with."
  value       = local.enabled_workload_identities
}

# Karpenter.
output "karpenter_client_id" {
  description = "Client ID of the Karpenter controller identity, null unless mode is self-hosted. Set it on the chart's workload identity annotation."
  value       = one(azurerm_user_assigned_identity.karpenter[*].client_id)
}

output "karpenter_principal_id" {
  description = "Principal ID of the Karpenter controller identity, for extra role assignments."
  value       = one(azurerm_user_assigned_identity.karpenter[*].principal_id)
}

output "karpenter_identity_id" {
  description = "Resource ID of the Karpenter controller identity."
  value       = one(azurerm_user_assigned_identity.karpenter[*].id)
}

output "karpenter_mode_resolved" {
  description = "self-hosted, node-auto-provisioning, or disabled."
  value       = local.karpenter_mode
}

# Blob CSI.
output "blob_csi_storage_account_id" {
  description = "Resource ID of the blob CSI storage account, null when not created."
  value       = one(azurerm_storage_account.blob_csi[*].id)
}

output "blob_csi_storage_account_name" {
  description = "Name of the blob CSI storage account, null when not created. Use it as the storageAccount of a PersistentVolume."
  value       = one(azurerm_storage_account.blob_csi[*].name)
}
