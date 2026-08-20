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
  target          = azurerm_storage_account.this
  override_during = plan

  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sre-platform-dev/providers/Microsoft.Storage/storageAccounts/sreplatformdevsta1b2c3"
  }
}

override_resource {
  target          = azurerm_private_dns_zone.blob
  override_during = plan

  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sre-platform-dev/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
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

run "storage_security_baseline" {
  command = plan

  assert {
    condition     = azurerm_storage_account.this.account_kind == "StorageV2"
    error_message = "The storage account must remain StorageV2."
  }

  assert {
    condition     = azurerm_storage_account.this.account_tier == "Standard"
    error_message = "The dev storage account must remain on the Standard tier."
  }

  assert {
    condition     = azurerm_storage_account.this.account_replication_type == "ZRS"
    error_message = "The dev storage account must retain ZRS."
  }

  assert {
    condition     = azurerm_storage_account.this.https_traffic_only_enabled == true
    error_message = "Storage must require HTTPS traffic."
  }

  assert {
    condition     = azurerm_storage_account.this.min_tls_version == "TLS1_2"
    error_message = "Storage must require at least TLS 1.2."
  }

  assert {
    condition     = azurerm_storage_account.this.public_network_access_enabled == false
    error_message = "Storage public network access must remain disabled."
  }

  assert {
    condition     = azurerm_storage_account.this.allow_nested_items_to_be_public == false
    error_message = "Blob containers and nested items must not be publicly exposed."
  }

  assert {
    condition     = azurerm_storage_account.this.shared_access_key_enabled == false
    error_message = "Shared Key authorization must remain disabled."
  }

  assert {
    condition     = azurerm_storage_account.this.default_to_oauth_authentication == true
    error_message = "Microsoft Entra OAuth must remain the default authentication method."
  }

  assert {
    condition     = azurerm_storage_account.this.local_user_enabled == false
    error_message = "Storage local users must remain disabled."
  }

  assert {
    condition     = azurerm_storage_account.this.cross_tenant_replication_enabled == false
    error_message = "Cross-tenant replication must remain disabled."
  }

  assert {
    condition     = azurerm_storage_account.this.infrastructure_encryption_enabled == true
    error_message = "Infrastructure encryption must remain enabled."
  }
}

run "blob_data_protection_baseline" {
  command = plan

  assert {
    condition     = azurerm_storage_account.this.blob_properties[0].versioning_enabled == true
    error_message = "Blob versioning must remain enabled."
  }

  assert {
    condition     = azurerm_storage_account.this.blob_properties[0].delete_retention_policy[0].days == 14
    error_message = "Deleted blobs must retain the 14-day recovery window."
  }

  assert {
    condition     = azurerm_storage_account.this.blob_properties[0].container_delete_retention_policy[0].days == 14
    error_message = "Deleted containers must retain the 14-day recovery window."
  }

  assert {
    condition     = azurerm_storage_container.app.container_access_type == "private"
    error_message = "The application Blob container must remain private."
  }
}

run "private_connectivity_baseline" {
  command = plan

  assert {
    condition     = azurerm_private_dns_zone.blob.name == "privatelink.blob.core.windows.net"
    error_message = "Blob Storage must use the Azure Blob Private Link DNS zone."
  }

  assert {
    condition     = azurerm_private_dns_zone_virtual_network_link.blob.registration_enabled == false
    error_message = "Automatic registration must remain disabled on the Blob private DNS link."
  }

  assert {
    condition     = azurerm_private_endpoint.blob.subnet_id == var.private_endpoint_subnet_id
    error_message = "The Blob private endpoint must remain in the dedicated private-endpoint subnet."
  }

  assert {
    condition = toset(
      azurerm_private_endpoint.blob.private_service_connection[0].subresource_names
    ) == toset(["blob"])
    error_message = "The private endpoint must target only the Blob storage subresource."
  }

  assert {
    condition     = azurerm_private_endpoint.blob.private_service_connection[0].is_manual_connection == false
    error_message = "The Blob private endpoint connection must remain automatically managed."
  }

  assert {
    condition = toset(
      azurerm_private_endpoint.blob.private_dns_zone_group[0].private_dns_zone_ids
    ) == toset([azurerm_private_dns_zone.blob.id])
    error_message = "The Blob private endpoint must remain associated with its private DNS zone."
  }
}