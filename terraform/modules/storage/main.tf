resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  sanitized_prefix = replace(lower(var.name_prefix), "-", "")
  account_name     = "${substr(local.sanitized_prefix, 0, 16)}st${random_id.suffix.hex}"
}

resource "azurerm_storage_account" "this" {
  #checkov:skip=CKV_AZURE_33:The workload uses Blob storage only; legacy Queue service logging is not applicable to this storage design.
  #checkov:skip=CKV_AZURE_206:ZRS is intentionally used for the single-region dev baseline; geo-replication is production DR hardening.
  #checkov:skip=CKV2_AZURE_1:Platform-managed encryption with infrastructure encryption is used; customer-managed keys are reserved for compliance-driven production deployments.

  name                = local.account_name
  resource_group_name = var.resource_group_name
  location            = var.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = var.replication_type

  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  public_network_access_enabled     = false
  allow_nested_items_to_be_public   = false
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  local_user_enabled                = false
  cross_tenant_replication_enabled  = false
  infrastructure_encryption_enabled = true

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 14
    }

    container_delete_retention_policy {
      days = 14
    }
  }

  tags = var.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_storage_container" "app" {
  #checkov:skip=CKV2_AZURE_21:Legacy Storage Analytics logging is not part of the baseline; centralized observability should use the Azure Monitor diagnostic pipeline in production.

  name                  = var.container_name
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = var.resource_group_name

  tags = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                = "${var.name_prefix}-blob-dns-link"
  private_dns_zone_id = azurerm_private_dns_zone.blob.id
  virtual_network_id  = var.virtual_network_id

  registration_enabled = false

  tags = var.tags
}

resource "azurerm_private_endpoint" "blob" {
  name                = "${var.name_prefix}-blob-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "${var.name_prefix}-blob-psc"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "blob-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }

  tags = var.tags
}
