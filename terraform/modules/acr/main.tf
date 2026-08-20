resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  registry_name = lower(
    replace("${var.name_prefix}${random_id.suffix.hex}", "-", "")
  )
}

resource "azurerm_container_registry" "this" {
  #checkov:skip=CKV_AZURE_166:ACR quarantine remains a preview feature and is not part of the baseline registry design.
  #checkov:skip=CKV_AZURE_233:Azure zone redundancy is automatic in supported regions and the legacy property no longer controls behavior.
  #checkov:skip=CKV_AZURE_165:This dev environment is intentionally single-region; geo-replication is production DR hardening.
  #checkov:skip=CKV_AZURE_164:Docker Content Trust is deprecated in Azure Container Registry; modern signing should use Notary Project.
  name                = local.registry_name
  resource_group_name = var.resource_group_name
  location            = var.location

  sku                           = "Premium"
  admin_enabled                 = false
  public_network_access_enabled = false
  data_endpoint_enabled         = true

  retention_policy_in_days = 30

  tags = var.tags
}

resource "azurerm_private_dns_zone" "acr" {
  name                = "privatelink.azurecr.io"
  resource_group_name = var.resource_group_name

  tags = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "acr" {
  name                = "${var.name_prefix}-acr-dns-link"
  private_dns_zone_id = azurerm_private_dns_zone.acr.id
  virtual_network_id  = var.virtual_network_id

  registration_enabled = false

  tags = var.tags
}

resource "azurerm_private_endpoint" "acr" {
  name                = "${var.name_prefix}-acr-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "${var.name_prefix}-acr-psc"
    private_connection_resource_id = azurerm_container_registry.this.id
    subresource_names              = ["registry"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "acr-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.acr.id]
  }

  tags = var.tags
}
