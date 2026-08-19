resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  server_name = lower("${var.name_prefix}-pg-${random_id.suffix.hex}")
  dns_zone    = "${var.name_prefix}.postgres.database.azure.com"
}

resource "azurerm_private_dns_zone" "postgresql" {
  name                = local.dns_zone
  resource_group_name = var.resource_group_name

  tags = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgresql" {
  name                = "${var.name_prefix}-postgresql-dns-link"
  private_dns_zone_id = azurerm_private_dns_zone.postgresql.id
  virtual_network_id  = var.virtual_network_id

  registration_enabled = false

  tags = var.tags
}

resource "azurerm_postgresql_flexible_server" "this" {
  name                = local.server_name
  resource_group_name = var.resource_group_name
  location            = var.location

  version = var.postgresql_version

  delegated_subnet_id           = var.delegated_subnet_id
  private_dns_zone_id           = azurerm_private_dns_zone.postgresql.id
  public_network_access_enabled = false

  administrator_login               = var.administrator_login
  administrator_password_wo         = var.administrator_password
  administrator_password_wo_version = var.administrator_password_version

  sku_name              = var.sku_name
  storage_mb            = var.storage_mb
  backup_retention_days = var.backup_retention_days

  geo_redundant_backup_enabled = false

  authentication {
    active_directory_auth_enabled = false
    password_auth_enabled         = true
  }

  tags = var.tags

  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.postgresql
  ]
}

resource "azurerm_postgresql_flexible_server_database" "app" {
  name      = var.database_name
  server_id = azurerm_postgresql_flexible_server.this.id

  charset   = "UTF8"
  collation = "en_US.utf8"

  lifecycle {
    prevent_destroy = true
  }
}
