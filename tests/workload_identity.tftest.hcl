# Microsoft Entra Workload ID for the identities the GitOps layer patches in (external-dns, cert-manager).

mock_provider "azurerm" {
  source = "./tests/mocks"
}

run "both_identities_by_default_without_dns_grants" {
  command = plan
  assert {
    condition     = length(azurerm_user_assigned_identity.workload) == 2 && azurerm_user_assigned_identity.workload["external_dns"].name == "id-platformdev-external-dns"
    error_message = "external_dns and cert_manager identities exist by default"
  }
  assert {
    condition     = azurerm_federated_identity_credential.workload["external_dns"].subject == "system:serviceaccount:external-dns:external-dns-controller" && azurerm_federated_identity_credential.workload["cert_manager"].subject == "system:serviceaccount:cert-manager:cert-manager"
    error_message = "federated credential subjects must match the namespace/service-account pairs the GitOps overlays use"
  }
  assert {
    condition     = tolist(azurerm_federated_identity_credential.workload["external_dns"].audience) == tolist(["api://AzureADTokenExchange"])
    error_message = "audience is the Entra token exchange audience"
  }
  assert {
    condition     = length(azurerm_role_assignment.workload_dns_zone) == 0 && length(azurerm_role_assignment.external_dns_zone_resource_group) == 0
    error_message = "no DNS grants unless zones are listed; the consumer can assign roles out of band"
  }
  assert {
    condition     = output.workload_identity_enabled_resolved == { external_dns = true, cert_manager = true }
    error_message = "introspection reports both enabled"
  }
}

run "dns_zones_grant_contributor_and_reader" {
  command = plan
  variables {
    workload_identity = {
      overrides = {
        external_dns = {
          dns_zone_ids = [
            "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-dns/providers/Microsoft.Network/dnszones/example.com",
            "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-dns-b/providers/Microsoft.Network/dnszones/example.org",
          ]
        }
        cert_manager = {
          dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-dns/providers/Microsoft.Network/dnszones/example.com"]
        }
      }
    }
  }
  assert {
    condition     = length(azurerm_role_assignment.workload_dns_zone) == 3
    error_message = "one DNS Zone Contributor per identity and zone"
  }
  assert {
    condition     = azurerm_role_assignment.workload_dns_zone["external_dns_/subscriptions/00000000-0000-0000-0000-000000000002/resourcegroups/rg-dns-b/providers/microsoft.network/dnszones/example.org"].scope == "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-dns-b/providers/Microsoft.Network/dnszones/example.org" && azurerm_role_assignment.workload_dns_zone["external_dns_/subscriptions/00000000-0000-0000-0000-000000000002/resourcegroups/rg-dns-b/providers/microsoft.network/dnszones/example.org"].role_definition_name == "DNS Zone Contributor"
    error_message = "assignments are keyed <identity>_<lowercased zone id> and scoped to the zone as given"
  }
  assert {
    condition     = length(azurerm_role_assignment.external_dns_zone_resource_group) == 2 && contains(keys(azurerm_role_assignment.external_dns_zone_resource_group), "/subscriptions/00000000-0000-0000-0000-000000000002/resourcegroups/rg-dns-b")
    error_message = "external-dns gets Reader on each distinct zone resource group"
  }
}

run "override_disables_one_identity" {
  command = plan
  variables {
    workload_identity = {
      overrides = { cert_manager = { enabled = false } }
    }
  }
  assert {
    condition     = length(azurerm_user_assigned_identity.workload) == 1 && contains(keys(azurerm_user_assigned_identity.workload), "external_dns")
    error_message = "cert_manager off leaves external_dns"
  }
  assert {
    condition     = output.cert_manager_client_id == null
    error_message = "a disabled identity reports a null client id"
  }
}

run "disabled_with_one_override_on" {
  command = plan
  variables {
    workload_identity = {
      enabled   = false
      overrides = { cert_manager = { enabled = true } }
    }
  }
  assert {
    condition     = length(azurerm_user_assigned_identity.workload) == 1 && contains(keys(azurerm_user_assigned_identity.workload), "cert_manager")
    error_message = "the override must re-enable a single identity"
  }
}

run "create_false_creates_no_identities" {
  command = plan
  variables {
    create_cluster = false
  }
  assert {
    condition     = length(azurerm_user_assigned_identity.workload) == 0 && length(azurerm_federated_identity_credential.workload) == 0
    error_message = "create_cluster gates workload identities"
  }
}

run "reader_grant_dedups_resource_group_casing" {
  command = plan
  variables {
    workload_identity = {
      overrides = {
        external_dns = {
          dns_zone_ids = [
            "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-dns/providers/Microsoft.Network/dnszones/example.com",
            "/subscriptions/00000000-0000-0000-0000-000000000002/resourcegroups/RG-DNS/providers/Microsoft.Network/dnszones/example.org",
          ]
        }
      }
    }
  }
  assert {
    condition     = length(azurerm_role_assignment.external_dns_zone_resource_group) == 1 && length(azurerm_role_assignment.workload_dns_zone) == 2
    error_message = "one Reader grant per resource group regardless of id casing, one Contributor grant per zone"
  }
}
