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
  target          = azurerm_private_dns_zone.postgresql
  override_during = plan

  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sre-platform-dev/providers/Microsoft.Network/privateDnsZones/sre-platform-dev.postgres.database.azure.com"
  }
}

override_resource {
  target          = azurerm_postgresql_flexible_server.this
  override_during = plan

  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sre-platform-dev/providers/Microsoft.DBforPostgreSQL/flexibleServers/sre-platform-dev-pg-a1b2c3"
  }
}

variables {
  name_prefix         = "sre-platform-dev"
  resource_group_name = "rg-sre-platform-dev"
  location            = "westeurope"

  delegated_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sre-platform-dev/providers/Microsoft.Network/virtualNetworks/sre-platform-dev-vnet/subnets/sre-platform-dev-postgresql-subnet"

  virtual_network_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sre-platform-dev/providers/Microsoft.Network/virtualNetworks/sre-platform-dev-vnet"

  administrator_password = "Mock-Only-Passw0rd!2026"

  tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

run "private_networking_baseline" {
  command = plan

  assert {
    condition     = azurerm_postgresql_flexible_server.this.public_network_access_enabled == false
    error_message = "PostgreSQL public network access must remain disabled."
  }

  assert {
    condition     = azurerm_postgresql_flexible_server.this.delegated_subnet_id == var.delegated_subnet_id
    error_message = "PostgreSQL must remain attached to the delegated private subnet."
  }

  assert {
    condition     = azurerm_postgresql_flexible_server.this.private_dns_zone_id == azurerm_private_dns_zone.postgresql.id
    error_message = "PostgreSQL must remain integrated with its private DNS zone."
  }

  assert {
    condition     = azurerm_private_dns_zone_virtual_network_link.postgresql.registration_enabled == false
    error_message = "Automatic DNS registration must remain disabled for the PostgreSQL DNS link."
  }
}

run "postgresql_service_baseline" {
  command = plan

  assert {
    condition     = azurerm_postgresql_flexible_server.this.version == "16"
    error_message = "PostgreSQL major version must remain 16."
  }

  assert {
    condition     = azurerm_postgresql_flexible_server.this.sku_name == "B_Standard_B1ms"
    error_message = "The dev PostgreSQL baseline must use B_Standard_B1ms."
  }

  assert {
    condition     = azurerm_postgresql_flexible_server.this.storage_mb == 32768
    error_message = "The dev PostgreSQL baseline must retain 32 GB of storage."
  }

  assert {
    condition     = azurerm_postgresql_flexible_server.this.backup_retention_days == 7
    error_message = "PostgreSQL backups must be retained for at least the configured 7-day dev baseline."
  }

  assert {
    condition     = azurerm_postgresql_flexible_server.this.geo_redundant_backup_enabled == false
    error_message = "Geo-redundant backup must remain disabled in the single-region dev baseline."
  }
}

run "authentication_baseline" {
  command = plan

  assert {
    condition     = azurerm_postgresql_flexible_server.this.authentication[0].password_auth_enabled == true
    error_message = "PostgreSQL password authentication must remain enabled."
  }

  assert {
    condition     = azurerm_postgresql_flexible_server.this.authentication[0].active_directory_auth_enabled == false
    error_message = "Microsoft Entra authentication is not enabled in the current dev baseline."
  }
}

run "database_baseline" {
  command = plan

  assert {
    condition     = azurerm_postgresql_flexible_server_database.app.name == "app_db"
    error_message = "The application database must remain named app_db."
  }

  assert {
    condition     = azurerm_postgresql_flexible_server_database.app.charset == "UTF8"
    error_message = "The application database must use UTF8."
  }

  assert {
    condition     = azurerm_postgresql_flexible_server_database.app.collation == "en_US.utf8"
    error_message = "The application database must use en_US.utf8 collation."
  }
}