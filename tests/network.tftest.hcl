# VNet, NAT Gateway and private endpoint wiring, plus the existing_vnet path.

mock_provider "azurerm" {
  source = "./tests/mocks"
}

run "defaults_create_vnet_and_nat_gateway" {
  command = plan
  assert {
    condition     = length(azurerm_virtual_network.this) == 1 && tolist(azurerm_virtual_network.this[0].address_space)[0] == "10.0.0.0/16"
    error_message = "a VNet with the default cidr must be created"
  }
  assert {
    condition     = azurerm_subnet.nodes[0].address_prefixes[0] == "10.0.0.0/22" && azurerm_subnet.nodes[0].default_outbound_access_enabled == false
    error_message = "the node subnet must use the default range and disable Azure's implicit default outbound"
  }
  assert {
    condition     = length(azurerm_subnet.database) == 0
    error_message = "no database subnet unless vnet.database_subnet_cidr is set"
  }
  assert {
    condition     = length(azurerm_nat_gateway.this) == 1 && length(azurerm_public_ip.nat) == 1 && length(azurerm_subnet_nat_gateway_association.nodes) == 1
    error_message = "NAT Gateway with one public ip must be attached to the node subnet by default"
  }
  assert {
    condition     = azurerm_nat_gateway.this[0].sku_name == "Standard" && azurerm_nat_gateway.this[0].idle_timeout_in_minutes == 4
    error_message = "NAT Gateway must be Standard with the default idle timeout"
  }
  assert {
    condition     = azurerm_public_ip.nat[0].sku == "Standard" && azurerm_public_ip.nat[0].allocation_method == "Static"
    error_message = "NAT public ips must be Standard static"
  }
  assert {
    condition     = output.outbound_type_resolved == "userAssignedNATGateway"
    error_message = "AKS egress must go through the NAT Gateway when nat_gateway is enabled"
  }
}

run "nat_disabled_leaves_egress_on_the_load_balancer" {
  command = plan
  variables {
    nat_gateway = { enabled = false }
  }
  assert {
    condition     = length(azurerm_nat_gateway.this) == 0 && length(azurerm_public_ip.nat) == 0 && length(azurerm_subnet_nat_gateway_association.nodes) == 0
    error_message = "nat_gateway.enabled = false must create no NAT resources"
  }
  assert {
    condition     = output.outbound_type_resolved == "loadBalancer"
    error_message = "without NAT, AKS egress is the load balancer"
  }
}

run "nat_public_ip_count_is_honoured" {
  command = plan
  variables {
    nat_gateway = { public_ip_count = 3, idle_timeout_minutes = 10 }
  }
  assert {
    condition     = length(azurerm_public_ip.nat) == 3 && length(azurerm_nat_gateway_public_ip_association.nat) == 3
    error_message = "every public ip must exist and be associated with the NAT Gateway"
  }
  assert {
    condition     = azurerm_nat_gateway.this[0].idle_timeout_in_minutes == 10
    error_message = "idle timeout must be passed through"
  }
}

run "database_subnet_and_service_endpoints" {
  command = plan
  variables {
    vnet = {
      database_subnet_cidr = "10.0.8.0/24"
      service_endpoints    = ["Microsoft.Storage", "Microsoft.KeyVault"]
    }
  }
  assert {
    condition     = length(azurerm_subnet.database) == 1 && azurerm_subnet.database[0].address_prefixes[0] == "10.0.8.0/24"
    error_message = "database subnet must be created from vnet.database_subnet_cidr"
  }
  assert {
    condition     = length(azurerm_subnet.nodes[0].service_endpoint) == 2
    error_message = "each service endpoint name must become a service_endpoint block on the node subnet"
  }
}

run "existing_vnet_skips_network_creation" {
  command = plan
  variables {
    existing_vnet = {
      vnet_id        = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-shared"
      node_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-shared/subnets/snet-aks"
      outbound_type  = "userDefinedRouting"
    }
  }
  assert {
    condition     = length(azurerm_virtual_network.this) == 0 && length(azurerm_subnet.nodes) == 0 && length(azurerm_nat_gateway.this) == 0
    error_message = "existing_vnet must create no VNet, subnet or NAT"
  }
  assert {
    condition     = output.node_subnet_id == "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-shared/subnets/snet-aks"
    error_message = "node_subnet_id must echo the existing subnet"
  }
  assert {
    condition     = output.outbound_type_resolved == "userDefinedRouting"
    error_message = "existing_vnet.outbound_type must drive AKS egress"
  }
}

run "private_endpoints_land_in_the_node_subnet" {
  command = plan
  variables {
    private_endpoints = {
      acr = {
        resource_id          = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-shared/providers/Microsoft.ContainerRegistry/registries/acrshared"
        subresource_names    = ["registry"]
        private_dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-dns/providers/Microsoft.Network/privateDnsZones/privatelink.azurecr.us"]
      }
      kv = {
        resource_id          = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-shared/providers/Microsoft.KeyVault/vaults/kv-shared"
        subresource_names    = ["vault"]
        private_dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-dns/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.usgovcloudapi.net"]
      }
    }
  }
  assert {
    condition     = length(azurerm_private_endpoint.node_subnet) == 2
    error_message = "one private endpoint per map entry"
  }
  assert {
    condition     = azurerm_private_endpoint.node_subnet["acr"].private_service_connection[0].subresource_names[0] == "registry" && azurerm_private_endpoint.node_subnet["acr"].private_service_connection[0].is_manual_connection == false
    error_message = "private service connection must carry the subresource and be automatic"
  }
  assert {
    condition     = azurerm_private_endpoint.node_subnet["kv"].name == "pe-platformdev-kv"
    error_message = "private endpoint names derive from the stack name and the map key"
  }
}
