# Blob CSI: driver flag on the cluster, a locked-down storage account, kubelet access.

mock_provider "azurerm" {
  source = "./tests/mocks"
}

run "defaults_create_a_locked_down_account" {
  command = plan
  assert {
    condition     = azurerm_kubernetes_cluster.this[0].storage_profile[0].blob_driver_enabled == true
    error_message = "the blob driver is on by default"
  }
  assert {
    condition     = length(azurerm_storage_account.blob_csi) == 1 && azurerm_storage_account.blob_csi[0].name == "acmeplatformdevcsi"
    error_message = "the account name is <Owner><name>csi with hyphens removed"
  }
  assert {
    condition     = azurerm_storage_account.blob_csi[0].account_kind == "StorageV2" && azurerm_storage_account.blob_csi[0].account_tier == "Standard" && azurerm_storage_account.blob_csi[0].account_replication_type == "LRS"
    error_message = "StorageV2 Standard LRS"
  }
  assert {
    condition     = azurerm_storage_account.blob_csi[0].https_traffic_only_enabled == true && azurerm_storage_account.blob_csi[0].min_tls_version == "TLS1_2" && azurerm_storage_account.blob_csi[0].allow_nested_items_to_be_public == false
    error_message = "HTTPS only, TLS 1.2, no public blobs"
  }
  assert {
    condition     = length(azurerm_role_assignment.kubelet_blob_storage_account) == 1 && azurerm_role_assignment.kubelet_blob_storage_account[0].role_definition_name == "Storage Blob Data Contributor"
    error_message = "the kubelet identity gets Storage Blob Data Contributor on the account"
  }
}

run "uppercase_owner_is_lowercased" {
  command = plan
  variables {
    tags = { Owner = "ACME", Environment = "test" }
  }
  assert {
    condition     = azurerm_storage_account.blob_csi[0].name == "acmeplatformdevcsi"
    error_message = "storage account names must be lowercase whatever the Owner tag says"
  }
}

run "long_names_are_cut_to_24" {
  command = plan
  variables {
    name = "abcdefghijklmnopqrstuvwxyz"
  }
  assert {
    condition     = length(azurerm_storage_account.blob_csi[0].name) == 24
    error_message = "the generated account name must be cut to 24 characters"
  }
}

run "no_account_when_not_requested" {
  command = plan
  variables {
    blob_csi = { create_storage_account = false }
  }
  assert {
    condition     = length(azurerm_storage_account.blob_csi) == 0 && length(azurerm_role_assignment.kubelet_blob_storage_account) == 0 && azurerm_kubernetes_cluster.this[0].storage_profile[0].blob_driver_enabled == true
    error_message = "the driver can be on without an account of ours"
  }
}

run "driver_off" {
  command = plan
  variables {
    blob_csi = { enabled = false }
  }
  assert {
    condition     = azurerm_kubernetes_cluster.this[0].storage_profile[0].blob_driver_enabled == false && length(azurerm_storage_account.blob_csi) == 0
    error_message = "enabled = false turns the driver off and creates nothing"
  }
}

run "explicit_name_wins" {
  command = plan
  variables {
    blob_csi = { storage_account_name = "platformdevblobs" }
  }
  assert {
    condition     = azurerm_storage_account.blob_csi[0].name == "platformdevblobs"
    error_message = "storage_account_name must win over the generated name"
  }
}
