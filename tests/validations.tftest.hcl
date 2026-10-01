# Input validations. Every run here is expected to fail on exactly one variable.

mock_provider "azurerm" {
  source = "./tests/mocks"
}

run "azure_cloud_must_be_known" {
  command = plan
  variables {
    azure_cloud = "germany"
  }
  expect_failures = [var.azure_cloud]
}

run "name_follows_dns_prefix_rules" {
  command = plan
  variables {
    name = "Bad_Name"
  }
  expect_failures = [var.name]
}

run "cluster_version_is_major_minor" {
  command = plan
  variables {
    cluster_version = "1.35.2"
  }
  expect_failures = [var.cluster_version]
}

run "kube_exec_login_mode_must_be_a_kubelogin_mode" {
  command = plan
  variables {
    kube_exec_login_mode = "password"
  }
  expect_failures = [var.kube_exec_login_mode]
}

run "nat_cannot_be_combined_with_existing_vnet" {
  command = plan
  variables {
    nat_gateway = { enabled = true }
    existing_vnet = {
      vnet_id        = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-shared"
      node_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-shared/subnets/snet-aks"
    }
  }
  # Only an explicit enabled = true conflicts; left unset with existing_vnet, there is simply no NAT Gateway.
  expect_failures = [var.nat_gateway]
}

run "existing_vnet_outbound_type_must_be_valid" {
  command = plan
  variables {
    existing_vnet = {
      vnet_id        = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-shared"
      node_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-shared/subnets/snet-aks"
      outbound_type  = "natInstance"
    }
  }
  expect_failures = [var.existing_vnet]
}

run "kube_ovn_requires_cni_node_pool_kubernetes_version" {
  command = plan
  variables {
    system_node_pool = { vm_size = "Standard_D4s_v5" }
    cni              = "kube-ovn"
  }
  expect_failures = [var.cni_node_pool]
}

run "system_pool_needs_two_nodes" {
  command = plan
  variables {
    system_node_pool = { vm_size = "Standard_D4s_v5", min_count = 1, node_count = 1 }
  }
  expect_failures = [var.system_node_pool]
}

run "system_pool_rejects_burstable_sizes" {
  command = plan
  variables {
    system_node_pool = { vm_size = "Standard_B4ms" }
  }
  expect_failures = [var.system_node_pool]
}

run "counts_must_be_ordered" {
  command = plan
  variables {
    system_node_pool = { vm_size = "Standard_D4s_v5", min_count = 3, node_count = 2, max_count = 6 }
  }
  expect_failures = [var.system_node_pool]
}

run "service_cidr_must_be_smaller_than_a_slash_12" {
  command = plan
  variables {
    system_node_pool = { vm_size = "Standard_D4s_v5" }
    service_cidr     = "10.0.0.0/12"
  }
  expect_failures = [var.service_cidr]
}

run "pod_cidr_must_avoid_aks_reserved_ranges" {
  command = plan
  variables {
    system_node_pool = { vm_size = "Standard_D4s_v5" }
    pod_cidr         = "172.30.5.0/24"
  }
  expect_failures = [var.pod_cidr]
}

run "service_cidr_must_avoid_aks_reserved_ranges" {
  command = plan
  variables {
    system_node_pool = { vm_size = "Standard_D4s_v5" }
    service_cidr     = "172.31.8.0/22"
  }
  expect_failures = [var.service_cidr]
}

run "cni_must_be_a_known_profile" {
  command = plan
  variables {
    system_node_pool = { vm_size = "Standard_D4s_v5" }
    cni              = "calico"
  }
  expect_failures = [var.cni]
}

run "azure_cni_mode_must_be_known" {
  command = plan
  variables {
    system_node_pool = { vm_size = "Standard_D4s_v5" }
    cni              = "azure-cni"
    azure_cni        = { network_plugin_mode = "flat" }
  }
  expect_failures = [var.azure_cni]
}

run "log_types_need_a_workspace" {
  command = plan
  variables {
    cluster_enabled_log_types = ["kube-apiserver"]
  }
  expect_failures = [var.cluster_log_analytics_workspace_id]
}

run "log_types_must_be_aks_categories" {
  command = plan
  variables {
    cluster_enabled_log_types          = ["api"]
    cluster_log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-ops/providers/Microsoft.OperationalInsights/workspaces/law-ops"
  }
  expect_failures = [var.cluster_enabled_log_types]
}

run "authorized_ip_ranges_need_a_public_endpoint" {
  command = plan
  variables {
    cluster_endpoint_public_access        = false
    cluster_endpoint_authorized_ip_ranges = ["203.0.113.0/24"]
  }
  expect_failures = [var.cluster_endpoint_authorized_ip_ranges]
}

run "kms_network_access_must_be_public_or_private" {
  command = plan
  variables {
    kms = { key_vault_network_access = "Hybrid" }
  }
  expect_failures = [var.kms]
}

run "kms_key_vault_name_follows_azure_rules" {
  command = plan
  variables {
    kms = { key_vault_name = "1-starts-with-a-digit" }
  }
  expect_failures = [var.kms]
}

run "sku_tier_must_be_known" {
  command = plan
  variables {
    sku_tier = "Basic"
  }
  expect_failures = [var.sku_tier]
}

run "upgrade_channels_must_be_known" {
  command = plan
  variables {
    automatic_upgrade_channel = "weekly"
  }
  expect_failures = [var.automatic_upgrade_channel]
}

run "karpenter_mode_must_be_known" {
  command = plan
  variables {
    karpenter = { mode = "managed" }
  }
  expect_failures = [var.karpenter]
}

run "blob_csi_name_must_be_a_storage_account_name" {
  command = plan
  variables {
    blob_csi = { storage_account_name = "Has-Hyphens" }
  }
  expect_failures = [var.blob_csi]
}

run "pod_cidr_must_not_overlap_service_cidr" {
  command = plan
  variables {
    pod_cidr = "10.96.0.0/16"
  }
  expect_failures = [var.pod_cidr]
}

run "pod_cidr_must_not_overlap_the_vnet" {
  command = plan
  variables {
    vnet = { cidr = "10.240.0.0/12" }
  }
  expect_failures = [var.pod_cidr]
}

run "service_cidr_must_not_overlap_the_vnet" {
  command = plan
  variables {
    vnet = { cidr = "10.96.0.0/12" }
  }
  expect_failures = [var.service_cidr]
}

run "existing_vnet_skips_the_vnet_overlap_checks" {
  command = plan
  variables {
    vnet = { cidr = "10.0.0.0/8" }
    existing_vnet = {
      vnet_id        = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-shared"
      node_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-shared/subnets/snet-aks"
    }
  }
  assert {
    condition     = length(azurerm_kubernetes_cluster.this) == 1
    error_message = "with an existing VNet the module's own vnet default must not be compared against the cidrs"
  }
}

run "dns_service_ip_must_be_inside_service_cidr" {
  command = plan
  variables {
    dns_service_ip = "10.200.0.10"
  }
  expect_failures = [var.dns_service_ip]
}

run "dns_service_ip_must_not_be_the_first_address" {
  command = plan
  variables {
    dns_service_ip = "10.96.0.1"
  }
  expect_failures = [var.dns_service_ip]
}

run "access_object_ids_must_be_unique" {
  command = plan
  variables {
    access = {
      admin_object_ids  = ["11111111-1111-1111-1111-111111111111"]
      reader_object_ids = ["11111111-1111-1111-1111-111111111111"]
    }
  }
  expect_failures = [var.access]
}
