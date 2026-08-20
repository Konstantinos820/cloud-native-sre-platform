mock_provider "azurerm" {
  override_during = plan
}

mock_provider "random" {
  override_during = plan
}

override_resource {
  target          = random_id.suffix
  override_during = plan

  values = {
    hex = "a1b2c3"
  }
}

override_resource {
  target          = azurerm_container_registry.this
  override_during = plan

  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sre-platform-dev/providers/Microsoft.ContainerRegistry/registries/sreplatformdeva1b2c3"
  }
}

override_resource {
  target          = azurerm_private_dns_zone.acr
  override_during = plan

  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sre-platform-dev/providers/Microsoft.Network/privateDnsZones/privatelink.azurecr.io"
  }
}

variables {
  name_prefix         = "sre-platform-dev"
  resource_group_name = "rg-sre-platform-dev"
  location            = "westeurope"

  private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sre-platform-dev/providers/Microsoft.Network/virtualNetworks/sre-platform-dev-vnet/subnets/sre-platform-dev-private-endpoints-subnet"

  virtual_network_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sre-platform-dev/providers/Microsoft.Network/virtualNetworks/sre-platform-dev-vnet"

  tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

run "registry_security_baseline" {
  command = plan

  assert {
    condition     = azurerm_container_registry.this.sku == "Premium"
    error_message = "ACR must remain on the Premium SKU required for Private Link."
  }

  assert {
    condition     = azurerm_container_registry.this.admin_enabled == false
    error_message = "The ACR admin account must remain disabled."
  }

  assert {
    condition     = azurerm_container_registry.this.public_network_access_enabled == false
    error_message = "ACR public network access must remain disabled."
  }

  assert {
    condition     = azurerm_container_registry.this.data_endpoint_enabled == true
    error_message = "ACR dedicated data endpoints must remain enabled."
  }

  assert {
    condition     = azurerm_container_registry.this.retention_policy_in_days == 30
    error_message = "ACR untagged manifest retention must remain at 30 days."
  }
}

run "private_dns_baseline" {
  command = plan

  assert {
    condition     = azurerm_private_dns_zone.acr.name == "privatelink.azurecr.io"
    error_message = "ACR must use the Azure Container Registry Private Link DNS zone."
  }

  assert {
    condition     = azurerm_private_dns_zone_virtual_network_link.acr.virtual_network_id == var.virtual_network_id
    error_message = "The ACR private DNS zone must remain linked to the platform VNet."
  }

  assert {
    condition     = azurerm_private_dns_zone_virtual_network_link.acr.registration_enabled == false
    error_message = "Automatic DNS registration must remain disabled for the ACR DNS link."
  }
}

run "private_endpoint_baseline" {
  command = plan

  assert {
    condition     = azurerm_private_endpoint.acr.subnet_id == var.private_endpoint_subnet_id
    error_message = "The ACR private endpoint must remain in the dedicated private-endpoint subnet."
  }

  assert {
    condition = toset(
      azurerm_private_endpoint.acr.private_service_connection[0].subresource_names
    ) == toset(["registry"])
    error_message = "The ACR private endpoint must target only the registry subresource."
  }

  assert {
    condition     = azurerm_private_endpoint.acr.private_service_connection[0].is_manual_connection == false
    error_message = "The ACR private endpoint connection must remain automatically managed."
  }

  assert {
    condition = toset(
      azurerm_private_endpoint.acr.private_dns_zone_group[0].private_dns_zone_ids
    ) == toset([azurerm_private_dns_zone.acr.id])
    error_message = "The ACR private endpoint must remain associated with its private DNS zone."
  }
}