# Blob CSI: off by default; when enabled, a locked-down storage account, kubelet access and containers. The AKS driver is opt-in.

mock_provider "azurerm" {
  source = "./tests/mocks"
}

run "enabled_creates_a_locked_down_account" {
  command = plan
  variables {
    blob_csi = { enabled = true }
  }
  assert {
    condition     = azurerm_kubernetes_cluster.this[0].storage_profile[0].blob_driver_enabled == false
    error_message = "enabled leaves the AKS blob driver off; the driver comes from GitOps"
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
    blob_csi = { enabled = true }
    tags     = { Owner = "ACME", Environment = "test" }
  }
  assert {
    condition     = azurerm_storage_account.blob_csi[0].name == "acmeplatformdevcsi"
    error_message = "storage account names must be lowercase whatever the Owner tag says"
  }
}

run "long_names_are_cut_to_24" {
  command = plan
  variables {
    blob_csi = { enabled = true }
    name     = "abcdefghijklmnopqrstuvwxyz"
  }
  assert {
    condition     = length(azurerm_storage_account.blob_csi[0].name) == 24
    error_message = "the generated account name must be cut to 24 characters"
  }
}

run "no_account_when_not_requested" {
  command = plan
  variables {
    blob_csi = { enabled = true, managed_driver = true, create_storage_account = false }
  }
  assert {
    condition     = length(azurerm_storage_account.blob_csi) == 0 && length(azurerm_role_assignment.kubelet_blob_storage_account) == 0 && azurerm_kubernetes_cluster.this[0].storage_profile[0].blob_driver_enabled == true
    error_message = "the driver can be on without an account of ours"
  }
}

run "managed_driver_is_opt_in" {
  command = plan
  variables {
    blob_csi = { enabled = true, managed_driver = true }
  }
  assert {
    condition     = azurerm_kubernetes_cluster.this[0].storage_profile[0].blob_driver_enabled == true
    error_message = "managed_driver = true turns the AKS blob driver on"
  }
  assert {
    condition     = length(azurerm_storage_account.blob_csi) == 1 && length(azurerm_role_assignment.kubelet_blob_storage_account) == 1
    error_message = "the account and the kubelet grant are created either way"
  }
}

run "containers_are_created_private" {
  command = plan
  variables {
    blob_csi = { enabled = true, containers = ["assets", "lab-images"] }
  }
  assert {
    condition     = length(azurerm_storage_container.blob_csi) == 2 && azurerm_storage_container.blob_csi["assets"].name == "assets" && azurerm_storage_container.blob_csi["lab-images"].name == "lab-images"
    error_message = "one container per name in the blob CSI account"
  }
  assert {
    condition     = alltrue([for container in azurerm_storage_container.blob_csi : container.container_access_type == "private"])
    error_message = "containers are private"
  }
  assert {
    condition     = output.blob_csi_container_names == tolist(["assets", "lab-images"])
    error_message = "the output lists the container names"
  }
}

run "no_containers_without_an_account" {
  command = plan
  variables {
    blob_csi = { enabled = true, create_storage_account = false, containers = ["assets"] }
  }
  assert {
    condition     = length(azurerm_storage_container.blob_csi) == 0
    error_message = "containers need an account of ours"
  }
}

run "bad_container_name_is_rejected" {
  command = plan
  variables {
    blob_csi = { containers = ["Assets"] }
  }
  expect_failures = [var.blob_csi]
}

run "off_by_default" {
  command = plan
  assert {
    condition     = azurerm_kubernetes_cluster.this[0].storage_profile[0].blob_driver_enabled == false && length(azurerm_storage_account.blob_csi) == 0 && length(azurerm_storage_container.blob_csi) == 0
    error_message = "the blob driver is off by default and creates nothing"
  }
}

run "explicit_name_wins" {
  command = plan
  variables {
    blob_csi = { enabled = true, storage_account_name = "platformdevblobs" }
  }
  assert {
    condition     = azurerm_storage_account.blob_csi[0].name == "platformdevblobs"
    error_message = "storage_account_name must win over the generated name"
  }
}
