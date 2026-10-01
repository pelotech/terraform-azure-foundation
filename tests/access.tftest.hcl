# Azure RBAC for Kubernetes: admin and reader object ids get assignments keyed by the object id.

mock_provider "azurerm" {
  source = "./tests/mocks"
}

run "admins_and_readers_get_their_roles" {
  command = plan
  variables {
    access = {
      admin_object_ids  = ["11111111-1111-1111-1111-111111111111", "22222222-2222-2222-2222-222222222222"]
      reader_object_ids = ["33333333-3333-3333-3333-333333333333"]
    }
  }
  assert {
    condition     = length(azurerm_role_assignment.access) == 6 && length([for k in keys(azurerm_role_assignment.access) : k if endswith(k, "_user")]) == 3
    error_message = "one RBAC role and one Cluster User role per principal"
  }
  assert {
    condition     = azurerm_role_assignment.access["admin_11111111-1111-1111-1111-111111111111"].role_definition_name == "Azure Kubernetes Service RBAC Cluster Admin" && azurerm_role_assignment.access["admin_22222222-2222-2222-2222-222222222222"].principal_id == "22222222-2222-2222-2222-222222222222"
    error_message = "admins get RBAC Cluster Admin under keys carrying the object id"
  }
  assert {
    condition     = azurerm_role_assignment.access["reader_33333333-3333-3333-3333-333333333333"].role_definition_name == "Azure Kubernetes Service RBAC Reader" && azurerm_role_assignment.access["reader_33333333-3333-3333-3333-333333333333"].principal_id == "33333333-3333-3333-3333-333333333333"
    error_message = "readers get RBAC Reader"
  }
  assert {
    condition     = azurerm_role_assignment.access["reader_33333333-3333-3333-3333-333333333333_user"].role_definition_name == "Azure Kubernetes Service Cluster User Role"
    error_message = "everyone gets Cluster User Role to fetch credentials"
  }
  assert {
    condition     = length(azurerm_role_assignment.access_admin_key_vault) == 2 && azurerm_role_assignment.access_admin_key_vault["11111111-1111-1111-1111-111111111111"].role_definition_name == "Key Vault Crypto Officer"
    error_message = "admins get Crypto Officer on the KMS vault"
  }
}

run "no_access_by_default" {
  command = plan
  assert {
    condition     = length(azurerm_role_assignment.access) == 0 && length(azurerm_role_assignment.access_admin_key_vault) == 0
    error_message = "empty access creates no assignments"
  }
}

run "kms_admins_follow_kms_enabled" {
  command = plan
  variables {
    kms    = { enabled = false }
    access = { admin_object_ids = ["11111111-1111-1111-1111-111111111111"] }
  }
  assert {
    condition     = length(azurerm_role_assignment.access_admin_key_vault) == 0 && length(azurerm_role_assignment.access) == 2
    error_message = "no vault means no Crypto Officer, but cluster access still applies"
  }
}

run "create_false_creates_no_access" {
  command = plan
  variables {
    create_cluster = false
    access         = { admin_object_ids = ["11111111-1111-1111-1111-111111111111"] }
  }
  assert {
    condition     = length(azurerm_role_assignment.access) == 0
    error_message = "create_cluster = false gates access assignments"
  }
}
