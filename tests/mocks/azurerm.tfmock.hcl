# Role assignments and federated credentials validate id shapes; the random mock strings would not pass.
mock_data "azurerm_client_config" {
  defaults = {
    tenant_id       = "00000000-0000-0000-0000-000000000001"
    subscription_id = "00000000-0000-0000-0000-000000000002"
    object_id       = "00000000-0000-0000-0000-000000000003"
    client_id       = "00000000-0000-0000-0000-000000000004"
  }
}
